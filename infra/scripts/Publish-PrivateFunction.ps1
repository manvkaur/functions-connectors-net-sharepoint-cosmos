param(
    [Parameter(Mandatory)][string] $ResourceGroup,
    [Parameter(Mandatory)][string] $FunctionAppName,
    [Parameter(Mandatory)][string] $PublishDirectory,
    [Parameter(Mandatory)][string] $DeploymentClientCidr,
    [string] $SubscriptionId
)

$ErrorActionPreference = 'Stop'

function Invoke-Az {
    param([string[]] $Arguments)
    if ($SubscriptionId) {
        $Arguments += @('--subscription', $SubscriptionId)
    }
    $output = az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: $($Arguments[0]) $($Arguments[1])"
    }
    return ($output -join "`n")
}

$publish = (Resolve-Path -LiteralPath $PublishDirectory).Path
if (-not (Test-Path -LiteralPath "$publish\functions.metadata") -or
    -not (Test-Path -LiteralPath "$publish\.azurefunctions")) {
    throw 'PublishDirectory must contain a published isolated Function app including its host extensions.'
}
if ($DeploymentClientCidr -notmatch '^\d{1,3}(\.\d{1,3}){3}/32$') {
    throw 'Supply only the publishing workstation IPv4 address with /32.'
}

$zip = Join-Path ([IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).zip"
try {
    [IO.Compression.ZipFile]::CreateFromDirectory($publish, $zip)
    $null = Invoke-Az -Arguments @('functionapp', 'config', 'access-restriction', 'add',
        '-g', $ResourceGroup, '-n', $FunctionAppName, '--rule-name', 'temporary-deployer',
        '--ip-address', $DeploymentClientCidr, '--priority', '100', '--action', 'Allow', '-o', 'none')
    $null = Invoke-Az -Arguments @('functionapp', 'config', 'access-restriction', 'set',
        '-g', $ResourceGroup, '-n', $FunctionAppName, '--default-action', 'Deny',
        '--use-same-restrictions-for-scm-site', 'true', '-o', 'none')
    $null = Invoke-Az -Arguments @('functionapp', 'update', '-g', $ResourceGroup,
        '-n', $FunctionAppName, '--set', 'publicNetworkAccess=Enabled', '-o', 'none')
    $null = Invoke-Az -Arguments @('functionapp', 'deployment', 'source', 'config-zip',
        '-g', $ResourceGroup, '-n', $FunctionAppName, '--src', $zip,
        '--build-remote', 'false', '--timeout', '600', '-o', 'none')
}
finally {
    try {
        $null = Invoke-Az -Arguments @('functionapp', 'update', '-g', $ResourceGroup,
            '-n', $FunctionAppName, '--set', 'publicNetworkAccess=Disabled', '-o', 'none')
        $id = Invoke-Az -Arguments @('functionapp', 'show', '-g', $ResourceGroup,
            '-n', $FunctionAppName, '--query', 'id', '-o', 'tsv')
        if ([string]::IsNullOrWhiteSpace($id)) {
            throw 'Could not resolve the Function resource ID for public-access verification.'
        }
        $app = Invoke-Az -Arguments @('rest', '--method', 'get',
            '--uri', "${id}?api-version=2024-04-01", '-o', 'json') | ConvertFrom-Json
        if ($app.properties.publicNetworkAccess -ne 'Disabled') {
            throw 'Public Function access was not disabled; restore it before continuing.'
        }
        $null = Invoke-Az -Arguments @('functionapp', 'config', 'access-restriction', 'remove',
            '-g', $ResourceGroup, '-n', $FunctionAppName, '--rule-name', 'temporary-deployer', '-o', 'none')
    }
    finally {
        if (Test-Path -LiteralPath $zip) {
            Remove-Item -LiteralPath $zip
        }
    }
}
Write-Output 'Publication completed; public Function access is Disabled.'
