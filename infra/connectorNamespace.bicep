// Adapted from Azure-Samples/functions-connectors-net/sharepointApp/infra/connectorNamespace.bicep (MIT).
param name string
param location string
param functionPrincipalId string
param connectionName string = 'sharepoint'
param triggerName string = 'sharepoint-file-intake'
param sourceParameters array

resource cn 'Microsoft.Web/connectorGateways@2026-05-01-preview' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}

resource connection 'Microsoft.Web/connectorGateways/connections@2026-05-01-preview' = {
  parent: cn
  name: connectionName
  properties: {
    connectorName: 'sharepointonline'
  }
}

resource functionPolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: connection
  name: 'function-runtime'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: functionPrincipalId
        tenantId: tenant().tenantId
      }
    }
  }
}

resource namespacePolicy 'Microsoft.Web/connectorGateways/connections/accessPolicies@2026-05-01-preview' = {
  parent: connection
  name: 'namespace-runtime'
  properties: {
    principal: {
      type: 'ActiveDirectory'
      identity: {
        objectId: cn.identity.principalId
        tenantId: tenant().tenantId
      }
    }
  }
}

module poll './poll-trigger.bicep' = {
  name: 'sharepoint-poll-trigger'
  params: {
    namespaceName: cn.name
    connectionName: connection.name
    triggerName: triggerName
    sourceParameters: sourceParameters
  }
  dependsOn: [namespacePolicy, functionPolicy]
}

var receiveUri = string(poll.outputs.pollingEndpoints.receiveUri)
var operationStart = indexOf(toLower(receiveUri), '/triggerconfigs/')
var queryStart = indexOf(receiveUri, '?')

output namespaceName string = cn.name
output connectionName string = connection.name
output triggerResourceId string = poll.outputs.triggerResourceId
output pollingEndpoints object = poll.outputs.pollingEndpoints
output pollingEndpoint string = '${substring(receiveUri, 0, operationStart)}${queryStart < 0 ? '' : substring(receiveUri, queryStart)}'
