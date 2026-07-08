@description('Azure region for the Static Web App.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource (must include azd-service-name for the frontend).')
param tags object

resource staticSite 'Microsoft.Web/staticSites@2023-12-01' = {
  name: 'stapp-${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Free', tier: 'Free' }
  properties: {
    // App is deployed by azd (SWA CLI), not by a linked repo build.
    provider: 'Custom'
  }
}

output name string = staticSite.name
output defaultHostname string = staticSite.properties.defaultHostname
output uri string = 'https://${staticSite.properties.defaultHostname}'
