#!/usr/bin/env bash
# tests/run_classroom_checks.sh --render-only, driven end to end by a fake Godot.
#
# The render gate is two layers: run_check judges each Godot script by its exit code and
# log, and tools/classroom_render_evidence.py judges the evidence the scripts leave. This
# file swaps the engine for a stand-in that can pass, fail, hang, throw a script error or
# lie about its renderer, per rendering method, and requires the combined verdict to be
# red whenever either renderer is wrong - and green only when both are right.
#
# The stand-in writes the same files the real scripts do (synthetic frames from
# tests/classroom_render_evidence_test.py) into a temporary directory. No engine, display
# or repository asset is touched.
#
# Usage: bash tests/run_classroom_checks_test.sh

set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fake="${work}/godot"
cat > "${fake}" <<'PY'
#!/usr/bin/env python3
"""A stand-in for `godot` with the command lines tests/run_classroom_checks.sh uses.
FAKE_GODOT_<METHOD> picks the behaviour: pass, fail, hang, script_error, or lie (prints
PASS while recording the other renderer, as a run after Godot's Vulkan fallback would if
the script did not check)."""
import os, sys, time
from pathlib import Path
sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "tests"))
import classroom_render_evidence_test as fixture

args = sys.argv[1:]
if args == ["--version"]:
    print(fixture.ENGINE)
    sys.exit(0)
def value(flag):
    return args[args.index(flag) + 1] if flag in args else ""
method = value("--rendering-method")
script = value("--script")
user = args[args.index("--") + 1:] if "--" in args else []
out = next(a.split("=", 1)[1] for a in user if a.startswith("--output="))
mode = os.environ.get("FAKE_GODOT_" + method.upper(), "pass")
if mode == "hang":
    time.sleep(60)
if mode == "fail":
    print("ERROR: TEST FAILURE: The real fader wall differs from 18% opacity control by 0.26667")
    print("FAIL: 1 problem(s) found.")
    sys.exit(1)
recorded = method
if mode == "lie":
    recorded = "gl_compatibility" if method == "forward_plus" else "forward_plus"
driver = fixture.evidence.EXPECTED_DRIVERS[recorded]
staging = Path(out).parent / ("staging-" + Path(out).name)
fixture.build(staging, recorded, driver)
kind = "pixels" if script.endswith("classroom_wall_render_test.gd") else "capture"
Path(out).parent.mkdir(parents=True, exist_ok=True)
(staging / ("%s-%s" % (kind, recorded))).rename(out)
log = (staging / ("classroom_%s_%s.log" % (kind, recorded))).read_text()
import shutil; shutil.rmtree(staging)
if mode == "script_error":
    print("SCRIPT ERROR: Invalid access to property or key 'transparency' on a base object of type 'Nil'.")
sys.stdout.write(log)
sys.exit(0)
PY
chmod +x "${fake}"
export REPO_ROOT="${root}"

failures=0
cases=0

# `scenario <description> <want-runner: pass|fail> <want-gate: pass|fail> [VAR=value...]`
scenario () {
  local description="$1" want_runner="$2" want_gate="$3"; shift 3
  local logs="${work}/case-${cases}"
  cases=$((cases + 1))
  env "$@" GODOT_BIN="${fake}" CLASSROOM_LOG_DIR="${logs}" \
    CLASSROOM_PIXEL_TIMEOUT=3 CLASSROOM_CAPTURE_TIMEOUT=3 \
    bash "${root}/tests/run_classroom_checks.sh" --render-only > "${work}/runner.out" 2>&1
  local code=$?
  local runner=pass gate=pass verdicts=()
  [ "${code}" -ne 0 ] && runner=fail
  local method
  for method in forward_plus gl_compatibility; do
    # The workflow verifies each renderer's folder in its own job; mirror that with a copy
    # per renderer so the two VERDICT.txt files cannot overwrite each other.
    local copy="${logs}-${method}"
    mkdir -p "${copy}"
    cp -r "${logs}/." "${copy}/" 2>/dev/null || true
    (cd "${root}" && python3 tools/classroom_render_evidence.py verify --dir "${copy}" \
      --method "${method}" > /dev/null 2>&1)
    verdicts+=("${copy}/VERDICT.txt")
  done
  python3 "${root}/tools/classroom_render_evidence.py" summarize "${verdicts[@]}" > "${work}/gate.out" 2>&1 \
    || gate=fail
  if [ "${runner}" != "${want_runner}" ] || [ "${gate}" != "${want_gate}" ]; then
    echo "FAIL: ${description}: runner ${runner} (wanted ${want_runner}), gate ${gate} (wanted ${want_gate})"
    sed 's/^/    /' "${work}/runner.out" | tail -n 20
    sed 's/^/    /' "${work}/gate.out"
    failures=$((failures + 1))
    return
  fi
  echo "ok: ${description} (runner ${runner}, gate ${gate})"
}

scenario "both renderers right is green" pass pass
scenario "a failing Forward+ is red" fail fail FAKE_GODOT_FORWARD_PLUS=fail
scenario "a failing Compatibility is red" fail fail FAKE_GODOT_GL_COMPATIBILITY=fail
scenario "a hung Forward+ is red" fail fail FAKE_GODOT_FORWARD_PLUS=hang
scenario "a script error behind a PASS is red" fail fail FAKE_GODOT_GL_COMPATIBILITY=script_error
# run_check alone cannot see this one: the script printed PASS and exited 0. The evidence
# verifier has to.
scenario "a Forward+ run that recorded another renderer is red" pass fail FAKE_GODOT_FORWARD_PLUS=lie
scenario "an unknown renderer name is red" fail fail CLASSROOM_RENDER_METHODS=vulkan_plus
scenario "an empty renderer list is red" fail fail CLASSROOM_RENDER_METHODS=" "

# The hang must be named as a timeout in the runner's own output.
env FAKE_GODOT_FORWARD_PLUS=hang GODOT_BIN="${fake}" CLASSROOM_LOG_DIR="${work}/hang" \
  CLASSROOM_PIXEL_TIMEOUT=2 CLASSROOM_CAPTURE_TIMEOUT=2 CLASSROOM_RENDER_METHODS=forward_plus \
  bash "${root}/tests/run_classroom_checks.sh" --render-only > "${work}/hang.out" 2>&1
cases=$((cases + 1))
if grep -q "classroom_pixels_forward_plus failed (timed out after 2s" "${work}/hang.out"; then
  echo "ok: the hang is reported as a timeout"
else
  echo "FAIL: the hang is not reported as a timeout"
  tail -n 20 "${work}/hang.out"
  failures=$((failures + 1))
fi

echo
echo "${cases} case(s), ${failures} failure(s)"
if [ "${failures}" -ne 0 ]; then
  exit 1
fi
echo "PASS: one wrong, hung, erroring or mislabelled renderer turns the classroom render gate red."
