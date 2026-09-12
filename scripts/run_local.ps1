$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$configPath = Join-Path (Get-Location) 'config/local.json'
if (-not (Test-Path -LiteralPath $configPath)) {
    throw 'Missing config/local.json. Copy config/example.json, fill in your values, and save it.'
}
$configText = Get-Content -LiteralPath $configPath -Raw
if ([string]::IsNullOrWhiteSpace($configText)) {
    throw 'config/local.json is empty on disk. Save the file in your editor before running.'
}
try { $localConfig = ConvertFrom-Json -InputObject $configText -ErrorAction Stop }
catch { throw 'config/local.json contains invalid JSON. Check commas and double quotes.' }
foreach ($key in @('GOOGLE_CLIENT_ID', 'APPS_SCRIPT_URL')) {
    if ([string]::IsNullOrWhiteSpace([string]$localConfig.$key)) {
        throw "Missing required configuration key: $key"
    }
}
$endpoint = $null
if (-not [Uri]::TryCreate([string]$localConfig.APPS_SCRIPT_URL, [UriKind]::Absolute, [ref]$endpoint) -or
    $endpoint.Scheme -ne 'https' -or $endpoint.Host -ne 'script.google.com' -or -not $endpoint.AbsolutePath.EndsWith('/exec')) {
    throw 'APPS_SCRIPT_URL must be an HTTPS script.google.com deployment URL ending in /exec.'
}
$flutterCommand = if (Test-Path '.tools/flutter/bin/flutter.bat') { '.\.tools\flutter\bin\flutter.bat' } else { 'flutter' }
if (Test-Path '.tools/flutter') { $env:PUB_CACHE = Join-Path (Get-Location) '.tools/pub-cache' }
& $flutterCommand run -d windows --dart-define-from-file=config/local.json
exit $LASTEXITCODE
