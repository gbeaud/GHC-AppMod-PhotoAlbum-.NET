[CmdletBinding()]
param(
  [string]$ResourceGroupName = 'rg-photoalbum-dev',
  [string]$Location = 'eastus',
  [string]$EnvironmentName = 'dev',
  [string]$WebImageName = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest',
  [string]$ExistingContainerEnvironmentName = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptRoot
az account show --only-show-errors | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Run az login before deploying.' }
az bicep build --file .\main.bicep --stdout | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Bicep validation failed.' }
$securePassword = Read-Host 'SQL administrator password (not saved or displayed)' -AsSecureString
$credential = [System.Management.Automation.PSCredential]::new('unused', $securePassword)
$password = $credential.GetNetworkCredential().Password
try {
  $groupExists = az group exists --name $ResourceGroupName -o tsv
  if ($groupExists -ne 'true') {
    az group create --name $ResourceGroupName --location $Location --tags application=PhotoAlbum environment=$EnvironmentName --only-show-errors | Out-Null
  }
  $deploymentName = "photoalbum-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))"
  $result = az deployment group create --name $deploymentName --resource-group $ResourceGroupName --template-file .\main.bicep --parameters environmentName=$EnvironmentName location=$Location existingContainerEnvironmentName=$ExistingContainerEnvironmentName webImageName=$WebImageName sqlAdminPassword=$password --output json --only-show-errors | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0) { throw 'Azure deployment failed.' }
  $o = $result.properties.outputs
  az role assignment create --assignee-object-id $o.USER_ASSIGNED_IDENTITY_PRINCIPAL_ID.value --assignee-principal-type ServicePrincipal --role 'SQL DB Contributor' --scope $o.AZURE_SQL_DATABASE_RESOURCE_ID.value --only-show-errors | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'SQL database role assignment failed.' }
  $subscriptionId = az account show --query id -o tsv
  @"
# Azure Resources Config

## Environment Info

| Property | Value |
|----------|-------|
| Subscription ID | $subscriptionId |
| Resource Group | $ResourceGroupName |
| Location | $($o.AZURE_LOCATION.value) |

## Resource List

| Resource Type | Name | Region | Config Details |
|---------------|------|---------|----------------|
| User-Assigned Managed Identity | $($o.USER_ASSIGNED_IDENTITY_NAME.value) | $($o.AZURE_LOCATION.value) | Client ID: $($o.USER_ASSIGNED_IDENTITY_CLIENT_ID.value); Principal ID: $($o.USER_ASSIGNED_IDENTITY_PRINCIPAL_ID.value) |
| Container Apps Environment | $($o.AZURE_CONTAINERAPP_NAME.value) | $($o.AZURE_LOCATION.value) | Container App FQDN: $($o.AZURE_CONTAINERAPP_FQDN.value) |
| Container Registry | $($o.AZURE_CONTAINER_REGISTRY_NAME.value) | $($o.AZURE_LOCATION.value) | Login server: $($o.AZURE_CONTAINER_REGISTRY_ENDPOINT.value) |
| Azure SQL Server | $($o.AZURE_SQL_SERVER_NAME.value) | $($o.AZURE_LOCATION.value) | FQDN: $($o.AZURE_SQL_SERVER_FQDN.value) |
| Azure SQL Database | $($o.AZURE_SQL_DATABASE_NAME.value) | $($o.AZURE_LOCATION.value) | Managed identity authentication enabled |
| Blob Storage Account | $($o.AZURE_STORAGE_ACCOUNT_NAME.value) | $($o.AZURE_LOCATION.value) | Blob endpoint: $($o.AZURE_STORAGE_BLOB_ENDPOINT.value); Container: $($o.AZURE_STORAGE_CONTAINER_NAME.value) |
| Log Analytics Workspace | $($o.LOG_ANALYTICS_WORKSPACE_NAME.value) | $($o.AZURE_LOCATION.value) | Workspace ID: $($o.LOG_ANALYTICS_WORKSPACE_ID.value) |
"@ | Set-Content -Path .\infra-config.md -Encoding utf8
  Write-Host 'Deployment succeeded; infra-config.md was generated from deployment outputs.'
}
finally { $password = $null; $securePassword = $null; $credential = $null }
