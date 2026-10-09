// Flex identity/storage composition inspired by Azure-Samples/functions-connectors-net/sharepointApp/infra/main.bicep (MIT).
targetScope = 'resourceGroup'

@minLength(3)
@maxLength(20)
param environmentName string = 'sp-poll-cosmos'
param tags object = {}
param location string = resourceGroup().location
@description('Application Insights location; it need not match the app/data region.')
param monitoringLocation string = 'westus2'
@description('Keep empty for private-only access. Supply the deployer IPv4 CIDR temporarily for publishing, then disable public access.')
param deploymentClientCidr string = ''
@minValue(1)
@maxValue(10)
param alwaysReadyInstances int = 1
param triggerName string = 'sharepoint-file-intake'
@description('SharePoint dataset, table, and optional folderPath parameter objects; keep real values outside source control.')
param sourceParameters array

var token = uniqueString(resourceGroup().id, environmentName)
var functionName = 'func-${environmentName}-${token}'
var databaseName = 'demo'
var containerName = 'documentIntake'
var blobOwnerRole = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var queueRole = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var tableRole = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var monitoringRole = '3913510d-42f4-4e42-8a64-420c390055eb'

module identity 'br/public:avm/res/managed-identity/user-assigned-identity:0.5.0' = {
  name: 'function-identity'
  params: {
    name: 'id-${environmentName}-${token}'
    location: location
  }
}

module logs 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'logs'
  params: {
    name: 'log-${environmentName}-${token}'
    location: location
    dataRetention: 30
  }
}

