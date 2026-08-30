# GameChanger solution validation

These scripts validate the exported GameChanger solution without importing, publishing, or running anything in Dataverse.

## Offline validation

Run:

```powershell
& .\tools\alm\Test-GameChangerSolution.ps1
```

This parses every exported XML and JSON file, checks required solution paths, and confirms that the bracket flow contains `_new_tournamentdivisionlookup_value`.

## Offline bracket-flow inspection

Run:

```powershell
& .\tools\alm\Test-GameChangerFlow.ps1
```

This parses the exported Generate Tournament Bracket flow and reports its trigger, top-level actions, connection reference, source and destination tables, List rows filter, and Tournament Division lookup binding. It fails if the committed flow no longer uses `_new_tournamentdivisionlookup_value`, `new_tournamentteams`, `new_gamematchs`, or the expected `new_tournamentdivisions(...)` binding.

The script operates only on exported JSON. It does not contact Power Platform, run or alter a flow, or change Dataverse records.

To also create an unmanaged ZIP locally:

```powershell
& .\tools\alm\Test-GameChangerSolution.ps1 -Pack
```

Generated packages and logs go under `.artifacts`, which Git ignores.

## Microsoft Solution Checker

First run validation-only mode:

```powershell
& .\tools\alm\Invoke-GameChangerSolutionChecker.ps1
```

After explicit approval, execute:

```powershell
& .\tools\alm\Invoke-GameChangerSolutionChecker.ps1 -Execute
```

The execution validates both checkouts and the active PAC environment, packs an unmanaged solution ZIP locally, and sends that ZIP to Microsoft Solution Checker. It passes `--saveResults false`, so results are written only under `.artifacts\solution-checker` and are not saved to Dataverse.

The script never imports or publishes a solution, runs a flow, changes Dataverse records, stages files, commits, or pushes.

## Approval boundaries

Explicit approval is required before running Solution Checker because the local solution ZIP is uploaded to Microsoft's checker service. Separate approval is required before staging, committing, pushing, importing, publishing, or changing any live component.
