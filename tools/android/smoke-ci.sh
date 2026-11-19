#!/usr/bin/env bash
# GitHub's Ubuntu runner provides KVM and JDK. The APK test is shared with Windows.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
apk="${1:?Pass the APK to be tested}"
out="${2:?Pass the log output directory}"
mkdir -p "$out"
image='system-images;android-36;google_apis;x86_64'
name=wis-api36
port=5554
sudo chmod a+rw /dev/kvm
"$ANDROID_SDKMANAGER" --sdk_root="$ANDROID_HOME" emulator "$image"
avdmanager="$(dirname "$ANDROID_SDKMANAGER")/avdmanager"
emulator="$ANDROID_HOME/emulator/emulator"

# The command-line tools and emulator must use the same AVD registry. Align the
# legacy SDK user-home variable too: some tools still read its .android/avd.
avd_session="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/wis-android.XXXXXX")"
export ANDROID_USER_HOME="$avd_session/.android"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
export ANDROID_SDK_HOME="$avd_session"
mkdir -p "$ANDROID_AVD_HOME"
# This is a runtime launch check, not a particular phone profile. Use the
# installed image's default instead of assuming a device ID exists in sdk-tools.
printf 'no\n' | "$avdmanager" create avd --force --name "$name" --package "$image" \
  --path "$ANDROID_AVD_HOME/$name.avd"
"$emulator" -list-avds | tee "$out/avds.txt"
if ! grep -Fxq "$name" "$out/avds.txt"; then
  echo "Created AVD $name is not visible to the emulator in ANDROID_AVD_HOME" >&2
  ls -la "$ANDROID_AVD_HOME" >&2
  exit 1
fi

export PATH="$ANDROID_HOME/platform-tools:$PATH"
export ANDROID_SERIAL="emulator-$port"
adb start-server
"$emulator" -avd "$name" -port "$port" -no-window -no-snapshot -noaudio -no-boot-anim \
  -gpu swiftshader_indirect > "$out/emulator.log" 2>&1 &
emulator_pid=$!
trap 'kill "$emulator_pid" 2>/dev/null || true' EXIT
deadline=$((SECONDS + 420))
until [[ "$(timeout 5 adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)" == 1 ]]; do
  if ! kill -0 "$emulator_pid" 2>/dev/null; then
    echo "Emulator exited before Android finished booting" >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo "Android boot timed out" >&2
    adb devices -l | tee "$out/devices.txt"
    exit 1
  fi
  sleep 2
done
adb shell input keyevent KEYCODE_WAKEUP
adb shell wm dismiss-keyguard
timeout 120 pwsh -NoLogo -NoProfile -File "$root/tools/android/smoke.ps1" \
  -Apk "$apk" -Output "$out" -Adb "$ANDROID_HOME/platform-tools/adb" -Serial "$ANDROID_SERIAL" -NonInteractive
