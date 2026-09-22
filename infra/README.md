# PhotoAlbum Azure Infrastructure

Modular Azure CLI (`az deployment group`) Bicep for PhotoAlbum; azd is not used.

## Resources

- Consumption Container Apps environment connected to Log Analytics
- Basic ACR with admin access disabled
- Azure SQL server and Basic database with Azure AD-only authentication
- TLS-enforced, OAuth-only StorageV2 account and private `photos` container
- User-assigned managed identity attached to the app
- Scoped ACR Pull, Storage Blob Data Contributor, and database-scoped SQL DB Contributor RBAC

## Deploy

Prerequisites: Azure CLI with Bicep support and `az login`.

```powershell
.\deploy.ps1
```

or:

```bash
./deploy.sh
```

The scripts validate Bicep, create the resource group, prompt interactively for the SQL password, and pass it only to Azure deployment. The password is never written or printed. `infra-config.md` is generated only after successful deployment from actual outputs.

`parameters.json` is the canonical non-secret parameter file. `main.parameters.json` remains as a compatibility alias. Override defaults with script parameters or `RESOURCE_GROUP_NAME`, `LOCATION`, `ENVIRONMENT_NAME`, and `WEB_IMAGE_NAME`.

## Security

Anonymous blob access and local storage keys are disabled. ACR admin access is disabled. SQL uses Azure AD-only authentication and only the Azure-services firewall rule. Add private networking and restrict ingress before production.
