@description('Azure region (must be an SRE-Agent-supported region, e.g. swedencentral).')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

@description('Application Insights app id (GUID) for the agent log configuration.')
param appInsightsAppId string

@description('Application Insights connection string for the agent log configuration.')
@secure()
param appInsightsConnectionString string

@description('Resource id of the resource group content the agent should watch.')
param managedResourceId string

@description('Agent action mode for Azure mitigations.')
@allowed([ 'ReadOnly', 'Review', 'Autonomous' ])
param agentMode string = 'Review'

@description('Model provider (ARM value). MicrosoftFoundry maps to Azure OpenAI.')
param modelProvider string = 'MicrosoftFoundry'

@description('Model name, e.g. gpt-5.')
param modelName string = 'gpt-5'

var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

resource agent 'Microsoft.App/agents@2026-01-01' = {
  name: 'sre-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    actionConfiguration: {
      mode: agentMode
      accessLevel: 'Low'
    }
    defaultModel: {
      provider: modelProvider
      name: modelName
    }
    knowledgeGraphConfiguration: {
      managedResources: [ managedResourceId ]
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsightsAppId
        connectionString: appInsightsConnectionString
      }
    }
    upgradeChannel: 'Preview'
  }
}

resource readerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedResourceId, agent.id, readerRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: readerRoleId
    principalId: agent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedResourceId, agent.id, monitoringReaderRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: monitoringReaderRoleId
    principalId: agent.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output name string = agent.name
output principalId string = agent.identity.principalId
