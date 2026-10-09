param(
    [Parameter(Mandatory)][string] $ResourceGroup,
    [Parameter(Mandatory)][string] $NamespaceName,
    [string] $ConnectionName = 'sharepoint',
    [string] $SubscriptionId
)

$ErrorActionPreference = 'Stop'
$contextArguments = @()
if ($SubscriptionId) {
    $contextArguments = @('--subscription', $SubscriptionId)
}

function Get-ConnectionStatus {
    $status = az connector-namespace connection show -g $ResourceGroup `
        --namespace $NamespaceName --connection-name $ConnectionName `
        --query properties.overallStatus -o tsv @contextArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to read SharePoint connection status.'
    }
    return ($status -join "`n").Trim()
}

if ((Get-ConnectionStatus) -eq 'Connected') {
    Write-Output 'SharePoint connection is already Connected.'
    return
}

$parametersFile = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($parametersFile,
        '[{"parameterName":"token","redirectUrl":"https://portal.azure.com"}]',
        [Text.UTF8Encoding]::new($false))
    $raw = az connector-namespace connection list-consent-links -g $ResourceGroup `
        --namespace $NamespaceName --connection-name $ConnectionName `
        --parameters "@$parametersFile" -o json @contextArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to obtain SharePoint OAuth consent link.'
    }
    $result = ($raw -join "`n") | ConvertFrom-Json
    $link = $result.value[0].link
    if ([string]::IsNullOrWhiteSpace($link)) {
        throw 'Connection service did not return a consent link.'
    }
    Start-Process $link
    Write-Output 'Complete SharePoint consent in the browser; waiting for Connected status.'
    $deadline = [DateTime]::UtcNow.AddMinutes(5)
    while ((Get-ConnectionStatus) -ne 'Connected') {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw 'Timed out waiting for SharePoint consent. Run Connect-SharePoint.ps1 again.'
        }
        Start-Sleep -Seconds 3
    }
    Write-Output 'SharePoint connection is Connected.'
}
finally {
    Remove-Item -LiteralPath $parametersFile
}
