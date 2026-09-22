# Post-Migration Test Plan

**Phase**: Verification (Phase 3)  
**TaskId**: 005-integrationTest  
**Migration Scope**: PhotoAlbum — local file storage → Azure Blob Storage + SQL login/password → Azure SQL Database with Managed Identity  
**Test Framework**: xUnit with WebApplicationFactory  
**Infra Mode**: Testcontainer (SQL Server container + Azurite emulator)  
**Test Class Location**: `PhotoAlbum.Tests/Integration/PhotoAlbumPostMigrationIT.cs`

---

## TC→Test Mapping Table

| TC ID | Test Method Name | Entry Point | Trigger Mechanism | Fixtures Loaded | Deps Touched (real/testcontainer) | Config Source | Cleanup Path |
|---|---|---|---|---|---|---|---|
| TC-WEB-001 | tcWeb001_ListAllPhotosHappyPath | GET /Index | HTTP GET via WebApplicationFactory test client to `/` (Index page handler) | Seeded 3 photos in preconditions; no testdata files | SQL Server (testcontainer), no storage access | `appsettings.IntegrationTest.json` + environment variables from Testcontainers runtime | Not applicable (read-only) |
| TC-WEB-002 | tcWeb002_UploadValidPhotoHappyPath | POST /Index?handler=Upload | HTTP POST multipart form-data via test client to `/?handler=Upload` with IFormFile from `testdata/inputs/sample-16x16.png` | `testdata/inputs/sample-16x16.png` (16x16 PNG) | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` + Azurite connection string from container runtime | Blob delete via test client `/?handler=Upload` reverse call (cleanup within test or in `Dispose`) |
| TC-WEB-003 | tcWeb003_UploadInvalidFileTypeFailure | POST /Index?handler=Upload | HTTP POST multipart form-data via test client to `/?handler=Upload` with IFormFile from `testdata/inputs/invalid-file.txt` | `testdata/inputs/invalid-file.txt` (text file) | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` + Azurite connection string | Not applicable (no resources created) |
| TC-WEB-004 | tcWeb004_UploadFileSizeExceedsBoundary | POST /Index?handler=Upload | HTTP POST multipart form-data via test client to `/?handler=Upload` with IFormFile from `testdata/inputs/oversized-image.bin` (11 MB) | `testdata/inputs/oversized-image.bin` (11 MB binary) | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` + Azurite connection string | Not applicable (no resources created) |
| TC-WEB-005 | tcWeb005_UploadEmptyFileSpecialInput | POST /Index?handler=Upload | HTTP POST multipart form-data via test client to `/?handler=Upload` with empty file stream, filename `empty.jpg` | None (empty file constructed inline) | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` + Azurite connection string | Not applicable (no resources created) |
| TC-WEB-006 | tcWeb006_ViewPhotoDetailHappyPath | GET /Detail/{id} | HTTP GET via test client to `/Detail/2` (middle photo by upload time from preconditions) | Seeded 3 photos with ordered upload times in preconditions; no testdata files | SQL Server (testcontainer) | `appsettings.IntegrationTest.json` | Not applicable (read-only) |
| TC-WEB-007 | tcWeb007_ViewNonExistentPhotoFailure | GET /Detail/{id} | HTTP GET via test client to `/Detail/999` (non-existent photo ID) | None | SQL Server (testcontainer) | `appsettings.IntegrationTest.json` | Not applicable (read-only) |
| TC-WEB-008 | tcWeb008_DeletePhotoAuthenticatedHappyPath | POST /Detail/{id}?handler=Delete | HTTP POST via test client to `/Detail/1?handler=Delete` with valid auth cookie (authenticated admin session) | Seeded photo Id=1 with StoredFileName=guid; file in Azurite blob storage | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` + auth cookie issued via POST /Login | Not applicable (photo deleted by handler) |
| TC-WEB-009 | tcWeb009_DeletePhotoUnauthenticatedFailure | POST /Detail/{id}?handler=Delete | HTTP POST via test client to `/Detail/1?handler=Delete` WITHOUT auth cookie (unauthenticated request) | Seeded photo Id=1 in database | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` (no auth cookie) | Not applicable (photo preserved; assertion confirms) |
| TC-WEB-010 | tcWeb010_DeleteNonExistentPhotoFailure | POST /Detail/{id}?handler=Delete | HTTP POST via test client to `/Detail/999?handler=Delete` with valid auth cookie | None | Blob Storage (testcontainer: Azurite), SQL Server (testcontainer) | `appsettings.IntegrationTest.json` + auth cookie | Not applicable (photo does not exist; assertion confirms no deletion) |
| TC-WEB-011 | tcWeb011_LoginWithValidCredentialsHappyPath | POST /Login | HTTP POST via test client to `/Login` with form data Username=admin, Password=<configured-correct-password> | None (credentials from appsettings.IntegrationTest.json Admin section) | SQL Server (testcontainer) | `appsettings.IntegrationTest.json` with Admin:Username and Admin:Password | Not applicable (cookie-based; no external state to clean) |
| TC-WEB-012 | tcWeb012_LoginWithInvalidCredentialsFailure | POST /Login | HTTP POST via test client to `/Login` with form data Username=admin, Password=WrongPassword | None | SQL Server (testcontainer) | `appsettings.IntegrationTest.json` | Not applicable (login rejected; no cookie issued) |

