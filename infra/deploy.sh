#!/usr/bin/env bash
set -euo pipefail
RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:-rg-photoalbum-dev}"
LOCATION="${LOCATION:-eastus}"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
WEB_IMAGE_NAME="${WEB_IMAGE_NAME:-mcr.microsoft.com/azuredocs/containerapps-helloworld:latest}"
EXISTING_CONTAINER_ENVIRONMENT_NAME="${EXISTING_CONTAINER_ENVIRONMENT_NAME:-}"
cd "$(dirname "${BASH_SOURCE[0]}")"
az account show --only-show-errors >/dev/null
az bicep build --file main.bicep --stdout >/dev/null
if [[ "$(az group exists --name "$RESOURCE_GROUP_NAME" -o tsv)" != "true" ]]; then
  az group create --name "$RESOURCE_GROUP_NAME" --location "$LOCATION" --tags application=PhotoAlbum environment="$ENVIRONMENT_NAME" --only-show-errors >/dev/null
fi
read -r -s -p "SQL administrator password (not saved or displayed): " SQL_ADMIN_PASSWORD
echo
trap 'unset SQL_ADMIN_PASSWORD' EXIT
DEPLOYMENT_NAME="photoalbum-$(date -u +%Y%m%d%H%M%S)"
DEPLOYMENT="$(az deployment group create --name "$DEPLOYMENT_NAME" --resource-group "$RESOURCE_GROUP_NAME" --template-file main.bicep --parameters environmentName="$ENVIRONMENT_NAME" location="$LOCATION" existingContainerEnvironmentName="$EXISTING_CONTAINER_ENVIRONMENT_NAME" webImageName="$WEB_IMAGE_NAME" sqlAdminPassword="$SQL_ADMIN_PASSWORD" --output json --only-show-errors)"
SQL_DB_RESOURCE_ID="$(python -c 'import json,sys; print(json.loads(sys.argv[1])["properties"]["outputs"]["AZURE_SQL_DATABASE_RESOURCE_ID"]["value"])' "$DEPLOYMENT")"
IDENTITY_PRINCIPAL_ID="$(python -c 'import json,sys; print(json.loads(sys.argv[1])["properties"]["outputs"]["USER_ASSIGNED_IDENTITY_PRINCIPAL_ID"]["value"])' "$DEPLOYMENT")"
az role assignment create --assignee-object-id "$IDENTITY_PRINCIPAL_ID" --assignee-principal-type ServicePrincipal --role "SQL DB Contributor" --scope "$SQL_DB_RESOURCE_ID" --only-show-errors >/dev/null
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
python - "$DEPLOYMENT" "$SUBSCRIPTION_ID" "$RESOURCE_GROUP_NAME" <<'PY'
import json, pathlib, sys
deployment, subscription, resource_group = sys.argv[1:]
o = json.loads(deployment)["properties"]["outputs"]
v = lambda key: o[key]["value"]
pathlib.Path("infra-config.md").write_text(f"""# Azure Resources Config

## Environment Info

| Property | Value |
|----------|-------|
| Subscription ID | {subscription} |
| Resource Group | {resource_group} |
| Location | {v('AZURE_LOCATION')} |

## Resource List

| Resource Type | Name | Region | Config Details |
|---------------|------|---------|----------------|
| User-Assigned Managed Identity | {v('USER_ASSIGNED_IDENTITY_NAME')} | {v('AZURE_LOCATION')} | Client ID: {v('USER_ASSIGNED_IDENTITY_CLIENT_ID')}; Principal ID: {v('USER_ASSIGNED_IDENTITY_PRINCIPAL_ID')} |
| Container Apps Environment | {v('AZURE_CONTAINERAPP_NAME')} | {v('AZURE_LOCATION')} | Container App FQDN: {v('AZURE_CONTAINERAPP_FQDN')} |
| Container Registry | {v('AZURE_CONTAINER_REGISTRY_NAME')} | {v('AZURE_LOCATION')} | Login server: {v('AZURE_CONTAINER_REGISTRY_ENDPOINT')} |
| Azure SQL Server | {v('AZURE_SQL_SERVER_NAME')} | {v('AZURE_LOCATION')} | FQDN: {v('AZURE_SQL_SERVER_FQDN')} |
| Azure SQL Database | {v('AZURE_SQL_DATABASE_NAME')} | {v('AZURE_LOCATION')} | Managed identity authentication enabled |
| Blob Storage Account | {v('AZURE_STORAGE_ACCOUNT_NAME')} | {v('AZURE_LOCATION')} | Blob endpoint: {v('AZURE_STORAGE_BLOB_ENDPOINT')}; Container: {v('AZURE_STORAGE_CONTAINER_NAME')} |
| Log Analytics Workspace | {v('LOG_ANALYTICS_WORKSPACE_NAME')} | {v('AZURE_LOCATION')} | Workspace ID: {v('LOG_ANALYTICS_WORKSPACE_ID')} |
""", encoding="utf-8")
PY
echo "Deployment succeeded; infra-config.md was generated from deployment outputs."
