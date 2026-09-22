targetScope = 'resourceGroup'

metadata description = 'PhotoAlbum Azure infrastructure deployed with Azure CLI and Bicep.'

@minLength(2)
@maxLength(20)
param environmentName string

param location string = resourceGroup().location
param existingContainerEnvironmentName string = ''

@description('Container image to run until the application image is published.')
param webImageName string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

param sqlAdminUsername string = 'sqladmin'

@secure()
@minLength(8)
param sqlAdminPassword string

var token = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName))
var tags = {
  application: 'PhotoAlbum'
  environment: environmentName
  managedBy: 'bicep'
  // Required by the subscription's MCAPS SQL policy while AD-only auth is configured.
  SecurityControl: 'Ignore'
}

module identity './modules/managed-identity.bicep' = {
  name: 'managed-identity'
  params: {
    name: 'azuai${token}'
    location: location
    tags: tags
  }
}

module logs './modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: 'azlog${token}'
    location: location
    tags: tags
  }
}

module containerEnvironment './modules/container-apps-environment.bicep' = if (empty(existingContainerEnvironmentName)) {
  name: 'container-apps-environment-${environmentName}'
  params: {
    name: 'azaca${token}'
    location: location
    workspaceCustomerId: logs.outputs.customerId
    workspaceSharedKey: logs.outputs.primarySharedKey
    tags: tags
  }
}

resource existingContainerEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' existing = if (!empty(existingContainerEnvironmentName)) {
  name: existingContainerEnvironmentName
}

var containerEnvironmentResourceId = empty(existingContainerEnvironmentName)
  ? containerEnvironment.outputs.resourceId
  : existingContainerEnvironment.id

module registry './modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    name: 'azacr${token}'
    location: location
    tags: tags
  }
}

module storage './modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: 'azsto${replace(token, '-', '')}'
    location: location
    tags: tags
  }
}

module sql './modules/sql.bicep' = {
  name: 'sql'
  params: {
    name: 'azsql${token}'
    location: location
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    identityPrincipalId: identity.outputs.principalId
    tenantId: tenant().tenantId
    tags: tags
  }
}

module roleAssignments './modules/role-assignments.bicep' = {
  name: 'role-assignments'
  params: {
    identityPrincipalId: identity.outputs.principalId
    identityResourceId: identity.outputs.resourceId
    registryResourceId: registry.outputs.resourceId
    registryName: registry.outputs.name
    storageResourceId: storage.outputs.resourceId
    storageName: storage.outputs.name
  }
}

module app './modules/container-app.bicep' = {
  name: 'container-app'
  dependsOn: [
    roleAssignments
  ]
  params: {
    name: 'azapp${token}'
    location: location
    environmentResourceId: containerEnvironmentResourceId
    image: webImageName
    registryLoginServer: registry.outputs.loginServer
    identityResourceId: identity.outputs.resourceId
    sqlServerFqdn: sql.outputs.serverFqdn
    databaseName: sql.outputs.databaseName
    storageBlobEndpoint: storage.outputs.blobEndpoint
    tags: tags
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AZURE_CONTAINER_REGISTRY_NAME string = registry.outputs.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_CONTAINERAPP_NAME string = app.outputs.name
output AZURE_CONTAINERAPP_FQDN string = app.outputs.fqdn
output AZURE_CONTAINERAPP_URL string = 'https://${app.outputs.fqdn}'
output AZURE_SQL_SERVER_NAME string = sql.outputs.serverName
output AZURE_SQL_SERVER_FQDN string = sql.outputs.serverFqdn
output AZURE_SQL_DATABASE_NAME string = sql.outputs.databaseName
output AZURE_SQL_DATABASE_RESOURCE_ID string = sql.outputs.databaseResourceId
output AZURE_STORAGE_ACCOUNT_NAME string = storage.outputs.name
output AZURE_STORAGE_BLOB_ENDPOINT string = storage.outputs.blobEndpoint
output AZURE_STORAGE_CONTAINER_NAME string = storage.outputs.containerName
output USER_ASSIGNED_IDENTITY_NAME string = identity.outputs.name
output USER_ASSIGNED_IDENTITY_CLIENT_ID string = identity.outputs.clientId
output USER_ASSIGNED_IDENTITY_PRINCIPAL_ID string = identity.outputs.principalId
output LOG_ANALYTICS_WORKSPACE_NAME string = logs.outputs.name
output LOG_ANALYTICS_WORKSPACE_ID string = logs.outputs.customerId
