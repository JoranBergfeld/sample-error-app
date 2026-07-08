@description('Azure region.')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags for the environment. The container app also needs an azd-service-name tag.')
param tags object

@description('azd service name that maps this container app to the "backend" service.')
param serviceName string = 'backend'

@description('Log Analytics workspace customer id (GUID) for the environment.')
param logAnalyticsCustomerId string

@description('Log Analytics workspace resource id (for the shared key lookup).')
param logAnalyticsWorkspaceResourceId string

@description('Container registry login server, e.g. myacr.azurecr.io.')
param registryLoginServer string

@description('Container registry resource name (for role assignment scope).')
param registryName string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Allowed CORS origin for the frontend (https://<swa-hostname>).')
param frontendOrigin string

@description('Container image to run. Defaults to a placeholder; azd replaces it on deploy.')
param backendImage string = 'mcr.microsoft.com/k8se/quickstart:latest'

var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceResourceId, '/'))
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-backend-${resourceToken}'
  location: location
  tags: tags
}

resource acrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, identity.id, acrPullRoleId)
  scope: registry
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource env 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-backend-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': serviceName })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: env.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: registryLoginServer
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'backend'
          image: backendImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'PORT', value: '8080' }
            { name: 'FRONTEND_ORIGIN', value: frontendOrigin }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 2
      }
    }
  }
  dependsOn: [ acrPull ]
}

output name string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
output uri string = 'https://${app.properties.configuration.ingress.fqdn}'
output identityPrincipalId string = identity.properties.principalId
