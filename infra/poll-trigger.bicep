param namespaceName string
param connectionName string = 'sharepoint'
param triggerName string = 'sharepoint-file-intake'
@description('SharePoint dataset, table, and optional folderPath parameter objects. Keep real values out of source control.')
param sourceParameters array

resource cn 'Microsoft.Web/connectorGateways@2026-05-01-preview' existing = {
  name: namespaceName
}

resource trigger 'Microsoft.Web/connectorGateways/triggerConfigs@2026-05-01-preview' = {
  parent: cn
  name: triggerName
  properties: {
    connectionDetails: {
      connectionName: connectionName
      connectorName: 'sharepointonline'
    }
    deliveryMode: 'Poll'
    operationName: 'GetOnNewFileItems'
    parameters: sourceParameters
    state: 'Enabled'
    type: 'NotSpecified'
    description: 'SharePoint file metadata to private Cosmos DB through Function Poll delivery.'
  }
}

output triggerResourceId string = trigger.id
output pollingEndpoints object = trigger.properties.pollingEndpoints
