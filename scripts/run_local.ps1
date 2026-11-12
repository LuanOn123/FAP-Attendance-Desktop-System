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
foreach ($key in @('GOOGLE_CLIENT_ID')) {
    if ([string]::IsNullOrWhiteSpace([string]$localConfig.$key)) {
        throw "Missing required configuration key: $key"
    }
}
$flutterCommand = if (Test-Path '.tools/flutter/bin/flutter.bat') { '.\.tools\flutter\bin\flutter.bat' } else { 'flutter' }
if (Test-Path '.tools/flutter') { $env:PUB_CACHE = Join-Path (Get-Location) '.tools/pub-cache' }
& $flutterCommand run -d windows --dart-define-from-file=config/local.json --dart-define=FIREBASE_GROUP_SIGNUP=true
exit $LASTEXITCODE
