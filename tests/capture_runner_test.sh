#!/usr/bin/env bash
# Inject a fake engine and Xvfb to prove exit handling independently of graphics.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/godot" <<'MOCK'
#!/usr/bin/env bash
if [[ " $* " == *' --editor '* ]]; then
  echo 'import diagnostic'
  [ "${FAIL_IMPORT:-0}" = 0 ] || exit 23
  exit 0
fi
mkdir -p "$CAPTURE_OUTPUT_DIR"
printf 'frame' > "$CAPTURE_OUTPUT_DIR/01.png"
printf 'CAPTURE_STATUS=success\n' > "$CAPTURE_OUTPUT_DIR/PLAYTHROUGH.log"
[ "${FAIL_CAPTURE:-0}" = 0 ] || exit 42
MOCK
cat > "$tmp/xvfb-run" <<'MOCK'
#!/usr/bin/env bash
shift 2
exec "$@"
MOCK
chmod +x "$tmp/godot" "$tmp/xvfb-run"
run_case () {
  local label="$1" expected="$2" marker="$3"; shift 3
  mkdir -p "$tmp/$label"
  local result=0
  env CAPTURE_OUTPUT_DIR="$tmp/$label" GODOT_CMD="$tmp/godot" XVFB_CMD="$tmp/xvfb-run" "$@" \
    bash tools/run-playthrough-capture.sh > "$tmp/$label.out" 2>&1 || result=$?
  if [ "$expected" = success ]; then
    [ "$result" -eq 0 ] || { cat "$tmp/$label.out"; exit 1; }
  else
    [ "$result" -ne 0 ] || { echo "$label falsely succeeded"; exit 1; }
  fi
  grep -q "CAPTURE_STATUS=$marker" "$tmp/$label/status.txt"
  [ -s "$tmp/$label/import.log" ]
  if [ "$marker" = capture_failed ]; then
    [ -s "$tmp/$label/capture.log" ] || [ -f "$tmp/$label/01.png" ]
    [ -f "$tmp/$label/01.png" ]
  fi
  echo "PASS $label: exit=$result marker=$marker"
}
run_case normal success success env
run_case import_failure fail import_failed env FAIL_IMPORT=1
run_case capture_failure fail capture_failed env FAIL_CAPTURE=1
