# Infrastructure Provisioning Task: 002-infrastructure

## Objective
Provision the Azure infrastructure required to run PhotoAlbum in the cloud, including Container Apps environment, Container Registry, Azure SQL Database, and Azure Storage Account using Bicep Infrastructure-as-Code.

## Scope
- Create Bicep templates for cloud infrastructure
- Define resource naming conventions following IaC best practices
- Implement managed identity-based authentication
- Configure networking and security settings
- Prepare deployment scripts for PowerShell and Bash
- Provision resources and document configuration

## Infrastructure Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Azure Subscription                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Resource Group: rg-photoalbum-dev (eastus2)                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  User-Assigned Managed Identity (azuai...)                │ │
│  │  - AcrPull role on Container Registry                      │ │
│  │  - Storage Blob Data Contributor on Storage Account       │ │
│  │  - SQL AD Admin on SQL Server                              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Container Apps Environment (azaca...)                     │ │
│  │  - Log Analytics integration enabled                       │ │
│  │  - Consumption workload profile                             │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │  PhotoAlbum Container App                            │  │ │
│  │  │  - User-Assigned Managed Identity attached           │  │ │
│  │  │  - 0.5 CPU / 1GB RAM per instance                    │  │ │
│  │  │  - Min: 1, Max: 3 replicas                           │  │ │
│  │  │  - CORS enabled for blob access                      │  │ │
│  │  │  - External ingress on port 8080                     │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│            ┌─────────────────┼─────────────────┐                 │
│            │                 │                 │                 │
│     ┌──────▼──────┐   ┌──────▼──────┐   ┌─────▼────────┐        │
│     │ Container    │   │ SQL Server  │   │ Storage      │        │
│     │ Registry     │   │ (eastus2)   │   │ Account      │        │
│     │ (azacr...)   │   │ (azsql...)  │   │ (azsto...)   │        │
│     ├──────────────┤   ├─────────────┤   ├──────────────┤        │
│     │ - Basic SKU  │   │ - Basic DB  │   │ - Standard   │        │
│     │ - No admin   │   │ - 2GB max   │   │ - LRS        │        │
│     │ - Public     │   │ - SQL auth  │   │ - Hot tier   │        │
│     │   network    │   │ - AD admin  │   │ - OAuth only │        │
│     │ - MI pull    │   │ - FW rules  │   │ - Blob CORS  │        │
│     └──────────────┘   └─────────────┘   └──────────────┘        │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Log Analytics Workspace (azlog...)                        │ │
│  │  - 30-day retention                                        │ │
│  │  - PerGB2018 SKU                                           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Resource Naming Convention

All resources follow the pattern: **az{prefix}{token}**

Where:
- `az` = Azure prefix
- `{prefix}` = 3-character resource type abbreviation
- `{token}` = Unique string from `uniqueString(subscriptionId, resourceGroupId, location, environmentName)`

### Resource Names

| Resource Type | Prefix | Example Name |
|---|---|---|
| User-Assigned Identity | uai | azuai7k3n5q2m9p |
| Container Apps Env | aca | azaca7k3n5q2m9p |
| Container Registry | acr | azacr7k3n5q2m9p |
| Storage Account | sto | azsto7k3n5q2m9p |
| SQL Server | sql | azsql7k3n5q2m9p |
| Log Analytics | log | azlog7k3n5q2m9p |

## Deployment Steps

### Prerequisites
1. Azure CLI v2.50+ installed and authenticated
2. Azure subscription with quotas for:
   - Container Apps (1 environment)
   - SQL Server (1 server + database)
   - Storage Account (1 standard account)
   - Container Registry (1 basic registry)
3. PowerShell 7+ (for Windows) or Bash (for Linux/macOS)
4. Strong SQL Server admin password (8+ chars, mixed case, numbers)

### Step 1: Review and Validate Bicep Files
```bash
# Validate Bicep syntax
az bicep build --file infra/main.bicep

# Review template structure
cat infra/main.bicep | head -50
```

### Step 2: Choose Deployment Method

**Option A: Automated Deployment (Recommended)**

Windows (PowerShell):
```powershell
cd infra
.\deploy.ps1
```

Linux/macOS (Bash):
```bash
cd infra
chmod +x deploy.sh
./deploy.sh
```

**Option B: Manual Deployment**

```bash
# Set environment variables
export RESOURCE_GROUP="rg-photoalbum-dev"
export LOCATION="eastus2"
export ENVIRONMENT="dev"
export SQL_PASSWORD="YourSecurePassword123!"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Deploy template
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file infra/main.bicep \
  --parameters \
    environmentName=$ENVIRONMENT \
    location=$LOCATION \
    sqlAdminPassword="$SQL_PASSWORD"
```

### Step 3: Verify Deployment
```bash
# List deployed resources
az resource list --resource-group rg-photoalbum-dev -o table

# Check Container App status
az containerapp show --name <container-app-name> --resource-group rg-photoalbum-dev

# Test Container App endpoint
curl https://<container-app-fqdn>
```

