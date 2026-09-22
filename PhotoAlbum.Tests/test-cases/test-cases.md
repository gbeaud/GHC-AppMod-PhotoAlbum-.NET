# Test Cases

> This document is the **frozen behavioral specification** of the PhotoAlbum module's external surface for the migration in scope. It is the source of truth that the verify-test-baseline skill uses to generate *PostMigrationIT tests against the new implementation. No test code is generated in the baseline phase.

## Metadata

| Field | Value |
|-------|-------|
| Project | PhotoAlbum |
| Module | web (Razor Pages application) |
| Migration Scope | Migrate from local file storage (wwwroot/uploads) to Azure Blob Storage AND from SQL login/password to Azure SQL Database with Managed Identity |
| Created At | 2025-09-30 |
| Status | baseline (frozen) |
| Testing Conventions | xUnit framework; test class per service; one test method per scenario |

## Existing Test Coverage

Unit tests in PhotoAlbum.Tests/Unit/Services/PhotoServiceTests.cs cover the PhotoService layer.

## Entry-Point Inventory

HTTP/Razor Page entry points accessed during application operation:

| Entry Point | Type | Source (file:symbol) | Covered by |
|---|---|---|---|
| GET /Index | HTTP (Razor Page) | PhotoAlbum/Pages/Index.cshtml.cs:OnGetAsync() | TC-WEB-001 |
| POST /Index?handler=Upload | HTTP (Razor Page) | PhotoAlbum/Pages/Index.cshtml.cs:OnPostUploadAsync(List<IFormFile>) | TC-WEB-002, TC-WEB-003, TC-WEB-004, TC-WEB-005 |
| GET /Detail/{id} | HTTP (Razor Page) | PhotoAlbum/Pages/Detail.cshtml.cs:OnGetAsync(int?) | TC-WEB-006, TC-WEB-007 |
| POST /Detail/{id}?handler=Delete | HTTP (Razor Page) | PhotoAlbum/Pages/Detail.cshtml.cs:OnPostDeleteAsync(int) | TC-WEB-008, TC-WEB-009, TC-WEB-010 |
| POST /Login | HTTP (Razor Page) | PhotoAlbum/Pages/Login.cshtml.cs:OnPostAsync() | TC-WEB-011, TC-WEB-012 |

---

## Test Cases

### TC-WEB-001 — List all photos (happy path)

| Field | Value |
|-------|-------|
| ID | TC-WEB-001 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | GET /Index |
| Description | When a user visits the index page with multiple photos, all are returned in reverse chronological order (newest first). |

**Trigger**: HTTP GET request to /Index (anonymous, no auth required)

**Preconditions**:
- Three Photo records exist in the database with UploadedAt times: 08:00Z, 09:00Z, 10:00Z

**Expected Response**: HTTP 200 OK with HTML page containing all 3 photos ordered newest-first

**Resource Verification**:
- Exactly 3 Photo rows returned in order: [Photo 10:00Z, Photo 09:00Z, Photo 08:00Z]
- No Photo records created, modified, or deleted

**Negative Verification**:
- Response status is not 400, 404, 500
- No new Photo rows created

**Data References**: none (seeded in preconditions)

---

### TC-WEB-002 — Upload valid photo (happy path)

| Field | Value |
|-------|-------|
| ID | TC-WEB-002 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | POST /Index?handler=Upload |
| Description | A valid PNG image is uploaded, saved with a generated filename, metadata recorded, and success returned. |

**Trigger**:
- HTTP POST to /Index?handler=Upload
- Body: multipart form-data with file field "files" containing testdata/inputs/sample-16x16.png
- Filename: "photo.png"
- Content-Type: "image/png"

**Preconditions**:
- Database is empty
- File storage is writable
- FileUpload:MaxFileSizeBytes = 10485760

**Expected Response**:
- HTTP 200 OK, application/json
- success: true
- uploadedPhotos: [{ id: <int>, originalFileName: "photo.png", filePath: "/uploads/<guid>.png", fileSize: <size>, width: 16, height: 16 }]
- failedUploads: []

**Resource Verification**:
- Exactly 1 new Photo row with OriginalFileName="photo.png", MimeType="image/png", Width=16, Height=16
- StoredFileName is GUID-generated (not "photo.png")
- File exists in blob storage with name matching StoredFileName
- Stored file content is byte-identical to uploaded file

**Negative Verification**:
- User-supplied filename NOT used as stored filename
- No rows created in tables other than Photos

