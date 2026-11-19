#!/usr/bin/env bash
# Launch the same artifact that a tester downloads, not a desktop --mobile-preview.
set -euo pipefail
apk="$1"
package=io.github.braineno.whereisschool.preview
out=build/android-smoke
mkdir -p "$out"
if [[ "${2:-}" == --boot ]]; then
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
fi
adb install -r "$apk"
adb shell am force-stop "$package"
adb logcat -c
# Use the manifest's launcher component, not a hard-coded Godot template class name.
component="$(adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER "$package" | tr -d '\r' | tail -n 1)"
[[ "$component" == "$package/"* ]]
adb shell am start -W -n "$component" | tee "$out/launch.txt"
grep -q 'Status: ok' "$out/launch.txt"
# Wait for the renderer, not just an Activity that momentarily appeared on the screen.
for (( n=0; n<30; n++ )); do
  adb logcat -d -v brief -s godot '*:S' > "$out/godot.log"
  if grep -Eiq 'OpenGL (API|ES)|Compatibility.*Renderer' "$out/godot.log"; then break; fi
  sleep 2
done
grep -Eiq 'OpenGL (API|ES)|Compatibility.*Renderer' "$out/godot.log"
adb shell dumpsys activity activities > "$out/activities.txt"
grep -E 'mResumedActivity:|topResumedActivity=' "$out/activities.txt" | grep -F "$package"
adb logcat -d -v brief -s AndroidRuntime '*:S' > "$out/android-runtime.log"
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|FATAL EXCEPTION' "$out/"*.log; then
  grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|FATAL EXCEPTION' "$out/"*.log >&2
  exit 1
fi
adb exec-out screencap -p > "$out/title.png"
echo '::notice title=Android emulator::The verified APK installed, started and reached the Compatibility renderer.'
