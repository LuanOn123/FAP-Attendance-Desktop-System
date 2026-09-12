$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$flutterCommand = if (Test-Path '.tools/flutter/bin/flutter.bat') { '.\.tools\flutter\bin\flutter.bat' } else { 'flutter' }
if (Test-Path '.tools/flutter') { $env:PUB_CACHE = Join-Path (Get-Location) '.tools/pub-cache' }
& $flutterCommand pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $flutterCommand analyze --no-pub
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $flutterCommand test --no-pub
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
node --test backend/test/core.test.cjs
exit $LASTEXITCODE
