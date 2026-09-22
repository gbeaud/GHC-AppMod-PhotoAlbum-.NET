# PhotoAlbum\PhotoAlbum.csproj

[← Back to the assessment index](../../assessment.md)

## Project Info

- **Current Target Framework:** net9.0
- **Proposed Target Framework:** net10.0
- **SDK-style**: True
- **Project Kind:** AspNetCore
- **Dependencies**: 0
- **Dependants**: 1
- **Number of Files**: 33
- **Number of Files with Incidents**: 1
- **Lines of Code**: 1568
- **Estimated LOC to modify**: 0+ (at least 0,0% of the project)

## Related Projects

**Depended on by (1)** — projects that reference this one:

- [C:\Users\gbeaud\OneDrive - Microsoft\Code repository\GitHub\GitHub-Copilot-App-Modernization-MicroHack\repos\PhotoAlbum-.NET\PhotoAlbum.Tests\PhotoAlbum.Tests.csproj](../projects/PhotoAlbum.Tests.md)

## Dependency Graph

Legend:
📦 SDK-style project
⚙️ Classic project

```mermaid
flowchart TB
    subgraph upstream["Dependants (1)"]
        P2["<b>📦&nbsp;PhotoAlbum.Tests.csproj</b><br/><small>net9.0</small>"]
        click P2 "../projects/PhotoAlbum.Tests.md"
    end
    subgraph current["PhotoAlbum.csproj"]
        MAIN["<b>📦&nbsp;PhotoAlbum.csproj</b><br/><small>net9.0</small>"]
        click MAIN "../projects/PhotoAlbum.md"
    end
    P2 --> MAIN

```

## API Compatibility

| Category | Count | Impact |
| :--- | :---: | :--- |
| 🔴 Binary Incompatible | 0 | High - Require code changes |
| 🟡 Source Incompatible | 0 | Medium - Needs re-compilation and potential conflicting API error fixing |
| 🔵 Behavioral change | 0 | Low - Behavioral changes that may require testing at runtime |
| ✅ Compatible | 0 |  |
| ***Total APIs Analyzed*** | ***0*** |  |

## NuGet Package Issues

| Package | Current Version | Suggested Version | Severity | Issue |
| :--- | :---: | :---: | :---: | :--- |
| Microsoft.EntityFrameworkCore.Design | 9.0.9 | 10.0.12 | 🟡 Potential | NuGet package upgrade is recommended |
| Microsoft.EntityFrameworkCore.SqlServer | 9.0.9 | 10.0.12 | 🟡 Potential | NuGet package upgrade is recommended |

Every project affected by these packages, and the versions the repository settles on: [aggregate NuGet packages](../nuget/aggregate-packages.md).