module insights 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'insights'
  params: {
    name: 'appi-${environmentName}-${token}'
    location: monitoringLocation
    workspaceResourceId: logs.outputs.resourceId
    disableLocalAuth: true
    roleAssignments: [
      {
        roleDefinitionIdOrName: monitoringRole
        principalId: identity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module storage 'br/public:avm/res/storage/storage-account:0.32.0' = {
  name: 'storage'
  params: {
    name: 'st${token}'
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    minimumTlsVersion: 'TLS1_2'
    blobServices: {
      containers: [
        { name: 'deploymentpackage' }
      ]
    }
    roleAssignments: [
      {
        roleDefinitionIdOrName: blobOwnerRole
        principalId: identity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: queueRole
        principalId: identity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
      {
        roleDefinitionIdOrName: tableRole
        principalId: identity.outputs.principalId
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

module plan 'br/public:avm/res/web/serverfarm:0.7.0' = {
  name: 'flex-plan'
  params: {
    name: 'plan-${environmentName}-${token}'
    location: location
    skuName: 'FC1'
    reserved: true
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${environmentName}-${token}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.64.0.0/16']
    }
    subnets: [
      {
        name: 'functions'
        properties: {
          addressPrefix: '10.64.0.0/24'
          delegations: [
            {
              name: 'flex'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.64.1.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: 'cosmos-${environmentName}-${token}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    consistencyPolicy: { defaultConsistencyLevel: 'Session' }
    locations: [
      { locationName: location, failoverPriority: 0 }
    ]
    capabilities: [
      { name: 'EnableServerless' }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmos
  name: databaseName
  properties: {
    resource: { id: databaseName }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: ['/source']
        kind: 'Hash'
      }
    }
  }
}

resource cosmosRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  name: guid(cosmos.id, environmentName, containerName)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: identity.outputs.principalId
    scope: '${cosmos.id}/dbs/${databaseName}/colls/${containerName}'
  }
  dependsOn: [container]
}

resource cosmosDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
}

resource cosmosDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: cosmosDns
  name: 'demo-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

resource cosmosEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-cosmos-${token}'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/private-endpoints' }
    privateLinkServiceConnections: [
      {
        name: 'cosmos'
        properties: {
          privateLinkServiceId: cosmos.id
          groupIds: ['Sql']
        }
      }
    ]
  }
}

resource cosmosDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: cosmosEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'cosmos', properties: { privateDnsZoneId: cosmosDns.id } }
    ]
  }
}

module cn './connectorNamespace.bicep' = {
  name: 'connector-namespace'
  params: {
    name: 'cn-${environmentName}-${token}'
    location: location
    functionPrincipalId: identity.outputs.principalId
    triggerName: triggerName
    sourceParameters: sourceParameters
  }
}

module app 'br/public:avm/res/web/site:0.22.0' = {
  name: 'function'
  params: {
    name: functionName
    location: location
    tags: union(tags, { 'azd-service-name': 'function-app' })
    kind: 'functionapp,linux'
    serverFarmResourceId: plan.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
      userAssignedResourceIds: [identity.outputs.resourceId]
    }
    virtualNetworkSubnetResourceId: '${vnet.id}/subnets/functions'
    publicNetworkAccess: empty(deploymentClientCidr) ? 'Disabled' : 'Enabled'
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storage.outputs.primaryBlobEndpoint}deploymentpackage'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: identity.outputs.resourceId
          }
        }
      }
      scaleAndConcurrency: {
        instanceMemoryMB: 2048
        maximumInstanceCount: 40
        alwaysReady: [
          { name: 'function:OnSharePointFile', instanceCount: alwaysReadyInstances }
        ]
      }
      runtime: { name: 'dotnet-isolated', version: '10.0' }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      ipSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictionsUseMain: true
      ipSecurityRestrictions: empty(deploymentClientCidr) ? [] : [
        {
          name: 'temporary-deployer'
          ipAddress: deploymentClientCidr
          action: 'Allow'
          priority: 100
        }
      ]
    }
    configs: [
      {
        name: 'appsettings'
        properties: {
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__clientId: identity.outputs.clientId
          AzureWebJobsStorage__accountName: storage.outputs.name
          APPLICATIONINSIGHTS_CONNECTION_STRING: insights.outputs.connectionString
          APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${identity.outputs.clientId};Authorization=AAD'
          ConnectorNamespace__credential: 'managedidentity'
          ConnectorNamespace__clientId: identity.outputs.clientId
          ConnectorNamespace__pollingEndpoint: cn.outputs.pollingEndpoint
          SharePointTriggerConfigName: triggerName
          'AzureWebJobs.OnSharePointFile.Disabled': 'false'
          CosmosConnection__accountEndpoint: cosmos.properties.documentEndpoint
          CosmosConnection__credential: 'managedidentity'
          CosmosConnection__clientId: identity.outputs.clientId
          CosmosDatabaseName: databaseName
          CosmosContainerName: containerName
        }
      }
    ]
  }
  dependsOn: [cosmosDnsLink, cosmosDnsGroup, cosmosRole]
}

resource appDns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
}

resource appDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: appDns
  name: 'demo-vnet'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}

resource appEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-function-${token}'
  location: location
  properties: {
    subnet: { id: '${vnet.id}/subnets/private-endpoints' }
    privateLinkServiceConnections: [
      {
        name: 'function'
        properties: {
          privateLinkServiceId: app.outputs.resourceId
          groupIds: ['sites']
        }
      }
    ]
  }
}

resource appDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: appEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'function', properties: { privateDnsZoneId: appDns.id } }
    ]
  }
}

output functionAppName string = app.outputs.name
output functionPrincipalId string = identity.outputs.principalId
output functionClientId string = identity.outputs.clientId
output connectorNamespaceName string = cn.outputs.namespaceName
output connectorConnectionName string = cn.outputs.connectionName
output cosmosAccountName string = cosmos.name
output cosmosEndpoint string = cosmos.properties.documentEndpoint
output vnetName string = vnet.name
output workspaceId string = logs.outputs.resourceId
output triggerResourceId string = cn.outputs.triggerResourceId
output pollingEndpoints object = cn.outputs.pollingEndpoints
output pollingEndpoint string = cn.outputs.pollingEndpoint
output cosmosDatabaseName string = databaseName
output cosmosContainerName string = containerName
output sharepointTriggerName string = triggerName
