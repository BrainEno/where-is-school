#!/usr/bin/env bash
set -euo pipefail
: "${JAVA_HOME_17_X64:?The runner needs JDK 17}" "${ANDROID_HOME:?The runner needs the Android SDK}"
export JAVA_HOME="$JAVA_HOME_17_X64"
sdkmanager=$(find "$ANDROID_HOME/cmdline-tools" -path '*/bin/sdkmanager' -type f | sort -V | tail -1)
test -x "$sdkmanager"
printf 'JAVA_HOME=%s\nANDROID_SDKMANAGER=%s\n' "$JAVA_HOME" "$sdkmanager" >> "$GITHUB_ENV"
"$JAVA_HOME/bin/java" -version
"$sdkmanager" --sdk_root="$ANDROID_HOME" platform-tools 'platforms;android-36' 'build-tools;36.1.0'
