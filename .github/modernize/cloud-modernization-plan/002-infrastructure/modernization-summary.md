# Modernization Summary: 002-infrastructure

PhotoAlbum infrastructure was modularized into Azure CLI Bicep. The implementation provisions Container Apps, ACR, Azure SQL Database, Blob Storage, Log Analytics, and a user-assigned managed identity with scoped RBAC. Deployment scripts use an interactive secure SQL password and generate actual endpoint/identity configuration only after successful provisioning.

Validation: `az bicep build --file infra/main.bicep` passes.
