#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'iOS Simulator requires macOS and full Xcode.' >&2
  exit 1
fi
# The Apple Command Line Tools may provide an older Python than export_mobile needs.
for python in "${WIS_PYTHON:-python3}" python3.13 python3.12 python3.11; do
  if "$python" -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null; then
    exec "$python" "$here/simulator.py" "$@"
  fi
done
echo 'Install Python 3.11+ from python.org or Homebrew (brew install python@3.12), then retry.' >&2
exit 1