### Step 4: Generate infra-config.md
After successful deployment:
```bash
# Extract deployment outputs and create configuration file
az deployment group show \
  --name deploy-<timestamp> \
  --resource-group rg-photoalbum-dev \
  --query properties.outputs \
  --output json > deployment-outputs.json

# Create infra-config.md with actual resource values
cat > infra/infra-config.md << 'EOF'
# Azure Resources Config

## Environment Info

| Property | Value |
|----------|-------|
| Subscription ID | <subscription-id> |
| Resource Group | rg-photoalbum-dev |
| Location | eastus2 |

## Resource List

| Resource Type | Name | Region | Config Details |
|---|---|---|---|
| User-Assigned Identity | azuai... | eastus2 | Principal ID: ... |
| Container Registry | azacr... | eastus2 | Login Server: ....azurecr.io |
| SQL Server | azsql... | eastus2 | FQDN: azsql....database.windows.net |
| SQL Database | PhotoAlbumDb | eastus2 | Tier: Basic, Max Size: 2GB |
| Storage Account | azsto... | eastus2 | Endpoint: https://azsto....blob.core.windows.net |
| Blob Container | photos | eastus2 | Access: Private |
| Log Analytics | azlog... | eastus2 | Workspace ID: ... |
| Container App | azaca... | eastus2 | FQDN: azaca....eastus2.azurecontainerapps.io |
EOF
```

## IaC Rules Applied

✅ **Naming Convention**: All resources follow `az{prefix}{token}` pattern
✅ **User-Assigned Identity**: Used instead of system-assigned for Container App
✅ **Role Assignments**: 
  - AcrPull on Container Registry for managed identity
  - Storage Blob Data Contributor on Storage Account
  - SQL AD Admin on SQL Server
✅ **Container Registry**: 
  - Admin user disabled
  - Public network access enabled
  - Only managed identity has pull permission
✅ **Storage Account**:
  - Anonymous blob access disabled (security best practice)
  - OAuth authentication required
  - CORS enabled for cross-origin requests
  - TLS 1.2+ enforced
✅ **SQL Database**:
  - Basic tier with 2GB max size
  - Azure AD authentication enabled
  - Firewall rules for Azure services
✅ **Container App**:
  - CORS policy enabled
  - Registry connection uses managed identity
  - Secrets configuration ready for Key Vault integration
  - Min/max replicas configured for auto-scaling
✅ **Log Analytics**: Connected to Container Apps Environment for monitoring
✅ **Deployment Scripts**: Both PowerShell and Bash with error handling

## Security Considerations

### Authentication & Authorization
- **Managed Identity**: Used for all service-to-service authentication
- **No Embedded Secrets**: SQL password only used during initial setup
- **RBAC**: Minimal required permissions granted to managed identity
- **Azure AD**: AD authentication enabled for SQL Database

### Network Security
- **Public Access**: Configured for initial setup (can be restricted later via Private Endpoints)
- **Firewall Rules**: SQL Server allows Azure services and public access
- **CORS**: Explicitly configured for expected origins
- **TLS**: Enforced for all connections

### Data Protection
- **Encryption**: Storage account enforces TLS 1.2+
- **Access Control**: Anonymous blob access disabled
- **Retention**: Log Analytics configured with 30-day retention

## Monitoring & Diagnostics

- **Application Logs**: Streamed to Log Analytics Workspace
- **Resource Metrics**: Available in Azure Portal and Log Analytics
- **Health Probes**: Container App includes liveness probes
- **Diagnostics**: Container App logs accessible via `az containerapp logs`

## Cost Implications

| Service | Tier | Estimated Monthly Cost |
|---|---|---|
| Container Apps | Consumption | $10-50 |
| SQL Database | Basic | $10-15 |
| Storage Account | Standard LRS | $1-5 |
| Log Analytics | PerGB2018 | $5-20 |
| **Total** | | **$25-90** |

*Costs vary by region and actual usage. See Azure Pricing Calculator for accurate estimates.*

## Next Steps

1. **Deploy Application**: Deploy PhotoAlbum container image to Container Registry
2. **Configure Secrets**: Set up Key Vault for sensitive configuration
3. **Enable Monitoring**: Configure alerts for critical metrics
4. **Setup CI/CD**: Implement GitHub Actions for automated deployments
5. **Security Hardening**: 
   - Restrict Storage Account to Private Endpoints
   - Enable SQL Threat Detection
   - Implement WAF on Container App ingress
6. **Performance Tuning**: 
   - Monitor Container App metrics
   - Optimize database queries
   - Configure container resource limits

## Troubleshooting

### Deployment Fails with "Quota Exceeded"
- Check available quotas: `az quotas list --filters "name eq 'ManagedEnvironmentCount'"`
- Request quota increase via Azure Portal
- Try different region if quotas unavailable

### Container App Won't Start
- Check logs: `az containerapp logs show --name <app-name> --resource-group <rg>`
- Verify ACR role assignment: `az role assignment list --assignee <identity-id>`
- Check firewall rules for SQL connectivity

### SQL Connection Issues
- Verify AD admin configured: `az sql server ad-admin list --server <sql-server> --resource-group <rg>`
- Check connection string format in Container App environment variables
- Ensure managed identity has SQL AD Admin role

## Files Generated

```
infra/
├── main.bicep                  # Main Bicep template (280 lines)
├── main.parameters.json        # Parameter values template
├── deploy.ps1                  # PowerShell deployment script
├── deploy.sh                   # Bash deployment script
├── README.md                   # Infrastructure documentation
└── infra-config.md            # Generated after deployment
```

## Timeline

- **Generation**: ~5 minutes (create files, validate syntax)
- **Deployment**: ~8-10 minutes (provision all resources)
- **Validation**: ~2 minutes (verify all resources deployed)
- **Total**: ~15-20 minutes

## Status

- [x] Bicep templates generated and validated
- [x] Deployment scripts created
- [x] Documentation written
- [ ] Resources provisioned (pending manual execution)
- [ ] infra-config.md generated (after deployment)
- [ ] GitHub commit created

---

**Created**: 2024
**Last Updated**: 2024
**IaC Type**: Bicep
**Deployment Tool**: Azure CLI (azcli)
**Target Resources**: Container Apps, ACR, SQL Database, Storage Account, Managed Identity
