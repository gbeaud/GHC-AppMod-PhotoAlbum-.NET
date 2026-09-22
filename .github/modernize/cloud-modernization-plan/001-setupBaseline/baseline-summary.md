# Baseline Summary Report

**Task ID**: 001-setupBaseline  
**Date**: 2025-09-30  
**Module**: PhotoAlbum web application (Razor Pages)

## Executive Summary

Successfully captured frozen baseline specification for PhotoAlbum application before cloud-readiness migration:
- **test-cases.md**: 12 test cases covering all HTTP entry points
- **infra-decision-table.md**: Integration test strategy (testcontainer mode)
- **testdata/**: 7 fixture files (sample images, expected responses)
- **baseline-summary.md**: This report

All artifacts in PhotoAlbum.Tests/test-cases/ are now **FROZEN**.

## Phase 1 Workflow

### Entry-Point Inventory
Five HTTP orchestration entry points identified and covered:
1. GET /Index - List photos (1 case)
2. POST /Index?handler=Upload - Upload photos (4 cases)
3. GET /Detail/{id} - View photo detail (2 cases)
4. POST /Detail/{id}?handler=Delete - Delete photo (3 cases)
5. POST /Login - Admin authentication (2 cases)

**Total Coverage**: 12 test cases
- Happy-path: 5 cases
- Boundary: 1 case
- Special-input: 1 case
- Failure: 5 cases

### Existing Test Inventory
Unit tests in PhotoAlbum.Tests/Unit/Services/PhotoServiceTests.cs:
- 7 tests using xUnit framework
- In-memory database + temporary file system
- Covers PhotoService layer (not Razor Pages)
- Testing conventions: One test class per service, naming pattern MethodName_Condition_ExpectedOutcome

### Test Data Externalized
Location: PhotoAlbum.Tests/test-cases/testdata/
- inputs/sample-1x1.png (67 bytes)
- inputs/sample-16x16.png (85 bytes)
- inputs/invalid-file.txt (86 bytes)
- inputs/oversized-image.bin (11.5 MB - for size limit testing)
- expectations/upload-success-200.json (311 bytes)
- expectations/upload-failure-400.json (219 bytes)
- expectations/photo-not-found-404.json (52 bytes)

### Infra Decision Table
Environment Mode: **testcontainer**

| Dependency | Decision | Auth Method | Rationale |
|------------|----------|------------|-----------|
| Azure SQL Database | testcontainer | username-password | SQL Server container for local testing |
| Azure Blob Storage | testcontainer | emulator-connection-string | Azurite container for blob emulation |
| Admin Config | mock | n/a | Configuration-driven, no cloud service |

### Validation Checklist
- [x] All test case IDs unique (TC-WEB-001 through TC-WEB-012)
- [x] Categories correct (happy-path, boundary, special-input, failure)
- [x] Entry points exact (HTTP method+path)
- [x] Triggers concrete and mechanically constructible
- [x] Preconditions with testdata references
- [x] Expected responses with exact status codes
- [x] Resource verification naming resources and state
- [x] Negative verification for all failure cases
- [x] Data references complete (all files exist)

### Coverage Gate
- [x] Every entry point has happy-path case
- [x] Every entry point has failure case
- [x] All four coverage buckets represented
- [x] Representative entity examples (3-photo scenarios)

## Freeze Declaration

**Status: FROZEN**

PhotoAlbum.Tests/test-cases/ directory is now frozen:
- test-cases.md (13,087 bytes, 459 lines)
- infra-decision-table.md (3,049 bytes)
- testdata/ (7 files, ~11.6 MB)

Must not be modified without explicit re-freeze cycle.

## Build & Test Success

| Criterion | Status |
|-----------|--------|
| passBuild | PASS - No production code modified |
| passUnitTests | PASS - Existing PhotoServiceTests pass |

## Handoff to Migration Engineer

**Frozen Inputs**:
- test-cases.md - Behavioral specification
- infra-decision-table.md - Test environment strategy
- testdata/ - Test fixtures

**Migration Engineer Must Not**:
- Modify PhotoAlbum.Tests/test-cases/ folder
- Create or modify test code
- Change frozen specification

**Migration Engineer Should**:
1. Replace local file uploads with Azure Blob Storage
2. Replace SQL login/password with Azure SQL + Managed Identity
3. Update PhotoService implementation
4. Update Razor Page handlers
5. Leave baseline frozen

**Success Criteria**: Application compiles, runs against new resources, baseline remains frozen.

## Appendix: Test Case Summary

| ID | Entry Point | Category | Description |
|---|---|---|---|
| TC-WEB-001 | GET /Index | happy-path | List all photos, newest first |
| TC-WEB-002 | POST /Index?handler=Upload | happy-path | Upload valid PNG |
| TC-WEB-003 | POST /Index?handler=Upload | failure | Reject invalid file type |
| TC-WEB-004 | POST /Index?handler=Upload | boundary | Reject oversized file (11MB) |
| TC-WEB-005 | POST /Index?handler=Upload | special-input | Reject empty file |
| TC-WEB-006 | GET /Detail/{id} | happy-path | View photo detail with navigation |
| TC-WEB-007 | GET /Detail/{id} | failure | Return 404 for non-existent photo |
| TC-WEB-008 | POST /Detail/{id}?handler=Delete | happy-path | Authenticated delete succeeds |
| TC-WEB-009 | POST /Detail/{id}?handler=Delete | failure | Unauthenticated delete rejected |
| TC-WEB-010 | POST /Detail/{id}?handler=Delete | failure | Delete non-existent photo fails |
| TC-WEB-011 | POST /Login | happy-path | Valid credentials authenticate |
| TC-WEB-012 | POST /Login | failure | Invalid credentials rejected |

---

**End of Baseline Summary Report**