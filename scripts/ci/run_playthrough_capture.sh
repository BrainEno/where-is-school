#!/usr/bin/env bash
# Capture only to a fresh evidence directory, never into tracked screenshots.
# The exit code and status.json both fail closed; the caller uploads the entire
# evidence directory even when this process fails.
set -uo pipefail

project_dir="${CAPTURE_PROJECT_DIR:-$(pwd)}"
evidence_dir="${CAPTURE_EVIDENCE_DIR:-$project_dir/ci-evidence}"
godot="${GODOT_BIN:-godot}"
xvfb="${XVFB_RUN_BIN:-xvfb-run}"
mkdir -p "$evidence_dir" || exit 2
# Do not mix a previous run's frames/logs into this one (or destroy them).
for name in frames import.log capture.log; do
  if [[ -e "$evidence_dir/$name" ]]; then
    echo "Evidence path already exists: $evidence_dir/$name" >&2
    exit 2
  fi
done
mkdir "$evidence_dir/frames" || exit 2

stage=import
import_status=not_run
capture_status=not_run
import_exit=-1
capture_exit=-1
result=failure
finish() {
  local code=$?
  printf '{"result":"%s","stage":"%s","import":"%s","import_exit":%s,"capture":"%s","capture_exit":%s}\n' \
    "$result" "$stage" "$import_status" "$import_exit" "$capture_status" "$capture_exit" \
    > "$evidence_dir/status.json.tmp"
  mv "$evidence_dir/status.json.tmp" "$evidence_dir/status.json"
  echo "PLAYTHROUGH_RESULT=${result^^} stage=$stage exit=$code"
}
trap finish EXIT
printf 'Capture not started.\n' > "$evidence_dir/capture.log"

if timeout "${IMPORT_TIMEOUT:-420}" "$godot" --headless --editor --path "$project_dir" --quit > "$evidence_dir/import.log" 2>&1; then
  import_exit=0
else
  import_exit=$?
fi
if (( import_exit != 0 )) || grep -Eq 'SCRIPT ERROR|Parse Error|^ERROR:' "$evidence_dir/import.log"; then
  import_status=failure
  detail=$(grep -E 'SCRIPT ERROR|Parse Error|^ERROR:' "$evidence_dir/import.log" | head -n 12 | tr '\n' '|' | cut -c1-2000 || true)
  detail=${detail//'%'/'%25'}
  echo "::error title=Import failed::exit=$import_exit ${detail:-See import.log and status.json in the artifact}"
  exit 1
fi
import_status=success
stage=capture
if CAPTURE_DIR="$evidence_dir/frames" timeout "${CAPTURE_TIMEOUT:-1200}" "$xvfb" -a --server-args="-screen 0 1600x900x24" \
  "$godot" --path "$project_dir" --resolution 1600x900 --rendering-driver opengl3 \
  --script res://tests/capture_playthrough.gd > "$evidence_dir/capture.log" 2>&1; then
  capture_exit=0
else
  capture_exit=$?
fi
if (( capture_exit != 0 )) || grep -Eq 'SCRIPT ERROR|Parse Error|^ERROR:' "$evidence_dir/capture.log"; then
  capture_status=failure
  detail=$(grep -E 'SCRIPT ERROR|Parse Error|^ERROR:|CAPTURE_RESULT|FAILURE:' "$evidence_dir/capture.log" | tail -n 12 | tr '\n' '|' | cut -c1-2000 || true)
  detail=${detail//'%'/'%25'}
  echo "::error title=Capture failed::exit=$capture_exit ${detail:-See capture.log and any partial frames in the artifact}"
  exit 1
fi

# A zero process exit is insufficient: reject incomplete, stale or silent runs.
required=(01_opening_line 04_prompt_schoolbag 05_inspection_text 06_chinese_world
          10_conversation_chinese 13_corridor 14_street 17_residential
          19_animal_conversation 20_estate_exit 21_playground 22_active_choices
          23_active_result 24_active_choices_chinese 20_end_card)
for frame in "${required[@]}"; do
  if [[ ! -s "$evidence_dir/frames/$frame.png" ]]; then
    stage=incomplete
    capture_status=failure
    echo "::error title=Capture incomplete::Missing frame $frame.png"
    exit 1
  fi
done
if [[ ! -s "$evidence_dir/frames/PLAYTHROUGH.log" || ! -s "$evidence_dir/frames/PLAYTHROUGH.md" ]] \
  || ! grep -q '^CAPTURE_RESULT: PASS$' "$evidence_dir/capture.log" \
  || grep -q 'FAILURE:' "$evidence_dir/frames/PLAYTHROUGH.log"; then
  stage=incomplete
  capture_status=failure
  echo "::error title=Capture incomplete::Missing success marker or index"
  exit 1
fi
capture_status=success
stage=complete
result=success
