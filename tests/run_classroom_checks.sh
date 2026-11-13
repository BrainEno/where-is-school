#!/usr/bin/env bash
# Classroom acceptance using the repository's existing strict verdict helper.
# Import first: godot --headless --path . --import
# Usage: GODOT_BIN=godot bash tests/run_classroom_checks.sh [--with-render|--render-only]
# A real display is required for the optional pixel checks and viewport captures.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"
godot="${GODOT_BIN:-godot}"
export CI_LOG_DIR="${CLASSROOM_LOG_DIR:-build/classroom-evidence/checks}"
mkdir -p "${CI_LOG_DIR}"
source tools/ci_run_check.sh

render=0
headless=1
case "${1:-}" in
  --with-render) render=1 ;;
  --render-only) render=1; headless=0 ;;
  "") ;;
  *) echo "Usage: bash tests/run_classroom_checks.sh [--with-render|--render-only]" >&2; exit 2 ;;
esac

"${godot}" --version | tee "${CI_LOG_DIR}/ENGINE.txt"

if [ "${headless}" -eq 1 ]; then
  for test in \
    smoke camera_rig classroom_visual_slice navigation navigation_sync_stress \
    prop_placement imported_placement imported_assets \
    interaction_occlusion interaction_visibility_sweep interaction_outline_content \
    interaction_hover interaction_cue automatic_interaction pointer_target_switch \
    opening_flow opening_resume free_period subjective_isolation \
    location_transition companion_route companion_obstacle dialogue_content content_integrity
  do
    run_check "${test}" 540 "${godot}" --headless --path . \
      --script "res://tests/${test}_test.gd" || status=1
  done
fi

if [ "${render}" -eq 1 ]; then
  for method in forward_plus gl_compatibility; do
    driver=vulkan
    if [ "${method}" = gl_compatibility ]; then driver="${GODOT_GL_DRIVER:-opengl3}"; fi
    run_check "classroom_pixels_${method}" 240 "${godot}" --path . --audio-driver Dummy \
      --rendering-method "${method}" --rendering-driver "${driver}" \
      --script res://tests/classroom_wall_render_test.gd \
      -- "--output=${CI_LOG_DIR}/pixels-${method}" || status=1
    run_check "classroom_capture_${method}" 300 "${godot}" --path . --audio-driver Dummy \
      --resolution 1600x900 --rendering-method "${method}" --rendering-driver "${driver}" \
      --script res://tests/capture_classroom_art.gd \
      -- "--output=${CI_LOG_DIR}/capture-${method}" || status=1
  done
fi

# A PASS verdict does not hide engine warnings or errors. Retain the complete logs;
# some old negative fixtures intentionally produce them and require separate review.
{
  for log in "${CI_LOG_DIR}"/*.log; do
    errors=$(grep -c 'ERROR:' "${log}" || true)
    warnings=$(grep -c 'WARNING:' "${log}" || true)
    printf '%s: %s ERROR, %s WARNING\n' "$(basename "${log}")" "${errors}" "${warnings}"
  done
} | tee "${CI_LOG_DIR}/ENGINE_NOISE.txt"
run_check_summary
