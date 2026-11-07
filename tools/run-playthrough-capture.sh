#!/usr/bin/env bash
# Called by the read-only PR job. Exit status and a strict marker BOTH matter.
# Logs and partial frames stay in the artifact directory even when a step fails.
set -uo pipefail
output="${CAPTURE_OUTPUT_DIR:?set CAPTURE_OUTPUT_DIR to an empty artifact directory}"
mkdir -p "$output"
if [ -n "$(ls -A "$output")" ]; then
  echo "Capture output directory must be empty: $output" >&2
  exit 1
fi
printf 'CAPTURE_STATUS=importing\n' > "$output/status.txt"
"${GODOT_CMD:-godot}" --headless --editor --path . --quit > "$output/import.log" 2>&1
code=$?
printf 'import_exit=%d\n' "$code" >> "$output/status.txt"
if [ "$code" -ne 0 ] || grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$output/import.log"; then
  printf 'CAPTURE_STATUS=import_failed\n' >> "$output/status.txt"
  tail -n 60 "$output/import.log"
  exit 1
fi
# timeout prevents a stalled window from receiving a false success on job timeout.
timeout 900 "${XVFB_CMD:-xvfb-run}" -a --server-args="-screen 0 1600x900x24" \
  "${GODOT_CMD:-godot}" --path . --resolution 1600x900 --rendering-driver opengl3 \
  --script res://tests/capture_playthrough.gd > "$output/capture.log" 2>&1
code=$?
printf 'capture_exit=%d\n' "$code" >> "$output/status.txt"
if [ "$code" -ne 0 ] || ! grep -q 'CAPTURE_STATUS=success' "$output/PLAYTHROUGH.log" || \
   grep -Eq 'FAILURE:|CAPTURE_STATUS=failure' "$output/PLAYTHROUGH.log" || \
   grep -Eq 'SCRIPT ERROR|Parse Error|ERROR:' "$output/capture.log" || \
   ! compgen -G "$output/*.png" > /dev/null; then
  printf 'CAPTURE_STATUS=capture_failed\n' >> "$output/status.txt"
  tail -n 70 "$output/capture.log"
  exit 1
fi
printf 'CAPTURE_STATUS=success\n' >> "$output/status.txt"
echo "Capture succeeded; $(find "$output" -maxdepth 1 -name '*.png' | wc -l) frames in $output"