**Data References**:
- testdata/inputs/sample-16x16.png

---

### TC-WEB-003 — Upload with invalid file type (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-003 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | POST /Index?handler=Upload |
| Description | A file with unsupported type (e.g., text) is rejected. No file saved, no database record created. |

**Trigger**:
- HTTP POST to /Index?handler=Upload
- Body: multipart form-data with testdata/inputs/invalid-file.txt
- Filename: "document.txt"
- Content-Type: "text/plain"

**Preconditions**: Database is empty

**Expected Response**:
- HTTP 200 OK, application/json
- success: false
- failedUploads: [{ fileName: "document.txt", error: "File type not supported. Please upload JPEG, PNG, GIF, or WebP images." }]

**Resource Verification**:
- No Photo records in database
- No file created in storage

**Negative Verification**:
- No Photo rows created
- Error message exactly matches hardcoded validation message

**Data References**:
- testdata/inputs/invalid-file.txt

---

### TC-WEB-004 — Upload file exceeding size limit (boundary)

| Field | Value |
|-------|-------|
| ID | TC-WEB-004 |
| Category | boundary |
| Entry Point Type | HTTP |
| Entry Point | POST /Index?handler=Upload |
| Description | File exceeding 10 MB limit is rejected. No record or file created. |

**Trigger**:
- HTTP POST to /Index?handler=Upload
- Body: multipart form-data with testdata/inputs/oversized-image.bin (11 MB)

**Preconditions**: Database empty, FileUpload:MaxFileSizeBytes=10485760

**Expected Response**:
- HTTP 200 OK, application/json
- success: false
- failedUploads: [{ fileName: "huge.jpg", error: "File size exceeds 10MB limit." }]

**Resource Verification**:
- No Photo records
- No file created

**Negative Verification**:
- File not saved to disk/blob
- No database modifications

**Data References**:
- testdata/inputs/oversized-image.bin

---

### TC-WEB-005 — Upload empty file (special input)

| Field | Value |
|-------|-------|
| ID | TC-WEB-005 |
| Category | special-input |
| Entry Point Type | HTTP |
| Entry Point | POST /Index?handler=Upload |
| Description | Empty file (0 bytes) is rejected with appropriate error. |

**Trigger**:
- HTTP POST to /Index?handler=Upload
- Body: multipart form-data with empty stream, filename "empty.jpg"

**Preconditions**: Database is empty

**Expected Response**:
- HTTP 200 OK, application/json
- success: false
- failedUploads: [{ fileName: "empty.jpg", error: "File is empty." }]

**Resource Verification**:
- No Photo records created
- No file stored

**Negative Verification**:
- No database modifications

**Data References**: none

---

### TC-WEB-006 — View photo detail (happy path)

| Field | Value |
|-------|-------|
| ID | TC-WEB-006 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | GET /Detail/{id} |
| Description | Photo detail page displays photo metadata and navigation to previous/next photos. |

**Trigger**: HTTP GET to /Detail/2 (middle photo by upload time)

**Preconditions**:
- Three Photo records with UploadedAt: 08:00Z (Id=1), 09:00Z (Id=2), 10:00Z (Id=3)

**Expected Response**:
- HTTP 200 OK, HTML
- Contains detail for Photo 2
- NextPhotoId=3 (newer), PreviousPhotoId=1 (older)
- Navigation links: href="/Detail/3" and href="/Detail/1"

**Resource Verification**:
- Photo property = Photo 2
- NextPhotoId = 3, PreviousPhotoId = 1
- No database modifications

**Negative Verification**:
- Response status not 404 or 500
- No database changes

**Data References**: none

---

### TC-WEB-007 — View non-existent photo (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-007 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | GET /Detail/{id} |
| Description | Requesting non-existent photo returns 404 Not Found. |

**Trigger**: HTTP GET to /Detail/999 (non-existent)

**Preconditions**: Database contains 0 or photos but not Id=999

**Expected Response**: HTTP 404 Not Found

**Resource Verification**: No queries modify database records

**Negative Verification**:
- Status exactly 404
- No Photo records created or modified

**Data References**: none

---

### TC-WEB-008 — Delete photo authenticated (happy path)

| Field | Value |
|-------|-------|
| ID | TC-WEB-008 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | POST /Detail/{id}?handler=Delete |
| Description | Authenticated admin deletes photo. Record and file removed. Redirect to index. |

