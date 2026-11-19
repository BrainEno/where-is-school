# Dot-source from the setup and test entry points; no machine-wide changes.
function Get-WisSdk([string]$SdkRoot) {
    if (-not $SdkRoot) { $SdkRoot = Join-Path $env:LOCALAPPDATA 'WhereIsSchool\Android\Sdk' }
    return [IO.Path]::GetFullPath($SdkRoot)
}

function Set-WisAvdEnvironment([string]$SdkRoot) {
    $env:ANDROID_HOME = $SdkRoot
    $env:ANDROID_SDK_ROOT = $SdkRoot
    $env:ANDROID_SDK_HOME = Join-Path $SdkRoot 'wis-emulator-home'
    $env:ANDROID_USER_HOME = Join-Path $env:ANDROID_SDK_HOME '.android'
    $env:ANDROID_EMULATOR_HOME = $env:ANDROID_USER_HOME
    $env:ANDROID_AVD_HOME = Join-Path $env:ANDROID_USER_HOME 'avd'
}
