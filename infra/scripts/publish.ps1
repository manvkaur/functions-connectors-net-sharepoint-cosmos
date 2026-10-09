$ErrorActionPreference = 'Stop'

$raw = azd env get-values --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the selected azd environment.'
}
$settings = ($raw -join "`n") | ConvertFrom-Json
foreach ($name in @('AZURE_SUBSCRIPTION_ID', 'AZURE_RESOURCE_GROUP', 'AZURE_FUNCTION_APP_NAME')) {
    if ([string]::IsNullOrWhiteSpace($settings.$name)) {
        throw "Missing azd output $name. Run azd provision first."
    }
}

$cidr = Read-Host 'Publishing workstation public IPv4 address (temporary /32 exception)'
$address = $null
if (-not [Net.IPAddress]::TryParse(($cidr -replace '/32$', ''), [ref]$address) -or
    $address.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    $cidr -notmatch '^\d{1,3}(\.\d{1,3}){3}(/32)?$') {
    throw 'Enter a valid public IPv4 address, optionally followed by /32.'
}
$cidr = "$address/32"

& "$PSScriptRoot\Publish-PrivateFunction.ps1" `
    -SubscriptionId $settings.AZURE_SUBSCRIPTION_ID `
    -ResourceGroup $settings.AZURE_RESOURCE_GROUP `
    -FunctionAppName $settings.AZURE_FUNCTION_APP_NAME `
    -PublishDirectory "$PSScriptRoot\..\..\out\publish" `
    -DeploymentClientCidr $cidr
