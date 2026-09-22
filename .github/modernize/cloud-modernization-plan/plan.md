# Modernization Plan: Cloud Modernization Plan

**Project**: PhotoAlbum

---

## Technical Framework

- **Language**: C# / .NET 10
- **Framework**: ASP.NET Core 10.0 (Razor Pages)
- **Build Tool**: dotnet CLI / MSBuild
- **Database**: SQL Server (LocalDB in development; SQL auth connection string)
- **Key Dependencies**: EF Core 10, SixLabors.ImageSharp, cookie auth

---

## Overview

> A prior assessment for this repository focused only on .NET framework upgrade
> recommendations, and the application has since already been upgraded to
> .NET 10 (the latest LTS). Per the current request, those upgrade
> recommendations are ignored, and this plan instead focuses exclusively on
> **cloud readiness** and **getting PhotoAlbum running in Azure**.
>
> The application currently stores uploaded photos on local disk
> (`wwwroot/uploads`) and connects to SQL Server using a local connection
> string. Neither approach is compatible with a stateless, horizontally
> scalable container deployment: local files are lost on restart/scale-out,
> and the database connection is not portable to a managed Azure SQL
> instance. The application does not use OracleDB, so no PostgreSQL
> migration is required.
>
> The new architecture will:
>
> - Persist uploaded photos in **Azure Blob Storage** instead of the local
>   container filesystem, so photos survive restarts and scale-out events.
> - Connect to **Azure SQL Database** using **Managed Identity** instead of
>   an embedded SQL login/password, removing a stored credential and
>   improving security posture.
> - Provision the required Azure infrastructure (Container Apps
>   environment, Azure SQL Database, Storage Account, Container Registry)
>   as Infrastructure-as-Code.
> - Scan and remediate known vulnerabilities (CVEs) in project
>   dependencies before deployment.
> - Containerize and deploy the application to **Azure Container Apps**.
>
> The migration follows a staged approach: establish a test baseline and
> provision infrastructure in parallel, migrate storage and database access
> to their Azure equivalents, verify the migration with integration tests,
> remediate security findings, and finally deploy the containerized app to
> Azure Container Apps.

---

## Migration Impact Summary

| App | Original | New Azure Service | Auth | Comments |
|-----|----------|--------------------|------|----------|
| PhotoAlbum | Local disk | Blob Storage | MI | Survives restarts |
| PhotoAlbum | SQL login/pw | Azure SQL DB | MI | No embedded secret |
| PhotoAlbum | `dotnet run` | Container Apps | MI | Scalable target |

---

## Open Questions & Questionnaire

- [ ] Environment Setup → Inferred: provision new infrastructure (existing
  `infra/` Bicep templates are reused and extended, not replaced), because
  the user explicitly asked to "set up Azure infrastructure ... and deploy
  the App on Azure".
- [ ] Integration Testing → Inferred: Yes, Real mode using the provisioned
  infrastructure, since infrastructure provisioning is included in this
  plan.
- [ ] Security & CVE Remediation → Inferred: Yes (default), no
  user-specified constraints provided.
- [ ] Deployment Target → Inferred: Azure Container Apps, matching the
  Container Apps resources already defined in `infra/main.bicep`.
- [ ] Containerization → Not asked; Azure Container Apps deployment already
  includes containerization.

_The `ask_user` tool was not available in this session, so these answers
use the documented defaults/inference rules from the questionnaire instead
of interactive confirmation._
