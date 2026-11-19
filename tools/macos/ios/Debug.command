#!/bin/bash
# Finder entry point; keep errors visible when double-clicked.
here=$(cd "$(dirname "$0")" && pwd) || exit 1
bash "$here/debug.sh" "$@"
status=$?
if [[ "$status" != 0 && -t 0 ]]; then read -r -p 'Press Return to close.' _; fi
exit "$status"
