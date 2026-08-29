[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot = 'C:\Users\moman\OneDrive\Documents\ChatGPT\GameChanger-Repository',

    [Parameter()]
    [switch]$Pack,

    [Parameter()]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRootPath = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$solutionRoot = Join-Path $repositoryRootPath 'DataverseSolution\GameChanger'
$sourceRoot = Join-Path $solutionRoot 'src'
$solutionXml = Join-Path $sourceRoot 'Other\Solution.xml'
$customizationsXml = Join-Path $sourceRoot 'Other\Customizations.xml'
$relationshipsXml = Join-Path $sourceRoot 'Other\Relationships.xml'
$workflowRoot = Join-Path $sourceRoot 'Workflows'
$bracketFlow = Join-Path $workflowRoot 'GenerateTournamentBracket-47620259-6394-F111-8075-70A8A5B30651.json'
$expectedFilterProperty = '_new_tournamentdivisionlookup_value'

$requiredPaths = @(
    $solutionRoot,
    $sourceRoot,
    $solutionXml,
    $customizationsXml,
    $relationshipsXml,
    $workflowRoot,
    $bracketFlow
)
foreach ($path in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required solution path was not found: $path"
    }
}

$xmlFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Filter '*.xml' -File -Recurse)
$jsonFiles = @(Get-ChildItem -LiteralPath $sourceRoot -Filter '*.json' -File -Recurse)
$xmlFailures = [System.Collections.Generic.List[string]]::new()
$jsonFailures = [System.Collections.Generic.List[string]]::new()

foreach ($file in $xmlFiles) {
    try {
        [xml](Get-Content -LiteralPath $file.FullName -Raw) | Out-Null
    }
    catch {
        $xmlFailures.Add("$($file.FullName): $($_.Exception.Message)")
    }
}

foreach ($file in $jsonFiles) {
    try {
        Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json | Out-Null
    }
    catch {
        $jsonFailures.Add("$($file.FullName): $($_.Exception.Message)")
    }
}

if ($xmlFailures.Count -gt 0) {
    throw "Invalid XML files:`n$($xmlFailures -join [Environment]::NewLine)"
}
if ($jsonFailures.Count -gt 0) {
    throw "Invalid JSON files:`n$($jsonFailures -join [Environment]::NewLine)"
}

$bracketFlowText = Get-Content -LiteralPath $bracketFlow -Raw
if (-not $bracketFlowText.Contains($expectedFilterProperty)) {
    throw "Bracket flow does not contain the expected lookup property: $expectedFilterProperty"
}

$result = [ordered]@{
    Mode = if ($Pack) { 'Offline validation and local pack' } else { 'Offline validation only' }
    XmlFilesValidated = $xmlFiles.Count
    JsonFilesValidated = $jsonFiles.Count
    BracketLookupProperty = $expectedFilterProperty
    SourceRoot = $sourceRoot
    Package = $null
}

if ($Pack) {
    $pacPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCLI\pac.cmd'
    if (-not (Test-Path -LiteralPath $pacPath -PathType Leaf)) {
        throw "PAC CLI was not found: $pacPath"
    }

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path $repositoryRootPath '.artifacts\solution-validation\latest'
    }
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $outputPath = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $packagePath = Join-Path $outputPath 'GameChanger_unmanaged.zip'
    $packLog = Join-Path $outputPath 'pack.log'

    if (Test-Path -LiteralPath $packagePath) {
        Remove-Item -LiteralPath $packagePath -Force
    }

    $packOutput = @(& $pacPath solution pack `
        --zipfile $packagePath `
        --folder $sourceRoot `
        --packagetype Unmanaged `
        --log $packLog `
        --errorlevel Warning 2>&1)
    $packExitCode = $LASTEXITCODE
    if ($packExitCode -ne 0) {
        throw "PAC solution pack failed with exit code $packExitCode. Review $packLog`n$($packOutput -join [Environment]::NewLine)"
    }
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        throw "PAC reported success but the package was not created: $packagePath"
    }
    $result.Package = $packagePath
}

[pscustomobject]$result
