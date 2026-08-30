[CmdletBinding()]
param(
    [Parameter()]
    [string]$MainCheckout = 'C:\Users\moman\OneDrive\Documents\ChatGPT\GameChanger-Repository',

    [Parameter()]
    [string]$SyncCheckout = 'C:\Users\moman\GameChanger-Sync',

    [Parameter()]
    [string]$ExpectedRemote = 'https://github.com/roman119994/Gamechanger.git',

    [Parameter()]
    [string]$ExpectedEnvironmentUrl = 'https://orgfc093633.crm.dynamics.com/',

    [Parameter()]
    [string]$ExpectedSolutionName = 'GameChanger',

    [Parameter()]
    [string]$ExpectedPacProfile = 'GameChanger Dev'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Git failed in '$Repository': $($output -join [Environment]::NewLine)"
    }
    @($output)
}

function Get-RepositoryState {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Remote
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Label checkout was not found: $Path"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $gitRoot = ([string](Invoke-Git -Repository $resolvedPath -Arguments @('rev-parse', '--show-toplevel'))).Trim()
    $normalizedGitRoot = [IO.Path]::GetFullPath($gitRoot)
    $normalizedResolvedPath = [IO.Path]::GetFullPath($resolvedPath)
    if (-not [string]::Equals($normalizedGitRoot, $normalizedResolvedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label checkout root '$gitRoot' does not match expected path '$resolvedPath'."
    }

    $actualRemote = ([string](Invoke-Git -Repository $resolvedPath -Arguments @('remote', 'get-url', 'origin'))).Trim()
    if (-not [string]::Equals($actualRemote, $Remote, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label checkout origin '$actualRemote' does not match '$Remote'."
    }

    $status = @(Invoke-Git -Repository $resolvedPath -Arguments @('status', '--porcelain=v1'))
    $branch = ([string](Invoke-Git -Repository $resolvedPath -Arguments @('branch', '--show-current'))).Trim()
    $commit = ([string](Invoke-Git -Repository $resolvedPath -Arguments @('rev-parse', 'HEAD'))).Trim()

    [pscustomobject]@{
        Label = $Label
        Path = $resolvedPath
        Branch = $branch
        Commit = $commit
        Origin = $actualRemote
        Clean = ($status.Count -eq 0)
    }
}

$mainState = Get-RepositoryState -Label 'Main' -Path $MainCheckout -Remote $ExpectedRemote
if (-not $mainState.Clean) {
    throw 'Main checkout has uncommitted changes. Review or checkpoint them before PAC synchronization.'
}

$syncState = Get-RepositoryState -Label 'PAC sync' -Path $SyncCheckout -Remote $ExpectedRemote
if (-not $syncState.Clean) {
    throw 'PAC sync checkout has uncommitted changes. Review or checkpoint them before PAC synchronization.'
}
if ($syncState.Path -like '*\OneDrive\*') {
    throw 'PAC sync checkout is inside OneDrive. Use C:\Users\moman\GameChanger-Sync.'
}
if ($syncState.Branch -ne 'main') {
    throw "PAC sync checkout must be on main before synchronization; current branch is '$($syncState.Branch)'."
}

$solutionProject = Join-Path $syncState.Path 'DataverseSolution\GameChanger\GameChanger.cdsproj'
if (-not (Test-Path -LiteralPath $solutionProject -PathType Leaf)) {
    throw "GameChanger solution project was not found: $solutionProject"
}

$pacPath = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerAppsCLI\pac.cmd'
if (-not (Test-Path -LiteralPath $pacPath -PathType Leaf)) {
    throw "PAC CLI was not found: $pacPath"
}

$authOutput = @(& $pacPath auth list 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "PAC auth list failed: $($authOutput -join [Environment]::NewLine)"
}
$activeProfileLine = $authOutput | Where-Object { $_ -match '^\[\d+\]\s+\*' } | Select-Object -First 1
if (-not $activeProfileLine) {
    throw 'PAC has no active authentication profile.'
}
if ($activeProfileLine -notmatch [regex]::Escape($ExpectedPacProfile)) {
    throw "Active PAC profile is not '$ExpectedPacProfile': $activeProfileLine"
}
if ($activeProfileLine -notmatch [regex]::Escape($ExpectedEnvironmentUrl.TrimEnd('/'))) {
    throw "Active PAC profile does not target '$ExpectedEnvironmentUrl': $activeProfileLine"
}

$solutionOutput = @(& $pacPath solution list 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "PAC solution list failed: $($solutionOutput -join [Environment]::NewLine)"
}
$solutionLine = $solutionOutput | Where-Object { $_ -match ('^' + [regex]::Escape($ExpectedSolutionName) + '\s+') } | Select-Object -First 1
if (-not $solutionLine) {
    throw "Solution '$ExpectedSolutionName' was not found in the active environment."
}

[pscustomobject]@{
    Check = 'Main checkout'
    Status = 'Passed'
    Detail = "$($mainState.Branch) at $($mainState.Commit)"
}
[pscustomobject]@{
    Check = 'PAC sync checkout'
    Status = 'Passed'
    Detail = "$($syncState.Branch) at $($syncState.Commit)"
}
[pscustomobject]@{
    Check = 'PAC authentication'
    Status = 'Passed'
    Detail = "$ExpectedPacProfile -> $ExpectedEnvironmentUrl"
}
[pscustomobject]@{
    Check = 'Live solution'
    Status = 'Passed'
    Detail = $solutionLine.Trim()
}
[pscustomobject]@{
    Check = 'Solution project'
    Status = 'Passed'
    Detail = $solutionProject
}
