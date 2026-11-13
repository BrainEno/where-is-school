#!/usr/bin/env bash
# The behaviour `tools/ci_run_check.sh` is supposed to have, tested without Godot.
#
# The point of these cases is the one the old inline version got wrong: a check whose
# process exits 0 while its log carries an unhandled GDScript error was counted as a pass.
# Every case below is a fake command writing a fake log, so the whole file runs in under a
# second and needs no engine.
#
# Usage: bash tests/run_check_test.sh

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CI_LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${CI_LOG_DIR}"' EXIT

# shellcheck source=../tools/ci_run_check.sh
source "${root}/tools/ci_run_check.sh"

failures=0
cases=0

# `expect <description> <expected: pass|fail> <fake command…>`
expect () {
  local description="$1"; shift
  local wanted="$1"; shift
  checks=0
  passed=""
  status=0
  run_check "${CURRENT_NAME}" 30 "$@" > /dev/null 2>&1
  local got="pass"
  if [ "${status}" -ne 0 ]; then
    got="fail"
  fi
  cases=$((cases + 1))
  if [ "${got}" != "${wanted}" ]; then
    echo "FAIL: ${description}: expected ${wanted}, got ${got}"
    failures=$((failures + 1))
  else
    echo "ok: ${description} (${got})"
  fi
}

CURRENT_NAME=clean_pass
expect "exit 0 + PASS is a pass" pass bash -c 'printf "PASS: all good\n"'

CURRENT_NAME=clean_failure
expect "exit 1 + PASS is a failure" fail bash -c 'printf "PASS: all good\n"; exit 1'

CURRENT_NAME=script_error
expect "exit 0 + SCRIPT ERROR is a failure" fail \
  bash -c 'printf "SCRIPT ERROR: previously freed instance\n"'

CURRENT_NAME=parse_error
expect "exit 0 + Parse Error is a failure" fail \
  bash -c 'printf "Parse Error at res://scripts/x.gd:3\n"'

CURRENT_NAME=test_failure
expect "exit 0 + TEST FAILURE is a failure" fail \
  bash -c 'printf "TEST FAILURE: the exit sits 25 m off\n"'

CURRENT_NAME=no_verdict
expect "exit 0 with no PASS verdict is a failure" fail bash -c 'printf "did something\n"'

CURRENT_NAME=error_noise
expect "an ordinary engine ERROR with a PASS is a pass" pass \
  bash -c 'printf "ERROR: leaked instance\nPASS: fine\n"'

CURRENT_NAME=import
expect "the import pass keeps its exception (errors ignored, no verdict needed)" pass \
  bash -c 'printf "ERROR: theme font not imported\n"'

CURRENT_NAME=capture_script
expect "the compile-only check needs no PASS verdict" pass bash -c 'printf "compiled\n"'

CURRENT_NAME=capture_script_broken
expect "the compile-only check still fails on a parse error" fail \
  bash -c 'printf "Parse Error at res://tests/capture_playthrough.gd:9\n"'

# A hung check is stopped by `timeout` and must be reported as a timeout, not a pass, even
# when it printed PASS before it hung.
timeout_case () {
  local description="$1"; shift
  checks=0
  passed=""
  status=0
  local output="${CI_LOG_DIR}/timeout_case.out"
  # Not $(...): run_check must update `status` in this shell, not a subshell.
  run_check slow_check 1 "$@" > "${output}" 2>&1
  cases=$((cases + 1))
  if [ "${status}" -eq 0 ] || ! grep -q "slow_check failed (timed out after 1s" "${output}"; then
    echo "FAIL: ${description}: expected an explicit timeout failure"
    failures=$((failures + 1))
  else
    echo "ok: ${description} (fail, named as a timeout)"
  fi
}
timeout_case "a check that hangs is an explicit timeout" bash -c 'sleep 5'
timeout_case "a check that prints PASS and then hangs is still a timeout" \
  bash -c 'printf "PASS: early\n"; sleep 5'

CURRENT_NAME=import
expect "the import pass keeps its exception even when it hits its limit" pass \
  bash -c 'exit 124'

echo
echo "${cases} case(s), ${failures} failure(s)"
if [ "${failures}" -ne 0 ]; then
  exit 1
fi
echo "PASS: run_check counts a green log with a script error in it as a failure."
