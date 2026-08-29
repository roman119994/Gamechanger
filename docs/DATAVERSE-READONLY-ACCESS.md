# GameChanger Dataverse read-only access

## Purpose

`GameChanger.Dataverse.ReadOnly.ps1` provides certificate-authenticated, read-only inspection of the GameChanger development environment. It is intentionally narrower than PAC CLI and does not support record-content retrieval or any Dataverse mutation.

## Security model

- Microsoft Entra application: `GameChanger Codex Reader`
- Dataverse application user: `# GameChanger Codex Reader`
- Dataverse security role: `GameChanger Codex Reader`
- Private key: non-exportable, stored in the Windows Current User certificate store
- Public certificate expiration: August 29, 2027
- Client secrets: none
- Business-table access: organization-level Read on the 13 tables in `config/gamechanger-reader.json`
- Metadata access: organization-level Read on Entity, Attribute, and Relationship Entity
- Export Customizations: organization level
- Import Customizations and Publish Customizations: none

The JSON configuration contains public identifiers and an allowlist. It contains no secret or private-key material.

## Supported operations

From the repository root:

```powershell
.\tools\dataverse\GameChanger.Dataverse.ReadOnly.ps1 -Operation TestConnection

.\tools\dataverse\GameChanger.Dataverse.ReadOnly.ps1 -Operation ListAllowedTables

.\tools\dataverse\GameChanger.Dataverse.ReadOnly.ps1 `
    -Operation DescribeAllowedTable `
    -LogicalName new_gamematch

.\tools\dataverse\GameChanger.Dataverse.ReadOnly.ps1 -Operation CountAllowedTables
```

`DescribeAllowedTable` returns metadata only: table identifiers, columns, relationships, and choice definitions. `CountAllowedTables` calls the OData `/$count` endpoint and does not retrieve record fields.

## Safety boundaries

The tool:

- authenticates only to the configured tenant and environment;
- verifies the Dataverse organization ID before executing an operation;
- permits table-specific operations only for the configured allowlist;
- sends only `GET` requests to the Dataverse Web API;
- uses a short-lived access token kept only in process memory;
- never prints or saves the access token;
- never exports the certificate private key; and
- has no create, update, delete, execute-flow, import, publish, deploy, commit, or push operation.

Microsoft Entra token acquisition uses the required HTTPS `POST` to the tenant token endpoint. This request authenticates the application and does not modify Dataverse.

## Credential handling

Do not place private keys, PFX files, client secrets, access tokens, or local override files in Git. Repository ignore rules block common credential artifacts, but operators must still inspect `git diff --staged` before every commit.

The configured certificate must exist at:

```text
Cert:\CurrentUser\My\1342E94D1A4835F2D55B0120A060D842496CBE6F
```

The exported public certificate may remain outside Git at:

```text
C:\Users\moman\.gamechanger\public\GameChanger-Codex-Reader.cer
```

## Certificate rotation

Before August 29, 2027:

1. Create a replacement non-exportable certificate in the Windows Current User store.
2. Upload only its public certificate to the Entra application.
3. Update `certificateThumbprint` in `config/gamechanger-reader.json`.
4. Run `TestConnection` and the metadata tests.
5. Remove the old public certificate from Entra only after the replacement is verified.

Certificate creation, upload, configuration changes, and old-certificate removal require explicit owner approval.

## Current limitations

- No record contents can be retrieved.
- No live records can be created or changed.
- No flow can be run or modified.
- No solution can be imported, published, or deployed.
- PAC solution synchronization remains separate and must use `C:\Users\moman\GameChanger-Sync`.
- The existing `DataverseSolution\GameChanger\push-gamechanger.ps1` is not approved for autonomous use because it stages, commits, and pushes without adequate safeguards.
