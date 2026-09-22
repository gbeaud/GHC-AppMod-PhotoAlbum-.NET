# Infra Decision Table

> This document is part of the **frozen baseline bundle**. It records, for every external dependency the migrated application talks to, whether the post-migration tests will exercise it as a **real** provisioned resource, a **testcontainer**-backed emulator/dependency, or a **mock** at the SDK / HTTP boundary.

## Metadata

| Field | Value |
|-------|-------|
| Project | PhotoAlbum |
| Module | web (Razor Pages application) |
| Migration Scope | Migrate from local file storage (wwwroot/uploads) to Azure Blob Storage AND from SQL login/password to Azure SQL Database with Managed Identity |
| Integration Test Environment | testcontainer |
| Created At | 2025-09-30 |
| infra/ Snapshot | Bicep files present at infra/main.bicep; no .md config files yet |
| Status | baseline (frozen) |

## Decision Rationale

The integration test environment is configured for **testcontainer** mode:
- Azure SQL Database: Using \mcr.microsoft.com/mssql/server\ container for SQL Server
- Azure Blob Storage: Using \mcr.microsoft.com/azure-storage/azurite\ container for emulated blob storage

Both services have mature, well-supported testcontainer images with full feature parity for the application's usage patterns (basic CRUD on SQL, blob storage upload/download/delete operations).

## Decision Table

| Dependency | Infra Match | Decision | Auth Method | Reason |
|---|---|---|---|---|
| Azure SQL Database (DefaultConnection) | No | testcontainer | username-password | Using SQL Server container (mcr.microsoft.com/mssql/server) for local testing; matches post-migration SQL target; no provisioned instance in current infra/ folder. |
| Azure Blob Storage (photo uploads container) | No | testcontainer | emulator-connection-string | Using Azurite container (mcr.microsoft.com/azure-storage/azurite) for local blob storage emulation; no provisioned storage account in current infra/ folder. |
| Configuration / Admin Credentials | N/A | mock | n/a | Admin login credentials read from appsettings.json; not a cloud service; mocked via configuration override in test environment. |

## Migration-Specific Notes

**SQL Authentication Change**: 
- Pre-migration: SQL login (username/password) in connection string
- Post-migration: Azure SQL Database + Managed Identity (system-assigned or user-assigned)
- Testcontainer mode: SQL Server container uses username-password for local development/testing; the verify-test-baseline skill must patch connection logic to use the container's basic auth when in testcontainer mode (not Managed Identity, which is Azure-specific)

**Storage Path Change**:
- Pre-migration: Local file system (\wwwroot/uploads/\)
- Post-migration: Azure Blob Storage (container + blob names)
- Testcontainer mode: Azurite emulates blob operations with identical SDK semantics; application code using \Azure.Storage.Blobs.BlobClient\ will work unchanged

**Session/Cookie Auth**:
- Admin login via cookies remains unchanged; no cloud dependency
- Marked mock (configuration-driven, not a service to connect to)
