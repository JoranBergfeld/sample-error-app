targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment; used to name the resource group and tag resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources (SRE-Agent-supported, e.g. swedencentral).')
param location string

@description('Location for the Static Web App. SWA is NOT available in every region (e.g. not swedencentral); use a supported region such as westeurope.')
param staticWebAppLocation string = 'westeurope'

@description('Optional email for the 5xx action group.')
param alertEmail string = ''

@description('SRE Agent action mode.')
@allowed([ 'ReadOnly', 'Review', 'Autonomous' ])
param sreAgentMode string = 'Review'

@description('SRE Agent model provider (ARM value; MicrosoftFoundry = Azure OpenAI).')
param sreAgentModelProvider string = 'MicrosoftFoundry'

@description('SRE Agent model name.')
param sreAgentModelName string = 'gpt-5'

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
  }
}

module staticwebapp 'modules/staticwebapp.bicep' = {
  name: 'staticwebapp'
  scope: rg
  params: {
    location: staticWebAppLocation
    resourceToken: resourceToken
    tags: union(tags, { 'azd-service-name': 'frontend' })
  }
}

module containerapp 'modules/containerapp.bicep' = {
  name: 'containerapp'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    logAnalyticsCustomerId: monitoring.outputs.logAnalyticsCustomerId
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsId
    registryLoginServer: registry.outputs.loginServer
    registryName: registry.outputs.name
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    frontendOrigin: staticwebapp.outputs.uri
  }
}

module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    appInsightsId: monitoring.outputs.appInsightsId
    alertEmail: alertEmail
  }
}

module sreAgent 'modules/sre-agent.bicep' = {
  name: 'sre-agent'
  scope: rg
  params: {
    location: location
    resourceToken: resourceToken
    tags: tags
    appInsightsAppId: monitoring.outputs.appInsightsAppId
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    managedResourceId: rg.id
    agentMode: sreAgentMode
    modelProvider: sreAgentModelProvider
    modelName: sreAgentModelName
  }
}

// azd-consumed outputs
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output SERVICE_BACKEND_URI string = containerapp.outputs.uri
output SERVICE_FRONTEND_URI string = staticwebapp.outputs.uri
output VITE_API_BASE_URL string = containerapp.outputs.uri
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.appInsightsConnectionString
output SRE_AGENT_NAME string = sreAgent.outputs.name
