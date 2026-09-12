$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$flutterCommand = if (Test-Path '.tools/flutter/bin/flutter.bat') { '.\.tools\flutter\bin\flutter.bat' } else { 'flutter' }
if (Test-Path '.tools/flutter') { $env:PUB_CACHE = Join-Path (Get-Location) '.tools/pub-cache' }
& $flutterCommand run -d windows --dart-define=DEMO_MODE=true
exit $LASTEXITCODE
