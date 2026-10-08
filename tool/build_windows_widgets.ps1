param(
    [string]$DotNet = 'dotnet',
    [switch]$Install,
    [string]$Version,
    [string]$InstallDirectory = "$env:LOCALAPPDATA/IlsangCalendar/WindowsWidgetsPackage"
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$output = Join-Path $repo 'build/windows-widgets'
$package = Join-Path $output 'package'
New-Item -ItemType Directory -Force -Path "$package/Provider", "$package/Assets", "$package/Public" | Out-Null
& $DotNet publish "$repo/windows/widgets/IlsangWidgets.csproj" -c Release -o "$package/Provider"
if ($LASTEXITCODE -ne 0) { throw 'Widget provider build failed.' }
Copy-Item -LiteralPath "$repo/windows/widgets/Package.appxmanifest" -Destination "$package/AppxManifest.xml" -Force
if (!$Version) {
    $installed = Get-AppxPackage IlsangCalendar.Widgets | Select-Object -First 1
    if ($installed -and $Install) {
        $previous = [Version]$installed.Version
        $Version = "1.0.0.$($previous.Revision + 1)"
    } else { $Version = '1.0.0.0' }
}
[xml]$manifest = Get-Content "$package/AppxManifest.xml" -Raw -Encoding utf8
$manifest.Package.Identity.Version = $Version
$manifest.Save("$package/AppxManifest.xml")
Set-Content "$package/Public/readme.txt" 'Ilsang Calendar Windows widget provider.' -Encoding utf8

# Generate package logos from the app's existing icon and picker illustrations.
Add-Type -AssemblyName System.Drawing
$icon = [Drawing.Image]::FromFile("$repo/assets/login/app-icon.png")
try {
    foreach ($entry in @(@('StoreLogo',50), @('Square44x44Logo',44), @('Square150x150Logo',150))) {
        $bitmap = New-Object Drawing.Bitmap([int]$entry[1], [int]$entry[1])
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.DrawImage($icon, 0, 0, [int]$entry[1], [int]$entry[1])
            $bitmap.Save("$package/Assets/$($entry[0]).png", [Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
    }
} finally { $icon.Dispose() }
foreach ($kind in @('Today','Month','Upcoming')) {
    $bitmap = New-Object Drawing.Bitmap(400,400)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $font = New-Object Drawing.Font('Malgun Gothic', 12)
    $heading = New-Object Drawing.Font('Malgun Gothic', 18, ([Drawing.FontStyle]::Bold))
    $brush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(40,44,54))
    try {
        $graphics.Clear([Drawing.Color]::FromArgb(247,249,253))
        $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $title = switch ($kind) { 'Today' {'오늘 일정'} 'Month' {'2026년 10월'} 'Upcoming' {'다가오는 일정'} }
        $graphics.DrawString($title, $heading, $brush, 24, 24)
        if ($kind -eq 'Month') {
            $labels = @('일','월','화','수','목','금','토')
            for ($col=0; $col -lt 7; $col++) { $graphics.DrawString($labels[$col], $font, $brush, (25+$col*50), 80) }
            for ($day=1; $day -le 31; $day++) {
                $cell = $day+3
                $graphics.DrawString("$day", $font, $brush, (25+($cell%7)*50), (115+[Math]::Floor($cell/7)*36))
            }
            $graphics.DrawString('09:00  오늘의 일정', $font, $brush, 24, 325)
        } else {
            $graphics.DrawString('10월 9일 금요일', $font, $brush, 24, 76)
            $graphics.DrawString("09:00  아침 회의`n`n14:00  프로젝트 점검`n`n18:00  운동", $font, $brush, 24, 125)
        }
        $graphics.DrawString('캘린더 열기        새로고침', $font, $brush, 24, 365)
        $bitmap.Save("$package/Assets/$kind.png", [Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose(); $font.Dispose(); $heading.Dispose(); $brush.Dispose() }
}
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}/Windows Kits/10/bin" -Directory |
    Sort-Object Name -Descending | Where-Object { Test-Path "$($_.FullName)/x64/makeappx.exe" } | Select-Object -First 1
if (!$sdk) { throw 'Windows SDK makeappx.exe is required.' }
& "$($sdk.FullName)/x64/makeappx.exe" pack /d $package /p "$output/IlsangCalendar.Widgets.msix" /o *> "$output/makeappx.log"
if ($LASTEXITCODE -ne 0) { Get-Content "$output/makeappx.log" -Tail 25; throw 'MSIX validation failed.' }
if ($Install) {
    # A loose development package avoids changing the certificate trust store.
    # A versioned path lets Windows replace an active provider without locked files.
    $destination = Join-Path $InstallDirectory $Version
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    Copy-Item -Path "$package/*" -Destination $destination -Recurse -Force
    Add-AppxPackage -Register "$destination/AppxManifest.xml" -ForceApplicationShutdown
    Write-Output "Installed: $destination"
}
Write-Output "MSIX: $output/IlsangCalendar.Widgets.msix"
