[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('TestConnection', 'CreateTestRecord', 'UpdateTestRecord', 'GetTestRecord')]
    [string]$Operation,

    [Parameter()]
    [string]$LogicalName,

    [Parameter()]
    [string]$RecordId,

    [Parameter()]
    [string]$Name,

    [Parameter()]
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'config\gamechanger-writer.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-WriterConfiguration {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Writer configuration was not found: $Path"
    }

    $configuration = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($property in @('environmentUrl', 'organizationId', 'tenantId', 'clientId', 'certificateThumbprint', 'testPrefix', 'writeTables')) {
        if (-not $configuration.PSObject.Properties.Name.Contains($property)) {
            throw "Writer configuration is missing required property '$property'."
        }
    }

    $configuration.environmentUrl = $configuration.environmentUrl.TrimEnd('/')
    $configuration
}

function Get-CertificateAccessToken {
    param([Parameter(Mandatory)]$Configuration)

    $certificatePath = "Cert:\CurrentUser\My\$($Configuration.certificateThumbprint)"
    $certificate = Get-Item -LiteralPath $certificatePath -ErrorAction SilentlyContinue
    if (-not $certificate) {
        throw "Certificate $($Configuration.certificateThumbprint) was not found in Cert:\CurrentUser\My."
    }
    if (-not $certificate.HasPrivateKey) {
        throw 'The configured certificate does not have an accessible private key.'
    }
    if ($certificate.NotAfter -le (Get-Date)) {
        throw "The configured certificate expired on $($certificate.NotAfter.ToString('u'))."
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$($Configuration.tenantId)/oauth2/v2.0/token"
    $now = [DateTimeOffset]::UtcNow
    $header = @{ alg = 'RS256'; typ = 'JWT'; x5t = ConvertTo-Base64Url -Bytes $certificate.GetCertHash() }
    $claims = @{
        aud = $tokenEndpoint
        exp = $now.AddMinutes(5).ToUnixTimeSeconds()
        iss = $Configuration.clientId
        jti = [guid]::NewGuid().ToString()
        nbf = $now.AddMinutes(-1).ToUnixTimeSeconds()
        sub = $Configuration.clientId
    }

    $headerPart = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes(($header | ConvertTo-Json -Compress)))
    $claimsPart = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes(($claims | ConvertTo-Json -Compress)))
    $unsignedAssertion = "$headerPart.$claimsPart"
    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($certificate)
    try {
        $signature = $rsa.SignData(
            [Text.Encoding]::UTF8.GetBytes($unsignedAssertion),
            [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    }
    finally {
        if ($rsa) { $rsa.Dispose() }
    }

    $assertion = "$unsignedAssertion.$(ConvertTo-Base64Url -Bytes $signature)"
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body @{
        client_id = $Configuration.clientId
        client_assertion = $assertion
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        grant_type = 'client_credentials'
        scope = "$($Configuration.environmentUrl)/.default"
    }
    if (-not $tokenResponse.access_token) { throw 'Microsoft Entra ID did not return an access token.' }
    $tokenResponse.access_token
}

function Assert-WriteTable {
    param([Parameter(Mandatory)]$Configuration, [Parameter(Mandatory)][string]$TableLogicalName)

    if ($Configuration.writeTables -notcontains $TableLogicalName) {
        throw "Table '$TableLogicalName' is not in the controlled-write allowlist."
    }
}

function Assert-TestName {
    param([Parameter(Mandatory)]$Configuration, [Parameter(Mandatory)][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or -not $Value.StartsWith([string]$Configuration.testPrefix, [StringComparison]::Ordinal)) {
        throw "The record name must begin with '$($Configuration.testPrefix)'."
    }
}

function Get-EntityDefinition {
    param([Parameter(Mandatory)]$Configuration, [Parameter(Mandatory)][hashtable]$Headers, [Parameter(Mandatory)][string]$TableLogicalName)

    Assert-WriteTable -Configuration $Configuration -TableLogicalName $TableLogicalName
    $uri = "{0}/api/data/v9.2/EntityDefinitions(LogicalName='{1}')?{2}select=LogicalName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute" -f $Configuration.environmentUrl, $TableLogicalName, '$'
    Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
}

function Assert-RecordId {
    param([Parameter(Mandatory)][string]$Value)

    $parsed = [guid]::Empty
    if (-not [guid]::TryParse($Value.Trim('{}'), [ref]$parsed)) {
        throw "RecordId '$Value' is not a valid GUID."
    }
    $parsed.ToString()
}

$config = Get-WriterConfiguration -Path $ConfigPath
$accessToken = Get-CertificateAccessToken -Configuration $config
$headers = @{
    Authorization = "Bearer $accessToken"
    Accept = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version' = '4.0'
}
$whoAmI = Invoke-RestMethod -Method Get -Uri "$($config.environmentUrl)/api/data/v9.2/WhoAmI" -Headers $headers
if ([string]$whoAmI.OrganizationId -ne [string]$config.organizationId) {
    throw "Connected organization '$($whoAmI.OrganizationId)' does not match configured organization '$($config.organizationId)'."
}

if ($Operation -eq 'TestConnection') {
    [pscustomobject]@{
        Status = 'Connected'
        EnvironmentUrl = $config.environmentUrl
        OrganizationId = $whoAmI.OrganizationId
        ApplicationUserId = $whoAmI.UserId
        AllowedWriteTableCount = $config.writeTables.Count
        TestPrefix = $config.testPrefix
    }
    return
}

if ([string]::IsNullOrWhiteSpace($LogicalName)) {
    throw "$Operation requires -LogicalName."
}
$definition = Get-EntityDefinition -Configuration $config -Headers $headers -TableLogicalName $LogicalName

if ($Operation -eq 'CreateTestRecord') {
    if ([string]::IsNullOrWhiteSpace($Name)) { throw 'CreateTestRecord requires -Name.' }
    Assert-TestName -Configuration $config -Value $Name
    $body = @{ $definition.PrimaryNameAttribute = $Name } | ConvertTo-Json -Compress
    $response = Invoke-WebRequest -Method Post -Uri "$($config.environmentUrl)/api/data/v9.2/$($definition.EntitySetName)" -Headers $headers -ContentType 'application/json' -Body $body
    $entityUri = [string]$response.Headers['OData-EntityId']
    if (-not $entityUri) { throw 'Dataverse did not return OData-EntityId for the created record.' }
    $createdId = [regex]::Match($entityUri, '\(([0-9a-fA-F-]{36})\)$').Groups[1].Value
    [pscustomobject]@{ Status = 'Created'; LogicalName = $LogicalName; RecordId = $createdId; Name = $Name; OwnerId = $whoAmI.UserId }
    return
}

$safeRecordId = Assert-RecordId -Value $RecordId
$recordUri = "$($config.environmentUrl)/api/data/v9.2/$($definition.EntitySetName)($safeRecordId)"
$selectUri = "${recordUri}?`$select=$($definition.PrimaryNameAttribute),_ownerid_value"
$existing = Invoke-RestMethod -Method Get -Uri $selectUri -Headers $headers
$existingName = [string]$existing.($definition.PrimaryNameAttribute)
Assert-TestName -Configuration $config -Value $existingName
if ([string]$existing._ownerid_value -ne [string]$whoAmI.UserId) {
    throw "Record $safeRecordId is not owned by the writer application user."
}

if ($Operation -eq 'GetTestRecord') {
    [pscustomobject]@{ Status = 'Found'; LogicalName = $LogicalName; RecordId = $safeRecordId; Name = $existingName; OwnerId = $existing._ownerid_value }
    return
}

if ([string]::IsNullOrWhiteSpace($Name)) { throw 'UpdateTestRecord requires -Name.' }
Assert-TestName -Configuration $config -Value $Name
$updateBody = @{ $definition.PrimaryNameAttribute = $Name } | ConvertTo-Json -Compress
Invoke-RestMethod -Method Patch -Uri $recordUri -Headers $headers -ContentType 'application/json' -Body $updateBody
[pscustomobject]@{ Status = 'Updated'; LogicalName = $LogicalName; RecordId = $safeRecordId; PreviousName = $existingName; Name = $Name; OwnerId = $whoAmI.UserId }
