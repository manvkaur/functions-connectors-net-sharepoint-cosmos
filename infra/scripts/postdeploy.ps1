param([switch] $ForceLocalSettings)

$ErrorActionPreference = 'Stop'

$raw = azd env get-values --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the selected azd environment.'
}
$settings = ($raw -join "`n") | ConvertFrom-Json
foreach ($name in @(
    'AZURE_SUBSCRIPTION_ID', 'AZURE_RESOURCE_GROUP',
    'CONNECTOR_NAMESPACE_NAME', 'CONNECTOR_CONNECTION_NAME', 'CONNECTOR_POLLING_ENDPOINT',
    'SHAREPOINT_TRIGGER_CONFIG_NAME', 'COSMOS_ENDPOINT', 'COSMOS_DATABASE_NAME', 'COSMOS_CONTAINER_NAME')) {
    if ([string]::IsNullOrWhiteSpace($settings.$name)) {
        throw "Missing azd output $name. Run azd provision first."
    }
}

$path = "$PSScriptRoot\..\..\local.settings.json"
if ((Test-Path -LiteralPath $path) -and -not $ForceLocalSettings) {
    Write-Host 'Existing local.settings.json preserved. Use postdeploy.ps1 -ForceLocalSettings to regenerate it.'
}
else {
    $localSettings = @{
        IsEncrypted = $false
        Values = @{
            AzureWebJobsStorage = 'UseDevelopmentStorage=true'
            FUNCTIONS_WORKER_RUNTIME = 'dotnet-isolated'
            ConnectorNamespace__pollingEndpoint = $settings.CONNECTOR_POLLING_ENDPOINT
            SharePointTriggerConfigName = $settings.SHAREPOINT_TRIGGER_CONFIG_NAME
            CosmosConnection__accountEndpoint = $settings.COSMOS_ENDPOINT
            CosmosDatabaseName = $settings.COSMOS_DATABASE_NAME
            CosmosContainerName = $settings.COSMOS_CONTAINER_NAME
        }
    }
    [IO.File]::WriteAllText($path, ($localSettings | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false))
    Write-Host 'Created ignored local.settings.json with developer-identity settings.'
}

& "$PSScriptRoot\Connect-SharePoint.ps1" `
    -SubscriptionId $settings.AZURE_SUBSCRIPTION_ID `
    -ResourceGroup $settings.AZURE_RESOURCE_GROUP `
    -NamespaceName $settings.CONNECTOR_NAMESPACE_NAME `
    -ConnectionName $settings.CONNECTOR_CONNECTION_NAME
