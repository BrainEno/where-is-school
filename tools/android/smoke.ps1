# The same native test runs on a CI emulator and on a Windows USB/virtual device.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Apk,
    [Parameter(Mandatory)][string]$Output,
    [string]$Adb = 'adb',
    [string]$Serial,
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
$package = 'io.github.braineno.whereisschool.preview'
$route = @()

function Invoke-Adb {
    param([string[]]$Arguments)
    $result = & $Adb @route @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "adb $($Arguments -join ' ') failed ($LASTEXITCODE). Output: $($result -join ' '). Check the selected device and the log directory: $Output"
    }
    return $result
}

$apkPath = (Get-Item -LiteralPath $Apk).FullName
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf) -or $apkPath -notlike '*.apk') {
    throw 'Select the Android preview .apk, not the downloaded ZIP.'
}
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Path $Output -Force | Out-Null
$inventory = @(Invoke-Adb @('devices', '-l'))
$inventory | Set-Content -LiteralPath (Join-Path $Output 'devices.txt') -Encoding utf8
$devices = @($inventory | Where-Object { $_ -match '^\S+\s+device(?:\s|$)' })
$ids = @($devices | ForEach-Object { ($_ -split '\s+', 2)[0] })
if (-not $ids.Count) {
    throw "No authorized Android device. $($inventory -join ' ') Enable USB debugging, accept the phone prompt or start your emulator."
}
if (-not $Serial) {
    if ($ids.Count -eq 1) { $Serial = $ids[0] }
    elseif ($NonInteractive) { throw 'More than one device; specify -Serial from adb devices -l.' }
    else {
        for ($i = 0; $i -lt $devices.Count; $i++) { Write-Host "[$($i + 1)] $($devices[$i])" }
        $n = 0
        if (-not [int]::TryParse((Read-Host 'Select device number'), [ref]$n) -or $n -lt 1 -or $n -gt $ids.Count) {
            throw 'Invalid device number.'
        }
        $Serial = $ids[$n - 1]
    }
}
if ($Serial -cnotin $ids) { throw "Device '$Serial' is offline, unauthorized or missing." }
$route = @('-s', $Serial)
Write-Host "Installing preview on $Serial (preserving existing data)."
$install = @(Invoke-Adb @('install', '-r', $apkPath))
$install | Set-Content -LiteralPath (Join-Path $Output 'install.txt') -Encoding utf8
if (-not ($install -match '^Success\s*$')) { throw 'Android did not report a successful install.' }
$component = (Invoke-Adb @('shell', 'cmd', 'package', 'resolve-activity', '--brief', '-a',
    'android.intent.action.MAIN', '-c', 'android.intent.category.LAUNCHER', $package) | Select-Object -Last 1)
if ($component -cnotmatch ('^' + [regex]::Escape($package) + '/[A-Za-z0-9_.$]+$')) {
    throw 'The installed preview has no MAIN/LAUNCHER component. Use the APK from the Android build workflow.'
}
Invoke-Adb @('shell', 'am', 'force-stop', $package) | Out-Null
$launch = @(Invoke-Adb @('shell', 'am', 'start', '-W', '-n', $component))
$launch | Set-Content -LiteralPath (Join-Path $Output 'launch.txt') -Encoding utf8
if (-not ($launch -match '^Status: ok\s*$')) { throw 'Android refused to launch the preview.' }
$appPid = ((Invoke-Adb @('shell', 'pidof', $package)) -join '').Trim()
if ($appPid -notmatch '^\d+$') { throw 'The preview did not retain a running process after launch.' }

# Read only this process' logs. Never clear a physical phone's log buffer.
$timer = [Diagnostics.Stopwatch]::StartNew()
do {
    $logs = (Invoke-Adb @('logcat', '-d', "--pid=$appPid", '-v', 'brief', '-s', 'godot', 'AndroidRuntime', '*:S')) -join "`n"
    $logs | Set-Content -LiteralPath (Join-Path $Output 'runtime.log') -Encoding utf8
    if ($logs -match 'SCRIPT ERROR|Parse Error|Failed to load script|FATAL EXCEPTION') {
        throw 'Game script or Android runtime errors found in runtime.log.'
    }
    if ($logs -match 'OpenGL (API|ES)|Compatibility.*Renderer') { break }
    Start-Sleep -Seconds 2
} while ($timer.Elapsed.TotalSeconds -lt 60)
if ($logs -notmatch 'OpenGL (API|ES)|Compatibility.*Renderer') { throw 'Godot did not report a renderer within 60 seconds.' }
$activities = @(Invoke-Adb @('shell', 'dumpsys', 'activity', 'activities'))
$foreground = $activities -match ('(?:mResumedActivity:|topResumedActivity=).*' + [regex]::Escape($package) + '/')
$foreground | Set-Content -LiteralPath (Join-Path $Output 'foreground.txt') -Encoding utf8
if (-not $foreground -or ((Invoke-Adb @('shell', 'pidof', $package)) -join '').Trim() -ne $appPid) {
    throw 'The preview lost its foreground process. Unlock the device and check runtime.log.'
}
# adb pull keeps the PNG binary with both Windows PowerShell 5.1 and pwsh.
$remote = '/data/local/tmp/wis-' + [guid]::NewGuid().ToString('N') + '.png'
try {
    Invoke-Adb @('shell', 'screencap', '-p', $remote) | Out-Null
    Invoke-Adb @('pull', $remote, (Join-Path $Output 'title.png')) | Out-Null
} finally {
    & $Adb @route shell rm -f $remote
}
if ((Get-Item -LiteralPath (Join-Path $Output 'title.png')).Length -lt 8) { throw 'Empty screenshot.' }
Write-Host "PASS: APK installed, launched and reached the Compatibility renderer in the foreground. Evidence: $Output"