---

## Test Infrastructure Dependencies

### Testcontainer Services

1. **SQL Server Container** (mcr.microsoft.com/mssql/server)
   - Well-known credentials: SA username/password (set via MSSQL_SA_PASSWORD env var)
   - Connection string format: `Server=<host>,<port>;User Id=sa;Password=<password>;Database=PhotoAlbumDb;Encrypt=false;`
   - Database auto-created or migrated on test startup

2. **Azurite Container** (mcr.microsoft.com/azure-storage/azurite)
   - Blob storage emulator with HTTP endpoint on port 10000
   - Well-known credentials: Account `devstoreaccount1`, Key `Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==`
   - Connection string: `DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=<key>;BlobEndpoint=http://localhost:<mapped-port>/devstoreaccount1/`

### Configuration Sources

- **appsettings.IntegrationTest.json** (test-only override)
  - ConnectionStrings:DefaultConnection (SQL Server testcontainer)
  - BlobStorage:Uri (Azurite container endpoint)
  - BlobStorage:ContainerName (hardcoded to "photos")
  - Admin:Username and Admin:Password (test user credentials)
  - IsTestEnvironment: true (skips production startup migrations)

- **Environment Variables** (injected by Testcontainers runtime)
  - SQL_PORT (dynamic, mapped from container)
  - AZURE_STORAGE_ENDPOINT (dynamic, from Azurite container)

### Authentication Strategy (Testcontainer Mode)

- **SQL Database**: Connection string with SA username/password (testcontainer mode); NOT Managed Identity
- **Blob Storage**: Connection string with account key (testcontainer mode); NOT DefaultAzureCredential/Managed Identity
- **Admin Login**: Cookie-based via appsettings credentials (unchanged from original)

---

## Test Execution Prerequisites

1. Docker daemon running (for Testcontainers)
2. Docker images pulled: `mcr.microsoft.com/mssql/server:latest`, `mcr.microsoft.com/azure-storage/azurite:latest`
3. .NET 10 SDK installed
4. xUnit test runner available via `dotnet test`
5. Testcontainers.NET NuGet package installed in PhotoAlbum.Tests

---

## Test Method Skeleton (per TC)

Each test method follows this structure:

```csharp
[Fact(DisplayName = "TC-WEB-NNN — [Description]")]
public async Task tcWebNNN_[MethodName]() 
{
    // Arrange: seed preconditions, set up test data from testdata/
    // Act: invoke HTTP handler via test client (declare Entry Point trigger)
    // Assert: verify Expected Response, Resource Verification, Negative Verification
}
```

---

## Known Issues / Gaps

- None at spec-freeze time; recheck at generation (Step 5).

---

## Next Steps

1. **Step 5**: Generate `PhotoAlbum.Tests/Integration/PhotoAlbumPostMigrationIT.cs` with 12 test methods (one per TC).
2. **Step 6**: Run tests, confirm 100% pass, validate Testcontainer dependencies are exercised.
3. **Step 9**: Generate verification-summary.md with runtime evidence.

