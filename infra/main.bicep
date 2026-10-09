targetScope = 'subscription'

param location string = 'westcentralus'
param monitoringLocation string = 'westus2'
param environmentName string = 'sp-poll-cosmos'
param resourceGroupName string = 'rg-${environmentName}-demo'
@minLength(1)
param sharepointSiteUrl string
@minLength(1)
param sharepointLibraryName string
param sharepointFolderPath string = ''

var tags = { 'azd-env-name': environmentName }
var sourceParameters = concat([
  { name: 'dataset', value: sharepointSiteUrl }
  { name: 'table', value: sharepointLibraryName }
], empty(sharepointFolderPath) ? [] : [
  { name: 'folderPath', value: sharepointFolderPath }
])

resource group 'Microsoft.Resources/resourceGroups@2025-04-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

module demo './resources.bicep' = {
  name: 'sharepoint-poll-cosmos'
  scope: group
  params: {
    location: location
    monitoringLocation: monitoringLocation
    environmentName: environmentName
    tags: tags
    sourceParameters: sourceParameters
  }
}

output AZURE_RESOURCE_GROUP string = group.name
output AZURE_FUNCTION_APP_NAME string = demo.outputs.functionAppName
output CONNECTOR_NAMESPACE_NAME string = demo.outputs.connectorNamespaceName
output CONNECTOR_CONNECTION_NAME string = demo.outputs.connectorConnectionName
output CONNECTOR_POLLING_ENDPOINT string = demo.outputs.pollingEndpoint
output SHAREPOINT_TRIGGER_CONFIG_NAME string = demo.outputs.sharepointTriggerName
output COSMOS_ENDPOINT string = demo.outputs.cosmosEndpoint
output COSMOS_DATABASE_NAME string = demo.outputs.cosmosDatabaseName
output COSMOS_CONTAINER_NAME string = demo.outputs.cosmosContainerName
