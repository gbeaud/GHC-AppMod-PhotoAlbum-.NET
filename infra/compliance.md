# Infrastructure Compliance Report

**Task:** `002-infrastructure`  
**IaC:** Bicep  
**Deployment:** Azure CLI (`az deployment group`)

## Controls

- Deterministic lowercase resource naming.
- User-assigned identity attached to Container Apps.
- ACR admin disabled; identity has only `AcrPull`.
- Storage public access and local keys disabled; TLS 1.2 enforced; identity has only `Storage Blob Data Contributor`.
- SQL Azure AD-only authentication enabled; SQL DB Contributor is scoped to the database resource.
- SQL firewall allows Azure services only; no allow-all rule.
- `SecurityControl=Ignore` is applied because the subscription's MCAPS deny policy does not recognize the template's AD-only authentication property during create; remove this tag when the policy exemption/definition is corrected.
- Log Analytics is connected to Container Apps with 30-day retention.
- SQL password is interactive and never persisted by deployment scripts.
- `infra-config.md` is generated only after successful deployment and contains no secrets.

## Validation

`az bicep build --file infra/main.bicep` passes.

## Operational note

The initial Container App image is the Microsoft sample image. Replace `WEB_IMAGE_NAME` with the PhotoAlbum image before release. Public ingress and SQL network access suit this development task; production should use private networking.
