[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter()]
    [switch]$Execute,

    [Parameter()]
    [string]$MainCheckout = 'C:\Users\moman\OneDrive\Documents\ChatGPT\GameChanger-Repository',

    [Parameter()]
    [string]$SyncCheckout = 'C:\Users\moman\GameChanger-Sync',

    [Parameter()]
    [string]$EnvironmentUrl = 'https://orgfc093633.crm.dynamics.com/'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationScript = Join-Path $PSScriptRoot 'Test-GameChangerWorkspace.ps1'
if (-not (Test-Path -LiteralPath $validationScript -PathType Leaf)) {
    throw "Workspace validation script was not found: $validationScript"
}

$validation = @(& $validationScript -MainCheckout $MainCheckout -SyncCheckout $SyncCheckout -ExpectedEnvironmentUrl $EnvironmentUrl)
$validation

if (-not $Execute) {
    [pscustomobject]@{
        Mode = 'Validation only'
        Result = 'No PAC synchronization was run.'
        NextAction = 'Obtain explicit approval, then rerun with -Execute.'
    }
    return
}

$solutionFolder = Join-Path $SyncCheckout 'DataverseSolution\GameChanger'
$pacPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCLI\pac.cmd'
$targetDescription = "solution 'GameChanger' from $EnvironmentUrl into $solutionFolder"

if (-not $PSCmdlet.ShouldProcess($targetDescription, 'Run PAC solution sync')) {
    return
}

$preSyncStatus = @(& git -C $SyncCheckout status --porcelain=v1 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to check PAC sync checkout status: $($preSyncStatus -join [Environment]::NewLine)"
}
if ($preSyncStatus.Count -ne 0) {
    throw 'PAC sync checkout changed after validation. Synchronization was cancelled.'
}

Push-Location -LiteralPath $solutionFolder
try {
    & $pacPath solution sync `
        --environment $EnvironmentUrl `
        --solution-folder $solutionFolder `
        --packagetype Both
    if ($LASTEXITCODE -ne 0) {
        throw "PAC solution sync failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$postSyncStatus = @(& git -C $SyncCheckout status --short 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read post-sync Git status: $($postSyncStatus -join [Environment]::NewLine)"
}
$postSyncStat = @(& git -C $SyncCheckout diff --stat 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read post-sync Git diff: $($postSyncStat -join [Environment]::NewLine)"
}

[pscustomobject]@{
    Mode = 'Executed'
    Result = 'PAC solution sync completed. No files were staged, committed, pushed, imported, or published.'
    ChangedPaths = @($postSyncStatus)
    DiffSummary = @($postSyncStat)
    NextAction = 'Review the complete diff before approving any transfer or Git checkpoint.'
}
