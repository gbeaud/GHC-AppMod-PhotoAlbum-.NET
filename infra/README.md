# PhotoAlbum Azure Infrastructure

This directory contains the Infrastructure-as-Code (Bicep) templates to provision the Azure resources required to run PhotoAlbum in the cloud.

## Overview

The infrastructure includes:

- **Container Apps Environment**: Managed serverless container environment for running the application
- **Container Registry (ACR)**: Private container registry for storing Docker images
- **Azure SQL Database**: Managed relational database for application data
- **Azure Storage Account**: Cloud storage for photo files
- **User-Assigned Managed Identity**: Security principal for authentication without passwords
- **Log Analytics Workspace**: Monitoring and diagnostics

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Azure Resources                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Container Apps Environment                  │   │
│  │  ┌──────────────────────────────────────────────┐   │   │
│  │  │  PhotoAlbum Container App                    │   │   │
│  │  │  (User-Assigned Managed Identity)            │   │   │
│  │  └──────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                         │                                    │
│              ┌──────────┼──────────┐                         │
│              │          │          │                         │
│         ┌────▼────┐  ┌──▼──────┐ ┌┴─────────────┐           │
│         │   ACR   │  │ SQL DB  │ │Blob Storage  │           │
│         │ Private │  │ Auth AD │ │ Managed ID   │           │
│         │Reg      │  │         │ │ (OAuth)      │           │
│         └─────────┘  └─────────┘ └──────────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Azure CLI (`az`) v2.50 or later
- An Azure subscription with sufficient quota
- Docker (for building and testing images locally)
- PowerShell or Bash (for running deployment scripts)

## Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `environmentName` | Environment name (dev, staging, prod) | - | Yes |
| `location` | Azure region for resource deployment | Region of resource group | No |
| `webImageName` | Docker image for Container App | mcr.microsoft.com/azuredocs/containerapps-helloworld:latest | No |
| `sqlAdminUsername` | SQL Server admin username | sqladmin | No |
| `sqlAdminPassword` | SQL Server admin password | - | Yes |

## Resource Naming Convention

All resources are named using the pattern: `az{prefix}{token}` where:
- `az` = Azure prefix
- `{prefix}` = 3-character resource type prefix (e.g., `acr`, `sql`, `sto`, `aca`)
- `{token}` = Unique string generated from subscription, resource group, location, and environment

Examples:
- Container Registry: `azacr[token]`
- SQL Server: `azsql[token]`
- Storage Account: `azsto[token]`
- Container App: `azaca[token]`

## Deployment

### Option 1: PowerShell (Windows)

```powershell
./deploy.ps1
```

### Option 2: Bash (Linux/macOS)

```bash
./deploy.sh
```

### Manual Deployment with Azure CLI

```bash
# Set variables
$resourceGroup = "rg-photoalbum-dev"
$location = "eastus2"
$environment = "dev"
$sqlPassword = "YourSecurePassword123!"

# Create resource group
az group create --name $resourceGroup --location $location

# Deploy Bicep template
az deployment group create \
  --resource-group $resourceGroup \
  --template-file main.bicep \
  --parameters \
    environmentName=$environment \
    location=$location \
    sqlAdminPassword=$sqlPassword
```

## Output Values

After successful deployment, the following values are output:

- `AZURE_CONTAINER_REGISTRY_ENDPOINT`: ACR login server
- `AZURE_CONTAINERAPP_NAME`: Container App name
- `AZURE_CONTAINERAPP_FQDN`: Container App fully qualified domain name
- `AZURE_CONTAINERAPP_URL`: Full HTTPS URL to the Container App
- `AZURE_SQL_SERVER_FQDN`: SQL Server fully qualified domain name
- `AZURE_SQL_DATABASE_NAME`: SQL Database name
- `AZURE_STORAGE_ACCOUNT_NAME`: Storage Account name
- `AZURE_STORAGE_BLOB_ENDPOINT`: Blob storage endpoint

## Security Considerations

### Managed Identity
- User-Assigned Managed Identity is used instead of stored credentials
- No passwords stored in environment variables or configuration files
- Role-Based Access Control (RBAC) enforces least privilege

### Storage
- Anonymous blob access is disabled
- Storage account uses TLS 1.2+ for encryption in transit
- Default to OAuth authentication (no storage keys in use)
- CORS is enabled for cross-origin requests from the Container App

### SQL Database
- SQL login credentials required for initial setup
- Azure AD authentication preferred for application connections
- Firewall rules restrict access to Azure services only

### Container Registry
- Admin user access is disabled
- Only managed identity has pull permissions
- No anonymous pull access

## Monitoring

Log Analytics Workspace is automatically configured with the Container Apps Environment for monitoring:

- Application logs are captured in Log Analytics
- Resource metrics are tracked
- Performance diagnostics are available in Azure Portal
- Custom KQL (Kusto Query Language) queries can be run

## Cost Estimation

Expected monthly costs (as of 2024):
- Container Apps: ~$10-50 (Consumption pricing)
- SQL Database (Basic): ~$10-15
- Storage Account: ~$1-5 (depending on usage)
- Log Analytics: ~$5-20 (depending on data volume)

**Total estimate: $25-90/month** (varies by region and usage)

## Troubleshooting

### Deployment Fails with "Insufficient Quota"
Check available quotas for Container Apps and SQL Server in your region:
```bash
az quotas list --filters "name eq 'ManagedEnvironmentCount'" --query "[].{Name:name,Current:currentValue,Limit:limit}"
```

### Container App Cannot Pull Image
Verify ACR role assignments:
```bash
az role assignment list --assignee <managed-identity-id> --scope <acr-id>
```

### SQL Connection Issues
Check firewall rules:
```bash
az sql server firewall-rule list --resource-group <rg> --server <sql-server>
```

Check Azure AD admin configuration:
```bash
az sql server ad-admin list --resource-group <rg> --server <sql-server>
```

## Cleanup

To remove all resources:

```bash
# Delete the resource group (deletes all contained resources)
az group delete --name rg-photoalbum-dev --yes --no-wait
```

## References

- [Bicep Documentation](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/)
- [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/)
- [Azure Blob Storage](https://learn.microsoft.com/en-us/azure/storage/blobs/)
- [Managed Identities for Azure Resources](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)

## Files

- `main.bicep` - Main Bicep template
- `main.parameters.json` - Parameter values
- `deploy.ps1` - PowerShell deployment script (Windows)
- `deploy.sh` - Bash deployment script (Linux/macOS)
- `README.md` - This file