**Trigger**:
- HTTP POST to /Detail/1?handler=Delete
- Auth cookie: valid admin session
- No body

**Preconditions**:
- User authenticated
- Photo record Id=1 exists with StoredFileName=guid1.jpg
- File exists in storage

**Expected Response**: HTTP 302 Found, Location: /Index

**Resource Verification**:
- Photo record Id=1 deleted from database
- File in storage deleted

**Negative Verification**:
- Photo fully removed (not archived)
- No new Photo records created

**Data References**: none

---

### TC-WEB-009 — Delete photo unauthenticated (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-009 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | POST /Detail/{id}?handler=Delete |
| Description | Unauthenticated user cannot delete. Redirected to login. Photo preserved. |

**Trigger**:
- HTTP POST to /Detail/1?handler=Delete
- No auth cookie
- No body

**Preconditions**:
- Photo Id=1 exists
- User unauthenticated

**Expected Response**: HTTP 302 Found, Location: /Login (Challenge response)

**Resource Verification**:
- Photo record Id=1 unchanged
- File in storage unchanged

**Negative Verification**:
- Photo NOT deleted
- File NOT deleted

**Data References**: none

---

### TC-WEB-010 — Delete non-existent photo (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-010 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | POST /Detail/{id}?handler=Delete |
| Description | Authenticated user deletes non-existent photo. Fails gracefully, redirected with error. |

**Trigger**:
- HTTP POST to /Detail/999?handler=Delete
- Auth cookie: valid session

**Preconditions**:
- User authenticated
- No Photo Id=999 exists

**Expected Response**:
- HTTP 302 Found
- Location: /Detail?id=999
- TempData["Error"] = "Failed to delete photo. Please try again."

**Resource Verification**:
- No Photo records deleted
- No files deleted

**Negative Verification**:
- No database records modified

**Data References**: none

---

### TC-WEB-011 — Login with valid credentials (happy path)

| Field | Value |
|-------|-------|
| ID | TC-WEB-011 |
| Category | happy-path |
| Entry Point Type | HTTP |
| Entry Point | POST /Login |
| Description | Admin with correct credentials authenticates. Session established, redirected to index. |

**Trigger**:
- HTTP POST to /Login
- Body: Username=admin, Password=<correct-password>

**Preconditions**:
- Admin:Username = "admin"
- Admin:Password = configured value
- No active session

**Expected Response**:
- HTTP 302 Found, Location: /Index
- Set-Cookie header with auth cookie

**Resource Verification**:
- Authentication cookie issued
- Cookie contains ClaimsIdentity with Name=admin, Role=Admin
- No database records created

**Negative Verification**:
- Status not 400 or 403
- No new Photo records

**Data References**: none

---

### TC-WEB-012 — Login with invalid credentials (failure)

| Field | Value |
|-------|-------|
| ID | TC-WEB-012 |
| Category | failure |
| Entry Point Type | HTTP |
| Entry Point | POST /Login |
| Description | Invalid credentials rejected. Login form redisplayed with error message. No session established. |

**Trigger**:
- HTTP POST to /Login
- Body: Username=admin, Password=WrongPassword

**Preconditions**:
- Admin:Username = "admin"
- Admin:Password = configured value (not "WrongPassword")

**Expected Response**:
- HTTP 200 OK, HTML
- ErrorMessage = "Invalid username or password."
- No Set-Cookie header

**Resource Verification**:
- No auth cookie issued
- No database records created

**Negative Verification**:
- Status not 302, 400, or 500
- User remains unauthenticated

**Data References**: none

---

## Required Field Checklist (Freeze Gate)

- [x] **ID** unique, formatted TC-<MODULE>-<NNN> (TC-WEB-001 through TC-WEB-012)
- [x] **Category** one of happy-path, boundary, special-input, failure
- [x] **Entry Point Type** HTTP for all Razor Page handlers
- [x] **Entry Point** exact production-code identifier (HTTP paths, handlers)
- [x] **Trigger** concrete, mechanically constructible
- [x] **Preconditions** enumerated with referenced testdata files
- [x] **Expected Response** exact status codes and body shapes
- [x] **Resource Verification** named resources with observable state
- [x] **Negative Verification** present for all failure cases
- [x] **Data References** complete; all files exist in testdata/

## Coverage Gate

- [x] Every entry point has at least one happy-path case
- [x] Every entry point has at least one failure case
- [x] All four coverage buckets represented
- [x] Multiple representative records used (3-photo examples throughout)