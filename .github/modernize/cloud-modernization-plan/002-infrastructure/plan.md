# Infrastructure Provisioning Task: 002-infrastructure

## Objective

Provision PhotoAlbum's Azure foundation with modular Bicep and Azure CLI, without azd.

## Scope

The deployment creates a Container Apps environment, Log Analytics workspace, Basic ACR, Azure SQL server/database, Blob Storage, a user-assigned managed identity, and a Container App placeholder. The identity is attached to the app and receives ACR Pull, Storage Blob Data Contributor, and database-scoped SQL DB Contributor roles.

## Execution

1. Review `infra/main.bicep`, `infra/modules/`, and `infra/parameters.json`.
2. Run `az bicep build --file infra/main.bicep`.
3. Run `infra/deploy.ps1` or `infra/deploy.sh` after `az login`.
4. Enter the SQL administrator password interactively; it is not saved or displayed.
5. The script runs `az deployment group create` and writes `infra/infra-config.md` only after success, using actual deployment outputs.
6. Store non-secret environment identifiers in `.github/modernize/env.md` for later tasks.

## Existing environment

No `.github/modernize/env.md` was present, so defaults are `rg-photoalbum-dev`, `eastus`, and `dev`. `eastus` is used because SQL provisioning is restricted in `eastus2` for this subscription. Existing resource-group locations are preserved. These values can be overridden by script parameters or environment variables.

## Validation and security

Bicep compiles with `az bicep build`. Storage public access and local keys are disabled, ACR admin access is disabled, SQL is Azure AD-only, and no SQL allow-all firewall rule is created.
