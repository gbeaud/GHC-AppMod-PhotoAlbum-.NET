param name string
param location string
param administratorLogin string
@secure()
param administratorLoginPassword string
param identityPrincipalId string
param tenantId string
param tags object

resource server 'Microsoft.Sql/servers@2021-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
}

resource adOnly 'Microsoft.Sql/servers/azureADOnlyAuthentications@2021-11-01' = {
  parent: server
  name: 'Default'
  dependsOn: [
    adAdministrator
  ]
  properties: {
    azureADOnlyAuthentication: true
  }
}

resource adAdministrator 'Microsoft.Sql/servers/administrators@2021-11-01' = {
  parent: server
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: 'PhotoAlbum managed identity'
    sid: identityPrincipalId
    tenantId: tenantId
  }
}

resource database 'Microsoft.Sql/servers/databases@2021-11-01' = {
  parent: server
  name: 'PhotoAlbumDb'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 2147483648
  }
}

resource azureServicesRule 'Microsoft.Sql/servers/firewallRules@2021-11-01' = {
  parent: server
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverName string = server.name
output serverFqdn string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
output databaseResourceId string = database.id
