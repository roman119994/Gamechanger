[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('TestConnection', 'ListAllowedTables', 'DescribeAllowedTable', 'CountAllowedTables')]
    [string]$Operation,

    [Parameter()]
    [string]$LogicalName,

    [Parameter()]
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent | Split-Path -Parent) 'config\gamechanger-reader.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-Base64Url {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-ReaderConfiguration {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Reader configuration was not found: $Path"
    }

    $configuration = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $requiredProperties = @(
        'environmentUrl',
        'organizationId',
        'tenantId',
        'clientId',
        'certificateThumbprint',
        'allowedTables'
    )

    foreach ($property in $requiredProperties) {
        if (-not $configuration.PSObject.Properties.Name.Contains($property)) {
            throw "Reader configuration is missing required property '$property'."
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
    $header = @{
        alg = 'RS256'
        typ = 'JWT'
        x5t = ConvertTo-Base64Url -Bytes $certificate.GetCertHash()
    }
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
        if ($rsa) {
            $rsa.Dispose()
        }
    }

    $assertion = "$unsignedAssertion.$(ConvertTo-Base64Url -Bytes $signature)"
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body @{
        client_id = $Configuration.clientId
        client_assertion = $assertion
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        grant_type = 'client_credentials'
        scope = "$($Configuration.environmentUrl)/.default"
    }

    if (-not $tokenResponse.access_token) {
        throw 'Microsoft Entra ID did not return an access token.'
    }
    $tokenResponse.access_token
}

function New-DataverseHeaders {
    param([Parameter(Mandatory)][string]$AccessToken)

    @{
        Authorization = "Bearer $AccessToken"
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
    }
}

function Assert-AllowedTable {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][string]$TableLogicalName
    )

    if ($Configuration.allowedTables -notcontains $TableLogicalName) {
        throw "Table '$TableLogicalName' is not in the read-only allowlist."
    }
}

function Get-EntityDefinition {
    param(
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter(Mandatory)][string]$TableLogicalName
    )

    Assert-AllowedTable -Configuration $Configuration -TableLogicalName $TableLogicalName
    $uri = "{0}/api/data/v9.2/EntityDefinitions(LogicalName='{1}')?{2}select=LogicalName,SchemaName,EntitySetName,PrimaryIdAttribute,PrimaryNameAttribute" -f `
        $Configuration.environmentUrl, $TableLogicalName, '$'
    Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers
}

$config = Get-ReaderConfiguration -Path $ConfigPath
$accessToken = Get-CertificateAccessToken -Configuration $config
$headers = New-DataverseHeaders -AccessToken $accessToken

$whoAmI = Invoke-RestMethod -Method Get -Uri "$($config.environmentUrl)/api/data/v9.2/WhoAmI" -Headers $headers
if ([string]$whoAmI.OrganizationId -ne [string]$config.organizationId) {
    throw "Connected organization '$($whoAmI.OrganizationId)' does not match configured organization '$($config.organizationId)'."
}

switch ($Operation) {
    'TestConnection' {
        [pscustomobject]@{
            Status = 'Connected'
            EnvironmentUrl = $config.environmentUrl
            OrganizationId = $whoAmI.OrganizationId
            ApplicationUserId = $whoAmI.UserId
            BusinessUnitId = $whoAmI.BusinessUnitId
            CertificateExpires = (Get-Item -LiteralPath "Cert:\CurrentUser\My\$($config.certificateThumbprint)").NotAfter
        }
    }

    'ListAllowedTables' {
        foreach ($table in $config.allowedTables) {
            Get-EntityDefinition -Configuration $config -Headers $headers -TableLogicalName $table |
                Select-Object LogicalName, SchemaName, EntitySetName, PrimaryIdAttribute, PrimaryNameAttribute
        }
    }

    'DescribeAllowedTable' {
        if ([string]::IsNullOrWhiteSpace($LogicalName)) {
            throw 'DescribeAllowedTable requires -LogicalName.'
        }
        $definition = Get-EntityDefinition -Configuration $config -Headers $headers -TableLogicalName $LogicalName
        $baseUri = "$($config.environmentUrl)/api/data/v9.2/EntityDefinitions(LogicalName='$LogicalName')"
        $attributes = Invoke-RestMethod -Method Get -Uri ($baseUri + '/Attributes?$select=LogicalName,SchemaName,AttributeType,RequiredLevel') -Headers $headers
        $manyToOne = Invoke-RestMethod -Method Get -Uri ($baseUri + '/ManyToOneRelationships?$select=SchemaName,ReferencingAttribute,ReferencedEntity') -Headers $headers
        $oneToMany = Invoke-RestMethod -Method Get -Uri ($baseUri + '/OneToManyRelationships?$select=SchemaName,ReferencedAttribute,ReferencingEntity') -Headers $headers
        $choices = Invoke-RestMethod -Method Get -Uri ($baseUri + '/Attributes/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$select=LogicalName&$expand=OptionSet($select=Name,IsGlobal)') -Headers $headers

        [pscustomobject]@{
            LogicalName = $definition.LogicalName
            SchemaName = $definition.SchemaName
            EntitySetName = $definition.EntitySetName
            PrimaryIdAttribute = $definition.PrimaryIdAttribute
            PrimaryNameAttribute = $definition.PrimaryNameAttribute
            ColumnCount = $attributes.value.Count
            ManyToOneRelationshipCount = $manyToOne.value.Count
            OneToManyRelationshipCount = $oneToMany.value.Count
            ChoiceColumnCount = $choices.value.Count
            Columns = @($attributes.value | Sort-Object LogicalName)
            ManyToOneRelationships = @($manyToOne.value | Sort-Object SchemaName)
            OneToManyRelationships = @($oneToMany.value | Sort-Object SchemaName)
            ChoiceColumns = @($choices.value | Sort-Object LogicalName)
        }
    }

    'CountAllowedTables' {
        foreach ($table in $config.allowedTables) {
            $definition = Get-EntityDefinition -Configuration $config -Headers $headers -TableLogicalName $table
            $countUri = '{0}/api/data/v9.2/{1}/{2}count' -f $config.environmentUrl, $definition.EntitySetName, '$'
            $countHeaders = $headers.Clone()
            $countHeaders.Accept = 'text/plain'
            $rawCount = [string](Invoke-RestMethod -Method Get -Uri $countUri -Headers $countHeaders)
            $cleanCount = $rawCount.Trim().TrimStart([char]0xFEFF)
            [pscustomobject]@{
                LogicalName = $table
                Count = [int]::Parse($cleanCount)
            }
        }
    }
}
