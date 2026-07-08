@description('Azure region for the alert resources (global for action groups).')
param location string

@description('Resource token used to build unique resource names.')
param resourceToken string

@description('Tags applied to every resource.')
param tags object

@description('Application Insights resource id the alert queries.')
param appInsightsId string

@description('Optional email address for the action group. Empty = no email receiver.')
param alertEmail string = ''

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${resourceToken}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'shop5xx'
    enabled: true
    emailReceivers: empty(alertEmail) ? [] : [
      {
        name: 'primary'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

resource alert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: 'alert-backend-5xx-${resourceToken}'
  location: location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: 'Backend 5xx errors detected'
    description: 'Fires when the backend records HTTP 5xx responses in Application Insights.'
    severity: 2
    enabled: true
    scopes: [ appInsightsId ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    autoMitigate: true
    criteria: {
      allOf: [
        {
          query: 'requests | where success == false and toint(resultCode) >= 500'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [ actionGroup.id ]
    }
  }
}

output actionGroupId string = actionGroup.id
output alertId string = alert.id
output alertName string = alert.name
