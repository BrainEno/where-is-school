[CmdletBinding()]
param([string]$SdkRoot, [switch]$Update, [switch]$Emulator, [string]$JavaHome = $env:JAVA_HOME)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. "$PSScriptRoot\Environment.ps1"
$sdk = Get-WisSdk $SdkRoot
$adb = Join-Path $sdk 'platform-tools\adb.exe'

function Install-Tools([string]$Url, [string]$Folder, [string]$Destination, [string]$Probe, [string]$Sha256) {
    # Stage on the same volume and don't replace a working install until validation.
    $temp = Join-Path $sdk ('.download-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $zip = Join-Path $temp 'download.zip'
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $zip
        if ($Sha256 -and (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $Sha256) {
            throw 'Android SDK command-line tools checksum mismatch.'
        }
        Expand-Archive -LiteralPath $zip -DestinationPath $temp
        $source = Join-Path $temp $Folder
        if (-not (Test-Path -LiteralPath (Join-Path $source $Probe) -PathType Leaf)) { throw 'Unexpected Android SDK ZIP layout.' }
        if ($Probe -eq 'adb.exe') {
            & (Join-Path $source $Probe) version
            if ($LASTEXITCODE -ne 0) { throw 'Downloaded adb cannot run on this Windows machine.' }
        }
        $backup = $Destination + '.wis-backup-' + [guid]::NewGuid().ToString('N')
        if (Test-Path -LiteralPath $Destination) { Move-Item -LiteralPath $Destination -Destination $backup }
        try { Move-Item -LiteralPath $source -Destination $Destination }
        catch {
            if (Test-Path -LiteralPath $backup) { Move-Item -LiteralPath $backup -Destination $Destination }
            throw
        }
        if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}

if ($Update -or -not (Test-Path -LiteralPath $adb)) {
    if ($Update -and (Get-Process adb -ErrorAction SilentlyContinue)) {
        throw 'Stop your ADB session intentionally (adb kill-server) before updating, then run Setup again.'
    }
    Write-Host 'Downloading Android Platform-Tools from Google...'
    Install-Tools 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' 'platform-tools' `
        (Join-Path $sdk 'platform-tools') 'adb.exe'
}
& $adb version
if ($LASTEXITCODE -ne 0) { throw 'adb version failed. Run Setup.ps1 -Update to repair the SDK.' }
Write-Host "ADB ready: $adb"
if (-not $Emulator) { return }

if (-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin\java.exe'))) {
    throw 'Install a JDK 17 (e.g. Temurin) and pass -JavaHome or set JAVA_HOME before preparing the emulator.'
}
$env:JAVA_HOME = $JavaHome
Set-WisAvdEnvironment $sdk
New-Item -ItemType Directory -Path $env:ANDROID_AVD_HOME -Force | Out-Null
$cmdline = Join-Path $sdk 'cmdline-tools\16.0'
$sdkmanager = Join-Path $cmdline 'bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $sdkmanager)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $cmdline) -Force | Out-Null
    # Google's SDK 16.0 archive and SHA-256 also used by the Windows 2025 runner image.
    Install-Tools 'https://dl.google.com/android/repository/commandlinetools-win-12266719_latest.zip' `
        'cmdline-tools' $cmdline 'bin\sdkmanager.bat' 'F9088C04A44F1F37A8A3A228A7663E11AE9445FA07529C96CEF38ACB985A88F3'
}
Write-Host 'Review and accept the Android SDK licenses if prompted.'
& $sdkmanager "--sdk_root=$sdk" --licenses
if ($LASTEXITCODE -ne 0) { throw 'Android SDK license step failed.' }
$image = 'system-images;android-36;google_apis;x86_64'
& $sdkmanager "--sdk_root=$sdk" 'emulator' $image
if ($LASTEXITCODE -ne 0) { throw 'Android emulator/runtime installation failed.' }
$emulatorExe = Join-Path $sdk 'emulator\emulator.exe'
$avd = 'wis-debug-api36'
$known = @(& $emulatorExe -list-avds)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate Android emulators.' }
if ($avd -notin $known) {
    'no' | & (Join-Path $cmdline 'bin\avdmanager.bat') create avd --name $avd --package $image `
        --path (Join-Path $env:ANDROID_AVD_HOME "$avd.avd")
    if ($LASTEXITCODE -ne 0) { throw 'AVD creation failed.' }
}
$registered = @(& $emulatorExe -list-avds)
if ($LASTEXITCODE -ne 0 -or $avd -notin $registered) { throw 'The emulator cannot see its AVD registration.' }
& $emulatorExe -accel-check
if ($LASTEXITCODE -ne 0) { throw 'Enable host virtualization and Windows Hypervisor Platform; this script does not change system settings.' }
Write-Host 'Prepared wis-debug-api36. Run Test.cmd -Emulator with the downloaded preview APK.'
