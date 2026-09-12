param([Parameter(Mandatory=$true)][string]$ImagePath)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    [void][Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
    [void][Windows.Storage.FileAccessMode, Windows.Storage, ContentType=WindowsRuntime]
    [void][Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
    [void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    function Await-Operation($Operation, [Type]$ResultType) {
        $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
        if (-not $task.Wait(45000)) { throw 'OCR operation timed out.' }
        return $task.Result
    }
    $resolved = (Resolve-Path -LiteralPath $ImagePath).Path
    # Upscale small timetable labels before recognition.
    Add-Type -AssemblyName System.Drawing
    $source = [System.Drawing.Bitmap]::new($resolved)
    $prepared = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString() + '.png')
    try {
        $scale = [Math]::Min(2, [Windows.Media.Ocr.OcrEngine]::MaxImageDimension / [Math]::Max($source.Width, $source.Height))
        $large = [System.Drawing.Bitmap]::new([int]($source.Width * $scale), [int]($source.Height * $scale))
        $graphics = [System.Drawing.Graphics]::FromImage($large)
        try {
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($source, 0, 0, $large.Width, $large.Height)
            $large.Save($prepared, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $large.Dispose() }
    } finally { $source.Dispose() }
    $resolved = $prepared
    $file = Await-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($resolved)) ([Windows.Storage.StorageFile])
    $stream = Await-Operation ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
    try {
        $decoder = Await-Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $bitmap = Await-Operation ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        try {
            [void][Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime]
            $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new('en-US'))
            if ($null -eq $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
            if ($null -eq $engine) { throw 'No Windows OCR language installed. Install an OCR language in Windows Settings.' }
            if ($bitmap.PixelWidth -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension -or $bitmap.PixelHeight -gt [Windows.Media.Ocr.OcrEngine]::MaxImageDimension) {
                throw 'Image too large for Windows OCR. Resize the image and retry.'
            }
            $result = Await-Operation ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
            $lines = @($result.Lines | ForEach-Object { $_.Text })
            $words = @($result.Lines | ForEach-Object { $_.Words | ForEach-Object {
                @{text=$_.Text; x=($_.BoundingRect.X / $scale); y=($_.BoundingRect.Y / $scale); width=($_.BoundingRect.Width / $scale); height=($_.BoundingRect.Height / $scale)}
            } })
            # Overlapping tiles recover short labels omitted by the full-image pass.
            $cropSource = [System.Drawing.Bitmap]::new($prepared)
            try {
                $step = [int](24 * $scale)
                for ($top = 0; $top -lt $cropSource.Height; $top += $step) {
                    for ($left = 0; $left -lt $cropSource.Width; $left += [int](200 * $scale)) {
                    $cropPath = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString() + '.png')
                    $rect = [System.Drawing.Rectangle]::new($left, $top, [Math]::Min([int](260 * $scale), $cropSource.Width - $left), [Math]::Min($step * 2, $cropSource.Height - $top))
                    $crop = $cropSource.Clone($rect, $cropSource.PixelFormat)
                    try { $crop.Save($cropPath, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
                    $cs = $null; $cb = $null
                    try {
                        $cf = Await-Operation ([Windows.Storage.StorageFile]::GetFileFromPathAsync($cropPath)) ([Windows.Storage.StorageFile])
                        $cs = Await-Operation ($cf.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
                        $cd = Await-Operation ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($cs)) ([Windows.Graphics.Imaging.BitmapDecoder])
                        $cb = Await-Operation ($cd.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
                        $cr = Await-Operation ($engine.RecognizeAsync($cb)) ([Windows.Media.Ocr.OcrResult])
                        foreach ($cl in $cr.Lines) { foreach ($cw in $cl.Words) {
                            if ($cw.Text -match '^(?:[AP][1-6]|THU|MON|TUE|WED|FRI|SAT|SUN|\(?\d{1,2}:\d{2}.*)$') {
                                $wx = ($cw.BoundingRect.X + $left) / $scale
                                $wy = ($cw.BoundingRect.Y + $top) / $scale
                                $exists = @($words | Where-Object { [Math]::Abs($_.x - $wx) -lt 8 -and [Math]::Abs($_.y - $wy) -lt 8 })
                                if ($exists.Count -eq 0) { $words += @{text=$cw.Text; x=$wx; y=$wy; width=($cw.BoundingRect.Width / $scale); height=($cw.BoundingRect.Height / $scale)} }
                            }
                        } }
                    } finally {
                        if ($cb) { $cb.Dispose() }; if ($cs) { $cs.Dispose() }
                        Remove-Item -LiteralPath $cropPath
                    }
                }
                }
            } finally { $cropSource.Dispose() }
            @{ok=$true; text=($lines -join "`n"); words=$words} | ConvertTo-Json -Compress -Depth 5
        } finally { if ($bitmap) { $bitmap.Dispose() } }
    } finally { if ($stream) { $stream.Dispose() } }
} catch {
    @{ok=$false; error=$_.Exception.Message} | ConvertTo-Json -Compress
    exit 1
} finally {
    if ($prepared -and (Test-Path -LiteralPath $prepared)) { Remove-Item -LiteralPath $prepared }
}



