# PhotoAlbum.Tests\PhotoAlbum.Tests.csproj

[← Back to the assessment index](../../assessment.md)

## Project Info

- **Current Target Framework:** net9.0
- **Proposed Target Framework:** net10.0
- **SDK-style**: True
- **Project Kind:** ClassLibrary
- **Dependencies**: 1
- **Dependants**: 0
- **Number of Files**: 1
- **Number of Files with Incidents**: 1
- **Lines of Code**: 252
- **Estimated LOC to modify**: 0+ (at least 0,0% of the project)

## Related Projects

**Depends on (1)** — projects this one references:

- [C:\Users\gbeaud\OneDrive - Microsoft\Code repository\GitHub\GitHub-Copilot-App-Modernization-MicroHack\repos\PhotoAlbum-.NET\PhotoAlbum\PhotoAlbum.csproj](../projects/PhotoAlbum.md)

## Dependency Graph

Legend:
📦 SDK-style project
⚙️ Classic project

```mermaid
flowchart TB
    subgraph current["PhotoAlbum.Tests.csproj"]
        MAIN["<b>📦&nbsp;PhotoAlbum.Tests.csproj</b><br/><small>net9.0</small>"]
        click MAIN "../projects/PhotoAlbum.Tests.md"
    end
    subgraph downstream["Dependencies (1)"]
        P1["<b>📦&nbsp;PhotoAlbum.csproj</b><br/><small>net9.0</small>"]
        click P1 "../projects/PhotoAlbum.md"
    end
    MAIN --> P1

```

## API Compatibility

| Category | Count | Impact |
| :--- | :---: | :--- |
| 🔴 Binary Incompatible | 0 | High - Require code changes |
| 🟡 Source Incompatible | 0 | Medium - Needs re-compilation and potential conflicting API error fixing |
| 🔵 Behavioral change | 0 | Low - Behavioral changes that may require testing at runtime |
| ✅ Compatible | 19 |  |
| ***Total APIs Analyzed*** | ***19*** |  |

## NuGet Package Issues

| Package | Current Version | Suggested Version | Severity | Issue |
| :--- | :---: | :---: | :---: | :--- |
| Microsoft.AspNetCore.Mvc.Testing | 9.0.9 | 10.0.12 | 🟡 Potential | NuGet package upgrade is recommended |
| Microsoft.EntityFrameworkCore.InMemory | 9.0.9 | 10.0.12 | 🟡 Potential | NuGet package upgrade is recommended |

Every project affected by these packages, and the versions the repository settles on: [aggregate NuGet packages](../nuget/aggregate-packages.md).

