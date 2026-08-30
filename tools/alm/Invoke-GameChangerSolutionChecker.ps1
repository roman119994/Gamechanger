[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Execute,

    [Parameter()]
    [string]$RepositoryRoot = 'C:\Users\moman\OneDrive\Documents\ChatGPT\GameChanger-Repository',

    [Parameter()]
    [string]$EnvironmentUrl = 'https://orgfc093633.crm.dynamics.com/'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$testScript = Join-Path $PSScriptRoot 'Test-GameChangerSolution.ps1'
if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
    throw "Solution validation script was not found: $testScript"
}

$workspaceScript = Join-Path $PSScriptRoot 'Test-GameChangerWorkspace.ps1'
if (-not (Test-Path -LiteralPath $workspaceScript -PathType Leaf)) {
    throw "Workspace validation script was not found: $workspaceScript"
}

$repositoryRootPath = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$offlineValidation = & $testScript -RepositoryRoot $repositoryRootPath
$offlineValidation

if (-not $Execute) {
    [pscustomobject]@{
        Mode = 'Validation only'
        Result = 'No package was created and Solution Checker was not run.'
        NextAction = 'Obtain explicit approval, then rerun with -Execute.'
    }
    return
}

$syncCheckout = 'C:\Users\moman\GameChanger-Sync'
& $workspaceScript `
    -MainCheckout $repositoryRootPath `
    -SyncCheckout $syncCheckout `
    -ExpectedEnvironmentUrl $EnvironmentUrl | Out-Host

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runRoot = Join-Path $repositoryRootPath ".artifacts\solution-checker\$timestamp"
$packageRoot = Join-Path $runRoot 'package'
$reportRoot = Join-Path $runRoot 'report'
$targetDescription = "local GameChanger package submitted to Microsoft Solution Checker for $EnvironmentUrl; results saved only under $reportRoot"

if (-not $PSCmdlet.ShouldProcess($targetDescription, 'Pack solution and run Solution Checker')) {
    return
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
$packResult = & $testScript -RepositoryRoot $repositoryRootPath -Pack -OutputDirectory $packageRoot
$packResult

$pacPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCLI\pac.cmd'
& $pacPath solution check `
    --environment $EnvironmentUrl `
    --path $packResult.Package `
    --outputDirectory $reportRoot `
    --ruleSet 'Solution Checker' `
    --saveResults false
if ($LASTEXITCODE -ne 0) {
    throw "Solution Checker failed with exit code $LASTEXITCODE. Any available output is under $reportRoot"
}

$reportFiles = @(Get-ChildItem -LiteralPath $reportRoot -File -Recurse | Select-Object -ExpandProperty FullName)
[pscustomobject]@{
    Mode = 'Executed'
    Result = 'Solution Checker completed. Results were not saved to Dataverse.'
    Package = $packResult.Package
    ReportDirectory = $reportRoot
    ReportFiles = $reportFiles
    NextAction = 'Review findings before approving any solution changes.'
}
