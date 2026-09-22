param name string
param location string
param environmentResourceId string
param image string
param registryLoginServer string
param identityResourceId string
param sqlServerFqdn string
param databaseName string
param storageBlobEndpoint string
param tags object

resource app 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentResourceId
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [
        {
          server: registryLoginServer
          identity: identityResourceId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'photoalbum'
          image: image
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'ConnectionStrings__DefaultConnection'
              value: 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${databaseName};Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
            }
            {
              name: 'AzureStorageBlob__Endpoint'
              value: storageBlobEndpoint
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
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
}

output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
