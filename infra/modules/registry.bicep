@description('Azure region for the registry.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'acr${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
  }
}

output loginServer string = registry.properties.loginServer
output name string = registry.name
output id string = registry.id
