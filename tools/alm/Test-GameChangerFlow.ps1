[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot = 'C:\Users\moman\OneDrive\Documents\ChatGPT\GameChanger-Repository',

    [Parameter()]
    [string]$FlowFile = 'GenerateTournamentBracket-47620259-6394-F111-8075-70A8A5B30651.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRootPath = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$flowPath = Join-Path $repositoryRootPath "DataverseSolution\GameChanger\src\Workflows\$FlowFile"
if (-not (Test-Path -LiteralPath $flowPath -PathType Leaf)) {
    throw "Flow definition was not found: $flowPath"
}

$flowText = Get-Content -LiteralPath $flowPath -Raw
try {
    $flow = $flowText | ConvertFrom-Json
}
catch {
    throw "Flow definition is not valid JSON: $($_.Exception.Message)"
}

$definition = $flow.properties.definition
if (-not $definition) {
    throw 'Flow JSON does not contain properties.definition.'
}

$expectedFilter = "_new_tournamentdivisionlookup_value eq @{triggerBody()['text']}"
$expectedBinding = "@concat('new_tournamentdivisions(',triggerBody()?['text'],')')"
$listRows = $definition.actions.List_rows
$createMatch = $definition.actions.Do_until.actions.Add_a_new_row

if (-not $listRows) { throw "Required action 'List_rows' was not found." }
if (-not $createMatch) { throw "Required action 'Do_until/Add_a_new_row' was not found." }
if ([string]$listRows.inputs.parameters.'$filter' -ne $expectedFilter) {
    throw "Unexpected Tournament Team filter: $($listRows.inputs.parameters.'$filter')"
}
if ([string]$createMatch.inputs.parameters.'item/new_TournamentDivision@odata.bind' -ne $expectedBinding) {
    throw "Unexpected Tournament Division binding: $($createMatch.inputs.parameters.'item/new_TournamentDivision@odata.bind')"
}
if ([string]$listRows.inputs.parameters.entityName -ne 'new_tournamentteams') {
    throw "List_rows targets unexpected table: $($listRows.inputs.parameters.entityName)"
}
if ([string]$createMatch.inputs.parameters.entityName -ne 'new_gamematchs') {
    throw "Add_a_new_row targets unexpected table: $($createMatch.inputs.parameters.entityName)"
}

$triggerNames = @($definition.triggers.PSObject.Properties.Name)
$actionNames = @($definition.actions.PSObject.Properties.Name)
$connectionNames = @($flow.properties.connectionReferences.PSObject.Properties.Name)

[pscustomobject][ordered]@{
    Status = 'Passed'
    FlowFile = $flowPath
    Triggers = $triggerNames -join ', '
    TopLevelActions = $actionNames -join ', '
    Connections = $connectionNames -join ', '
    ListRowsTable = [string]$listRows.inputs.parameters.entityName
    ListRowsFilter = [string]$listRows.inputs.parameters.'$filter'
    CreateRowTable = [string]$createMatch.inputs.parameters.entityName
    TournamentDivisionBinding = [string]$createMatch.inputs.parameters.'item/new_TournamentDivision@odata.bind'
    ExecutesFlow = $false
    ContactsPowerPlatform = $false
}
