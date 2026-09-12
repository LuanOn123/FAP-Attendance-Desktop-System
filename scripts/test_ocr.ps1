$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureDirectory = Join-Path $projectRoot 'test/fixtures'
New-Item -ItemType Directory -Force -Path $fixtureDirectory | Out-Null
$imageFile = Join-Path $fixtureDirectory 'schedule_ocr.png'
$bitmap = New-Object System.Drawing.Bitmap(1800, 240)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$font = New-Object System.Drawing.Font('Arial', 28)
try {
    $graphics.Clear([System.Drawing.Color]::White)
    $graphics.DrawString('FA26 PRM393 SE1848 Mon Slot 1', $font, [System.Drawing.Brushes]::Black, 30, 30)
    $graphics.DrawString('07:30-09:00 Room AL-201', $font, [System.Drawing.Brushes]::Black, 30, 110)
    $bitmap.Save($imageFile, [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $font.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
& "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $projectRoot 'assets/ocr_windows.ps1') -ImagePath $imageFile
exit $LASTEXITCODE
