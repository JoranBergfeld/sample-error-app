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

@description('Model name (must be a supported agent model in the target region, e.g. gpt-5.4).')
param modelName string = 'gpt-5.4'

var readerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
var monitoringReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')

// The agent's sub-configurations (knowledgeGraph / action) reference an identity by
// resource id, which a system-assigned identity cannot satisfy at create time
// (its principal is unknown until after creation). A user-assigned identity is used
// so the same identity can be referenced by the agent's properties and RBAC.
resource agentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-sre-${resourceToken}'
  location: location
  tags: tags
}

resource agent 'Microsoft.App/agents@2026-01-01' = {
  name: 'sre-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${agentIdentity.id}': {}
    }
  }
  properties: {
    actionConfiguration: {
      mode: agentMode
      accessLevel: 'Low'
      identity: agentIdentity.id
    }
    defaultModel: {
      provider: modelProvider
      name: modelName
    }
    knowledgeGraphConfiguration: {
      managedResources: [ managedResourceId ]
      identity: agentIdentity.id
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
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource monitoringReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedResourceId, agent.id, monitoringReaderRoleId)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: monitoringReaderRoleId
    principalId: agentIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output name string = agent.name
output principalId string = agentIdentity.properties.principalId
