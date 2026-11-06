#!/usr/bin/env bash
# Linux/CI validation. GODOT can point to the pinned Godot 4.7.2 executable.
set -euo pipefail

cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

run_checked() {
  local name="$1"
  local expected="$2"
  shift 2
  local log="$logs/$name.log"
  echo "==> $name: $*"
  if ! "$@" 2>&1 | tee "$log"; then
    echo "FAIL: $name returned a nonzero exit status." >&2
    return 1
  fi
  # Godot may still exit 0 after a parse or runtime error; fail on the output too.
  if grep -Eq 'SCRIPT ERROR|ERROR:|FAIL:' "$log"; then
    echo "FAIL: $name emitted an error." >&2
    return 1
  fi
  if [[ -n "$expected" ]] && ! grep -Eq "$expected" "$log"; then
    echo "FAIL: $name did not report completion." >&2
    return 1
  fi
}

run_checked import '' "$GODOT" --headless --editor --path . --quit
run_checked smoke '^Smoke test passed:' "$GODOT" --headless --path . --script res://tests/smoke_test.gd
# A bounded run plus a completion marker prevents a script error or stalled test
# from being mistaken for a successful quit. The test scene needs autoloads.
run_checked prologue '^Prologue tests passed: [0-9]+ checks' "$GODOT" --headless --path . --fixed-fps 60 --quit-after 20000 res://tests/prologue_test.tscn
