# Synthetic ADB responses exercise failure boundaries only, not game startup.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$smoke = Join-Path $root 'tools/android/smoke.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('wis debug test ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $apk = Join-Path $temp 'preview test.apk'
    Set-Content -LiteralPath $apk -Value 'not a real APK'
    $adb = Join-Path $temp 'adb fixture.ps1'
    @'
$package = 'io.github.braineno.whereisschool.preview'
if ($args[0] -eq 'devices') {
    'List of devices attached'
    'authorized-1  device product:test'
    'locked-2  unauthorized'
    if ($env:WIS_SMOKE_FIXTURE -eq 'multiple') { 'authorized-3  device product:test' }
    exit 0
}
if ($args[0] -ne '-s' -or $args[1] -ne 'authorized-1') { throw 'ADB command not routed to the chosen device' }
switch ($args[2]) {
    'install' {
        if ($args[3] -ne '-r' -or $args[4] -notlike '*preview test.apk') { throw 'APK path or install flags changed' }
        'Performing Streamed Install'; 'Success'
    }
    'shell' {
        switch ($args[3]) {
            'cmd' { "$package/.GodotAppLauncher" }
            'am' { if ($args[4] -eq 'start') { 'Status: ok' } }
            'pidof' { '234' }
            'dumpsys' {
                if ($env:WIS_SMOKE_FIXTURE -ne 'background') { "topResumedActivity=ActivityRecord{ u0 $package/.GodotApp}" }
            }
            'screencap' { }
            'rm' { }
            default { throw 'Unexpected adb shell operation' }
        }
    }
    'logcat' {
        if ($args -contains '-c' -or $args -notcontains '--pid=234') { throw 'ADB logs must be scoped, never cleared' }
        'OpenGL API OpenGL ES - Compatibility'
        if ($env:WIS_SMOKE_FIXTURE -eq 'crash') { 'FATAL EXCEPTION' }
    }
    'pull' {
        [IO.File]::WriteAllBytes($args[4], [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMBA7ppkN0AAAAASUVORK5CYII='))
    }
    default { throw 'Unexpected adb operation' }
}
exit 0
'@ | Set-Content -LiteralPath $adb -Encoding utf8
    foreach ($case in @('ok', 'crash', 'background', 'multiple', 'locked')) {
        $env:WIS_SMOKE_FIXTURE = $case
        $out = Join-Path $temp $case
        $serial = if ($case -eq 'locked') { 'locked-2' } else { '' }
        $failure = ''
        try { & $smoke -Apk $apk -Output $out -Adb $adb -Serial $serial -NonInteractive }
        catch { $failure = $_.Exception.Message }
        $expected = @{'ok'=''; 'crash'='runtime errors'; 'background'='foreground process';
                      'multiple'='More than one device'; 'locked'='offline, unauthorized or missing'}[$case]
        if (($case -eq 'ok' -and ($failure -or -not (Test-Path -LiteralPath (Join-Path $out 'title.png')))) -or
            ($case -ne 'ok' -and -not $failure.Contains($expected))) {
            throw "Unexpected $case verdict: $failure"
        }
    }
    # Exercise the native .cmd wrapper's non-zero exit and quoted paths on Windows.
    if ($env:OS -eq 'Windows_NT') {
        $test = Join-Path $root 'tools/windows/android/Test.cmd'
        $wrapperError = Join-Path $temp 'wrapper-error.txt'
        $ErrorActionPreference = 'Continue' # PS 5.1 may write native stderr as ErrorRecords.
        try {
            & $test -Apk (Join-Path $temp 'missing file.apk') -NonInteractive 2> $wrapperError
            $wrapperExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = 'Stop' }
        if ($wrapperExit -eq 0 -or (Get-Content -LiteralPath $wrapperError -Raw) -notmatch 'Download and extract') {
            throw 'Batch debug wrapper did not propagate the expected missing-APK failure.'
        }
    }
    Write-Host 'PASS: Android launch verdict fixtures (success, crash, background, multiple and unauthorized devices).'
} catch {
    Write-Host "::error title=Windows Android debug::$($_.Exception.Message)"
    throw
} finally {
    Remove-Item Env:WIS_SMOKE_FIXTURE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}

exit 0 # The last native exit was an intentional negative case.
