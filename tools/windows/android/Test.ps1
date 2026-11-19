[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Apk,
    [string]$Serial,
    [string]$SdkRoot,
    [switch]$Emulator,
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Environment.ps1"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$sdk = Get-WisSdk $SdkRoot
$adb = Join-Path $sdk 'platform-tools\adb.exe'
if (-not $Apk) {
    $mobile = Join-Path $root 'build\mobile'
    $packages = @()
    if (Test-Path -LiteralPath $mobile) {
        $packages = @(Get-ChildItem -LiteralPath $mobile -Recurse -File -Filter 'where-is-school-preview.apk')
    }
    if ($packages.Count -eq 1) { $Apk = $packages[0].FullName }
    elseif ($NonInteractive) { throw 'Specify -Apk (no unique preview APK under build/mobile).' }
    else { $Apk = (Read-Host 'Path to extracted where-is-school-preview.apk').Trim('"') }
}
if (-not $Apk -or $Apk -notlike '*.apk' -or -not (Test-Path -LiteralPath $Apk -PathType Leaf)) {
    throw 'Download and extract the Android workflow artifact, then drag its .apk onto Test.cmd or pass -Apk.'
}
$package = Get-Item -LiteralPath $Apk
$manifestPath = Join-Path $package.DirectoryName 'BUILD.json'
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.target -ne 'android-preview' -or $manifest.artifact -ne $package.Name -or
        $manifest.sha256 -ne (Get-FileHash -LiteralPath $package.FullName -Algorithm SHA256).Hash) {
        throw 'APK SHA-256 or identity differs from BUILD.json. Download the matching artifact again.'
    }
}
if (-not (Test-Path -LiteralPath $adb)) { & "$PSScriptRoot\Setup.ps1" -SdkRoot $sdk }
$out = Join-Path $root ('build\mobile\android-debug\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $out -Force | Out-Null
if ($Emulator) {
    if ($Serial) { throw 'Use either -Emulator for the dedicated AVD or -Serial for an already running device.' }
    Set-WisAvdEnvironment $sdk
    $avd = 'wis-debug-api36'
    $port = 5564
    $Serial = "emulator-$port"
    $emulatorExe = Join-Path $sdk 'emulator\emulator.exe'
    if (-not (Test-Path -LiteralPath $emulatorExe)) { throw 'Run Setup.cmd -Emulator first.' }
    $names = @(& $emulatorExe -list-avds)
    if ($LASTEXITCODE -ne 0 -or $avd -notin $names) { throw 'The debug AVD is missing. Run Setup.cmd -Emulator first.' }
    & $adb start-server
    if ($LASTEXITCODE -ne 0) { throw 'adb start-server failed.' }
    $running = @(& $adb devices)
    if ($LASTEXITCODE -ne 0) { throw 'adb devices failed.' }
    $process = $null
    if (-not ($running -match "^$Serial\s")) {
        $process = Start-Process -FilePath $emulatorExe -ArgumentList '-avd', $avd, '-port', $port, '-no-snapshot-load' `
            -RedirectStandardOutput (Join-Path $out 'emulator.log') `
            -RedirectStandardError (Join-Path $out 'emulator-errors.log') -PassThru
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        # No adb wait-for-device: a failed emulator should not block the user indefinitely.
        $current = @(& $adb devices)
        if ($current -match "^$Serial\s+device\s*$") {
            $boot = (& $adb -s $Serial shell getprop sys.boot_completed) -join ''
            if ($LASTEXITCODE -eq 0 -and $boot.Trim() -eq '1') { break }
        }
        if ($process -and $process.HasExited) { throw "Emulator exited. See $out; check Windows Hypervisor Platform and BIOS virtualization." }
        if ($timer.Elapsed.TotalSeconds -ge 420) { throw "Emulator boot timed out. See $out." }
        Start-Sleep -Seconds 2
    } while ($true)
    $activeName = & $adb -s $Serial emu avd name | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or $activeName.Trim() -ne $avd) { throw "Port $port is occupied by another AVD." }
    & $adb -s $Serial shell input keyevent KEYCODE_WAKEUP
    if ($LASTEXITCODE -ne 0) { throw 'Could not wake the emulator.' }
    & $adb -s $Serial shell wm dismiss-keyguard
    if ($LASTEXITCODE -ne 0) { throw 'Could not dismiss the emulator keyguard.' }
}
& (Join-Path $root 'tools\android\smoke.ps1') -Apk $package.FullName -Adb $adb -Serial $Serial `
    -Output $out -NonInteractive:$NonInteractive
Write-Host 'The game stays open for touch testing. Use adb -s <serial> logcat -s godot to follow logs.'
