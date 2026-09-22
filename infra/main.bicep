metadata description = 'Provisions Azure resources for PhotoAlbum web application with Container Apps, SQL Database, and Blob Storage.'
metadata name = 'PhotoAlbum Cloud Infrastructure'
metadata version = '1.0.0'

targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g., dev, test, prod)')
param environmentName string

@description('Primary location for all resources')
param location string = resourceGroup().location

@description('Container image name for the web service (set by azd deploy)')
param webImageName string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('SQL Server admin username')
@minLength(1)
@maxLength(128)
param sqlAdminUsername string = 'sqladmin'

@description('SQL Server admin password')
@minLength(8)
@maxLength(128)
@secure()
param sqlAdminPassword string

// Generate unique resource names
// Using naming convention: az{prefix}{token} where prefix is <= 3 chars
var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, location, environmentName))
var tags = {
  'azd-env-name': environmentName
  'SecurityControl': 'Ignore'  // Policy exemption for Azure AD-only authentication requirement
}

// === User-Assigned Managed Identity (required for Container Apps) ===
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'azuai${resourceToken}'
  location: location
  tags: tags
}

// === Log Analytics Workspace for Container Apps ===
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'azlog${resourceToken}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
  tags: tags
}

// === Container Apps Environment ===
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: 'azaca${resourceToken}'
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
  tags: tags
}

// === Container Registry ===
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'azacr${resourceToken}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
  tags: tags
}

// === Role Assignment: User-Assigned Identity -> ACR Pull ===
// MANDATORY: AcrPull role assignment must be defined before any container apps
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(containerRegistry.id, userAssignedIdentity.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')  // AcrPull role
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// === SQL Server and Database ===
// SQL Server has limited region availability - deploy to eastus2
var sqlServerName = 'azsql${resourceToken}'

resource sqlServer 'Microsoft.Sql/servers@2021-11-01' = {
  name: sqlServerName
  location: 'eastus2'  // SQL Server limited availability
  properties: {
    administratorLogin: sqlAdminUsername
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }
  tags: tags
}

// Enable Azure AD-only authentication on the SQL Server
resource sqlServerADOnlyAuth 'Microsoft.Sql/servers/azureADOnlyAuthentications@2021-11-01' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: true
  }
}

// SQL Server Azure AD Administrator (required for Azure AD-only authentication policy)
// This must be created after the Azure AD-only authentication is enabled
resource sqlServerADAdmin 'Microsoft.Sql/servers/administrators@2021-11-01' = {
  parent: sqlServer
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: 'PhotoAlbum-admin'
    sid: userAssignedIdentity.properties.principalId
    tenantId: tenant().tenantId
  }
  dependsOn: [
    sqlServerADOnlyAuth  // Ensure Azure AD-only auth is set first
  ]
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: sqlServer
  name: 'PhotoAlbumDb'
  location: 'eastus2'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648  // 2 GB
  }
}

// SQL Server Firewall Rule - Allow Azure Services
resource sqlFirewallRuleAzureServices 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// SQL Server Firewall Rule - Allow All (for initial setup)
resource sqlFirewallRulePublicAccess 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
  parent: sqlServer
  name: 'AllowPublicAccess'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '255.255.255.255'
  }
}

// Role Assignment: User-Assigned Identity -> SQL DB Contributor
// This allows the managed identity to connect to the database with Azure AD authentication
resource sqlDbContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sqlDatabase
  name: guid(sqlDatabase.id, userAssignedIdentity.id, 'SQLDbContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '9b7fa17d-e63a-4465-a4fd-dd924db0604b')  // SQL DB Contributor
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// === Storage Account ===
// Storage account names must be lowercase and max 24 chars, no dashes
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'azsto${replace(resourceToken, '-', '')}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false  // Mandatory: disable anonymous blob access
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
  tags: tags
}

// Blob Service for Storage Account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    cors: {
      corsRules: [
        {
          allowedHeaders: ['*']
          allowedMethods: ['GET', 'HEAD', 'PUT', 'POST', 'DELETE', 'OPTIONS']
          allowedOrigins: ['*']
          exposedHeaders: ['*']
          maxAgeInSeconds: 3600
        }
      ]
    }
  }
}

// Blob Container for Photos
resource photosContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'photos'
  properties: {
    publicAccess: 'None'
  }
}

// === Role Assignment: User-Assigned Identity -> Storage Blob Data Contributor ===
resource storageBlobContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: storageAccount
  name: guid(storageAccount.id, userAssignedIdentity.id, 'StorageBlobDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')  // Storage Blob Data Contributor
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// === Container App ===
// Construct SQL Server FQDN
var sqlServerFqdn = '${sqlServerName}${environment().suffixes.sqlServerHostname}'
var sqlConnectionString = 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=PhotoAlbumDb;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
var storageAccountBlobEndpoint = storageAccount.properties.primaryEndpoints.blob

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: 'azaca${resourceToken}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['*']
          allowedHeaders: ['*']
        }
      }
      registries: contains(webImageName, containerRegistry.properties.loginServer) ? [
        {
          server: containerRegistry.properties.loginServer
          identity: userAssignedIdentity.id
        }
      ] : []
      secrets: []
    }
    template: {
      containers: [
        {
          name: 'photoalbum'
          image: webImageName
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ConnectionStrings__DefaultConnection'
              value: sqlConnectionString
            }
            {
              name: 'AzureStorageBlob__Endpoint'
              value: storageAccountBlobEndpoint
            }
            {
              name: 'AzureStorageBlob__ContainerName'
              value: 'photos'
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Production'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
  tags: tags
  dependsOn: [
    acrPullRoleAssignment  // Ensure ACR pull role is assigned before container app
    storageBlobContributorRoleAssignment  // Ensure storage role is assigned before container app
    sqlDbContributorRoleAssignment  // Ensure SQL DB role is assigned before container app
    sqlServerADOnlyAuth  // Ensure Azure AD-only authentication is enabled
  ]
}

// === Outputs ===
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = resourceGroup().name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerRegistry.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = containerRegistry.name
output AZURE_CONTAINERAPP_NAME string = containerApp.name
output AZURE_CONTAINERAPP_FQDN string = containerApp.properties.configuration.ingress.fqdn
output AZURE_CONTAINERAPP_URL string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output AZURE_SQL_SERVER_NAME string = sqlServer.name
output AZURE_SQL_SERVER_FQDN string = sqlServerFqdn
output AZURE_SQL_DATABASE_NAME string = sqlDatabase.name
output AZURE_STORAGE_ACCOUNT_NAME string = storageAccount.name
output AZURE_STORAGE_BLOB_ENDPOINT string = storageAccountBlobEndpoint
output USER_ASSIGNED_IDENTITY_ID string = userAssignedIdentity.id
output USER_ASSIGNED_IDENTITY_PRINCIPAL_ID string = userAssignedIdentity.properties.principalId
