# GameChanger PAC synchronization procedure

## Purpose

This procedure synchronizes the live unmanaged `GameChanger` solution into the dedicated PAC checkout while protecting the primary OneDrive checkout and keeping Git actions separate from Power Platform actions.

## Fixed locations

- Primary Codex and Git checkout: `C:\Users\moman\OneDrive\Documents\ChatGPT\GameChanger-Repository`
- PAC synchronization checkout: `C:\Users\moman\GameChanger-Sync`
- PAC solution project: `C:\Users\moman\GameChanger-Sync\DataverseSolution\GameChanger\GameChanger.cdsproj`
- Development environment: `https://orgfc093633.crm.dynamics.com/`
- Solution unique name: `GameChanger`

PAC synchronization must never target the OneDrive checkout. OneDrive previously denied replacement of the exported `CanvasApps` directory.

## Stage 1: validate without changing anything

From the primary repository:

```powershell
.\tools\alm\Test-GameChangerWorkspace.ps1
```

Or run the sync wrapper without `-Execute`:

```powershell
.\tools\alm\Sync-GameChangerSolution.ps1
```

Validation checks:

- both checkout paths and Git roots;
- clean working trees;
- expected GitHub remote;
- PAC checkout on `main`;
- PAC CLI installation;
- active `GameChanger Dev` profile;
- expected environment URL;
- live `GameChanger` solution; and
- local solution project.

No PAC synchronization occurs in validation mode.

## Stage 2: obtain explicit approval

Before execution, report:

- both checkout branches and commits;
- both working-tree states;
- active PAC identity and environment;
- solution unique name;
- exact PAC checkout target; and
- that synchronization will replace or modify exported solution files.

Approval to validate is not approval to synchronize. Obtain a separate explicit approval for `-Execute`.

## Stage 3: synchronize into the PAC checkout

After approval:

```powershell
.\tools\alm\Sync-GameChangerSolution.ps1 -Execute
```

PowerShell requests confirmation because the command modifies the PAC checkout. The wrapper passes the environment URL and solution folder explicitly and uses package type `Both`.

The wrapper does not stage, commit, push, reset, delete, import, publish, deploy, or run flows.

## Stage 4: review the PAC diff

Review all changed paths and the complete diff in `C:\Users\moman\GameChanger-Sync`. Pay special attention to:

- `src\Workflows` for flow-definition changes;
- `src\CanvasApps` for generated-source replacement;
- `src\Other\Customizations.xml` and `src\Other\Solution.xml` for version-only noise;
- unexpected additions or deletions; and
- the Tournament Team filter `_new_tournamentdivisionlookup_value`.

Do not discard, normalize, transfer, stage, commit, or push changes until the diff is explained and approved.

## Stage 5: transfer approved changes

Transfer into the primary checkout is a separate operation requiring approval. Preserve unrelated work and copy only reviewed solution changes. Never use a recursive delete or reset as a transfer mechanism.

After transfer:

1. run repository validation;
2. inspect `git diff --check`;
3. inspect the full diff;
4. verify expected flow expressions and lookup bindings; and
5. confirm no credentials or generated secrets are present.

## Stage 6: checkpoint and push

Staging, committing, and pushing are separate approval points. Stage only named, reviewed paths. Verify the staged diff before committing, and verify the commit before pushing a feature branch.

Never push directly to `main` as part of synchronization.

## Recovery

If PAC synchronization fails or produces an unsafe diff:

1. stop without staging or committing;
2. capture the error and `git status`;
3. inspect locked files and OneDrive involvement;
4. obtain approval before restoring or discarding anything; and
5. never use `git reset --hard`, recursive deletion, or `git clean` without explicit approval and verified paths.

## Existing unsafe helper

`DataverseSolution\GameChanger\push-gamechanger.ps1` automatically runs sync, stages all changes, requests a commit message, commits, and pushes. It lacks environment, checkout, diff, and scope guards. Do not use it for autonomous operations. It remains unchanged until a separately approved replacement or retirement plan exists.
