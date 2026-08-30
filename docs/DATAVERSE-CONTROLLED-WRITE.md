# GameChanger Dataverse controlled write access

## Purpose

`GameChanger.Dataverse.TestWriter.ps1` provides certificate-authenticated creation, update, and read-back of explicitly marked development test records. It is intended for small, owner-approved validation changes and is separate from the read-only inspection identity.

## Security model

- Microsoft Entra application: `GameChanger Codex Test Writer`
- Entra application client ID: `7011c56a-2520-4ade-84b5-feb6c614b499`
- Dataverse application user: `# GameChanger Codex Test Writer`
- Dataverse application user ID: `37ffb687-0ca4-f111-b8de-70a8a5b30651`
- Dataverse security roles: `GameChanger Codex Reader` and `GameChanger Codex Test Writer`
- Private key: non-exportable, stored in the Windows Current User certificate store
- Public certificate expiration: August 29, 2027
- Client secrets: none
- Test-record prefix: `[CODEX-TEST]`

The writer role grants Basic (user-owned) Create, Read, Write, Append, and Append To on the approved GameChanger tables. Delete, Assign, and Share remain disabled. The reader role supplies the separately documented read-only metadata and organization-level business-table access.

The JSON configuration contains public identifiers and table allowlists only. It contains no secret or private-key material.

## Approved tables

The controlled writer is restricted in both Dataverse and `config/gamechanger-writer.json` to these logical names:

- `new_division`
- `new_gamematch`
- `new_gamechangeruser`
- `new_judge`
- `new_organization`
- `new_player`
- `new_result`
- `new_team`
- `new_tournament`
- `new_tournamentdivision`
- `new_tournamentroster`
- `new_tournamentteam`
- `new_vote`
- `cr668_games`

Use the logical names above when duplicate display names exist. In particular, the approved tables are `new_team`, `new_tournamentdivision`, and `new_organization`; similarly named legacy or system tables are not approved.

## Supported operations

From the repository root:

```powershell
.\tools\dataverse\GameChanger.Dataverse.TestWriter.ps1 `
    -Operation TestConnection

.\tools\dataverse\GameChanger.Dataverse.TestWriter.ps1 `
    -Operation CreateTestRecord `
    -LogicalName cr668_games `
    -Name '[CODEX-TEST] Example'

.\tools\dataverse\GameChanger.Dataverse.TestWriter.ps1 `
    -Operation UpdateTestRecord `
    -LogicalName cr668_games `
    -RecordId '<approved-record-guid>' `
    -Name '[CODEX-TEST] Example updated'

.\tools\dataverse\GameChanger.Dataverse.TestWriter.ps1 `
    -Operation GetTestRecord `
    -LogicalName cr668_games `
    -RecordId '<approved-record-guid>'
```

## Safety boundaries

The tool:

- authenticates only to the configured tenant and environment;
- verifies the Dataverse organization ID before every operation;
- permits writes only to tables in the configured write allowlist;
- requires every created or updated name to start with `[CODEX-TEST]`;
- permits update and read-back only when the existing record has the test prefix and is owned by the writer application user;
- exposes no delete, assign, share, flow-run, import, publish, deploy, commit, or push operation;
- uses a short-lived access token kept only in process memory;
- never prints or saves the access token; and
- never exports the certificate private key.

The tool does not by itself ensure that a test record has every business-specific field needed by an app. Inspect table metadata and agree on the exact payload before extending it beyond the primary name field.

## Approval procedure

Before a create or update:

1. Confirm the development environment and exact logical table name.
2. State the exact record name and fields that will change.
3. Confirm that no existing non-test record will be touched.
4. Obtain explicit owner approval for that operation.
5. Execute one bounded operation.
6. Read the record back and report its ID, name, and owner.

Approval for one operation does not authorize a later operation. Existing Game Match records, flow execution, solution import or publication, production changes, and destructive operations always require separate explicit approval.

## Verified checkpoint

On August 30, 2026, the writer identity successfully:

1. connected to organization `4888017d-8bed-f011-aa21-6045bd081412`;
2. read metadata and counts for all 14 allowlisted tables;
3. created one record in the previously empty `cr668_games` table;
4. updated only that writer-owned record; and
5. read the record back and confirmed its writer ownership.

Verified record:

```text
Record ID: 7d892cb7-89a4-f111-b8de-70a8a5b30651
Name: [CODEX-TEST] Writer validation updated 2026-08-30
```

The validation record remains in Dataverse because the writer has no Delete privilege and the tool has no delete operation. Removal, if desired, must be performed manually after owner verification.

## Credential handling and rotation

Do not place private keys, PFX files, client secrets, access tokens, or local authentication artifacts in Git.

The configured certificate must exist at:

```text
Cert:\CurrentUser\My\BA25236FA9F89897502ACD2D0F653D15C2BA51DC
```

The exported public certificate may remain outside Git at:

```text
C:\Users\moman\.gamechanger\public\GameChanger-Codex-Test-Writer.cer
```

Before August 29, 2027:

1. Create a replacement non-exportable certificate in the Windows Current User store.
2. Upload only its public certificate to the Entra application.
3. Update `certificateThumbprint` in `config/gamechanger-writer.json`.
4. Run `TestConnection` and a read-only verification.
5. Remove the old public certificate from Entra only after the replacement is verified.

Certificate creation, upload, configuration changes, role changes, and old-certificate removal require explicit owner approval.

## Current limitations

- The writer tool handles only the primary name field.
- It cannot delete, assign, or share records.
- It cannot run or modify flows.
- It cannot import, publish, or deploy solutions.
- PAC synchronization remains separate and must use `C:\Users\moman\GameChanger-Sync`.
- Git commits and pushes remain separate, reviewable operations requiring advance notice.
