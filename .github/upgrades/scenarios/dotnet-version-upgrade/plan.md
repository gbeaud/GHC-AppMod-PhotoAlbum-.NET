# .NET 10.0 Upgrade Plan

## Upgrade Strategy

**Target Framework**: net10.0  
**Current Framework**: net9.0 (both projects)  
**Scope**: PhotoAlbum (ASP.NET Core web app) + PhotoAlbum.Tests (test project)

## Package Upgrades Required

| Package | Current | Target |
|---------|---------|--------|
| Microsoft.AspNetCore.Mvc.Testing | 9.0.9 | 10.0.12 |
| Microsoft.EntityFrameworkCore.Design | 9.0.9 | 10.0.12 |
| Microsoft.EntityFrameworkCore.InMemory | 9.0.9 | 10.0.12 |
| Microsoft.EntityFrameworkCore.SqlServer | 9.0.9 | 10.0.12 |

**Compatible Packages** (no change needed):
- coverlet.collector (6.0.2)
- Microsoft.NET.Test.Sdk (17.12.0)
- SixLabors.ImageSharp (3.1.11)
- xunit (2.9.2)
- xunit.runner.visualstudio (2.8.2)

## Execution Order

Following topological order (dependencies first):

1. **Task 01-upgrade-photoalbum**: Upgrade PhotoAlbum.csproj
   - Update target framework from net9.0 to net10.0
   - Upgrade all dependent packages

2. **Task 02-upgrade-photoalbum-tests**: Upgrade PhotoAlbum.Tests.csproj
   - Update target framework from net9.0 to net10.0
   - Upgrade all dependent packages

3. **Task 03-validate-build**: Build and validate the solution
   - Build both projects
   - Fix any warnings or errors

4. **Task 04-run-tests**: Run unit tests to verify functionality
   - Execute all tests
   - Ensure 100% pass rate

## Risk Assessment

- **Difficulty**: Low (both projects have 0 API issues, straightforward package updates)
- **Breaking Changes**: None detected in assessment
- **Testing Coverage**: PhotoAlbum.Tests provides validation
- **Rollback Path**: Simple version revert if needed

## Success Criteria

✅ Both projects target net10.0  
✅ All packages upgraded to net10.0 compatible versions  
✅ Solution builds without errors or warnings  
✅ All unit tests pass  
✅ No dependency conflicts  

