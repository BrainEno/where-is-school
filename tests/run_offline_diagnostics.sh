#!/usr/bin/env bash
# Run from the project root, after importing it. On Linux, both launches intentionally
# share the same throwaway XDG user data. This never reads or removes a player's saves.
set -uo pipefail
source tools/ci_run_check.sh
sandbox=$(mktemp -d) || exit 1
trap 'rm -rf -- "$sandbox"' EXIT
use_profile () {
  export DIAGNOSTICS_TEST_HOME="$sandbox/$1"
  export XDG_DATA_HOME="$DIAGNOSTICS_TEST_HOME/data"
  export XDG_CONFIG_HOME="$DIAGNOSTICS_TEST_HOME/config"
  export XDG_CACHE_HOME="$DIAGNOSTICS_TEST_HOME/cache"
  mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" || exit 1
}
use_profile unit
run_check offline_diagnostics 60 godot --headless --path . --script res://tests/offline_diagnostics_test.gd || status=1
# Start the real game scenes twice. Xvfb can also be used for a desktop-rendered run of
# these assertions; the headless runner tests input/exports, not drawing or the OS shell.
use_profile play
run_check offline_diagnostics_collect 70 godot --headless --path . --script res://tests/offline_diagnostics_restart_test.gd -- collect || status=1
run_check offline_diagnostics_export 70 godot --headless --path . --script res://tests/offline_diagnostics_restart_test.gd -- export || status=1
run_check_summary
