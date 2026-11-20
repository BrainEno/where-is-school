#!/usr/bin/env bash
# Shared import preflight for Linux evidence jobs. The caller has installed Godot with
# setup-godot and is in the project root. Keep the cold and warm logs separate so a
# startup message about an asset still being imported is not mistaken for a warm error.
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo 'Usage: bash tools/ci_import_godot.sh LOG_DIR' >&2
  exit 2
fi
log_dir="$1"
mkdir -p -- "$log_dir"

run_pass() {
  local phase="$1" limit="$2" log="$3" code=0
  shift 3
  timeout --kill-after=10s "$limit" godot "$@" > "$log" 2>&1 || code=$?
  printf 'Godot %s: exit %d (%s)\n' "$phase" "$code" "${log##*/}"
  if (( code != 0 )); then
    tail -n 20 -- "$log" | sed 's/^/  /'
    echo 'IMPORT_RESULT=failure'
    printf '::error title=Godot import::%s exited %d (limit %s); see %s\n' "$phase" "$code" "$limit" "${log##*/}"
    exit "$code"
  fi
}

# Only --import waits for the first scan and asset queue to drain. Its log may mention
# the theme's font before it is available, but the process must finish successfully.
run_pass 'blocking import' 420s "$log_dir/import-1.log" --headless --path . --import
warm_log="$log_dir/import-2.log"
run_pass 'warm editor check' 120s "$warm_log" --headless --editor --path . --quit

# Godot can quit with status 0 even if a script failed to parse. Do not publish an
# import inventory or take evidence from a tree that failed this second check.
if grep -qE 'SCRIPT ERROR|Parse Error' "$warm_log"; then
  grep -m 20 -E 'SCRIPT ERROR|Parse Error' "$warm_log" | sed 's/^/  /'
  echo 'IMPORT_RESULT=failure'
  echo '::error title=Godot import::the warm editor check reported script errors; see import-2.log'
  exit 1
fi
echo 'IMPORT_RESULT=success'
