#!/usr/bin/env bash
# The verdict for one headless Godot check, in one place.
#
# This used to live inline in `godot-ci.yml`, where it decided a check had passed from the
# process exit code alone. A GDScript runtime error does not always change that code: an
# uncaught error inside a coroutine can leave the script's own verdict line in the log and
# still let the engine exit 0, and the harness's `quit(0)` path is reached by any test whose
# assertions ran before the error. The result was a green check over a log with
# "SCRIPT ERROR: ... previously freed instance" in it - exactly the errors this round is
# about, invisible to CI.
#
# So a check passes only when the log agrees with the exit code:
#
#   - non-zero exit                                    -> failure
#   - "Parse Error" in the log                         -> failure
#   - "SCRIPT ERROR" in the log                        -> failure
#   - "TEST FAILURE" / "FAIL:" in the log              -> failure
#   - no "PASS:" in the log (unless the check is one
#     of the compile-only ones below)                  -> failure
#
# Two checks are exceptions, and both are named here rather than inferred:
#
#   `import`        the first import pass loads the project theme before the font it points
#                   at has been imported, so it reports errors that are *caused* by the
#                   import being the thing that is running. Its verdict is the import audit
#                   that runs right after it, which checks every committed `.import` sidecar
#                   has its produced file. Only the error scan is skipped, and only here.
#   `capture_script` `--check-only` compiles a script and prints nothing on success: there
#                   is no verdict line to find. Its errors are still scanned.
#
# Sourcing this file defines `run_check`; see tests/run_check_test.sh for the behaviour it
# is expected to have.

# Counters shared with the caller.
checks=0
passed=""
status=0

run_check () {
  local name="$1"; shift
  local limit="$1"; shift
  local log_path="${CI_LOG_DIR:-ci-logs}/${name}.log"
  mkdir -p "$(dirname "${log_path}")"
  echo "=== ${name}: $*"
  timeout "${limit}" "$@" > "${log_path}" 2>&1
  local code=$?
  tail -n 30 "${log_path}"
  echo "--- exit ${code}"

  local need_pass=1
  local scan_errors=1
  local check_exit=1
  case "${name}" in
    import|capture_script) need_pass=0 ;;
  esac
  case "${name}" in
    # The import pass is the one command whose exit code is not a verdict: it loads the
    # project theme before the font it points at has been imported, so it fails on the
    # first pass by construction. The audit that runs straight after it is the verdict.
    import) scan_errors=0; check_exit=0 ;;
  esac

  # The verdict itself, one reason at a time, most specific first. The log is the second
  # witness: a run that exits 0 with a script error in it is not a pass.
  local failure=""
  if [ "${check_exit}" -eq 1 ] && [ "${code}" -ne 0 ]; then
    failure="exit ${code}"
  elif [ "${scan_errors}" -eq 1 ] && grep -qE "^Parse Error|Parse Error at" "${log_path}"; then
    failure="a Parse Error was reported"
  elif [ "${scan_errors}" -eq 1 ] && grep -qE "SCRIPT ERROR" "${log_path}"; then
    failure="an unhandled GDScript SCRIPT ERROR was reported"
  elif grep -qE "TEST FAILURE|FAIL:" "${log_path}"; then
    failure="the test reported a failure"
  elif [ "${need_pass}" -eq 1 ] && ! grep -qE "^PASS:" "${log_path}"; then
    failure="the test printed no PASS verdict"
  fi

  local summary
  # Prefer the test's own verdict lines. Engine ERROR noise (a freed-node warning repeated
  # every frame) can be hundreds of lines long and would otherwise push the real failure out
  # of the check annotation. `SCRIPT ERROR` belongs in the summary: an uncaught runtime error
  # kills the test's coroutine without printing a verdict, and the run then looks like a
  # silent timeout. Without this line the only visible symptom is the watchdog.
  summary=$(grep -E "TEST FAILURE|TEST WATCHDOG|FAIL:|SCRIPT ERROR|Parse Error|PASS:" \
    "${log_path}" | head -n 20 | tr '\n' '|' | cut -c1-4000)
  if [ -z "${summary}" ]; then
    summary=$(grep -E "SCRIPT ERROR|ERROR:" "${log_path}" \
      | head -n 12 | tr '\n' '|' | cut -c1-4000)
  fi
  grep -E "TEST FAILURE|TEST WATCHDOG|FAIL:" "${log_path}" | head -n 20 || true
  # A test that prints `::notice …` is describing what it measured. The engine's output goes
  # to a file above, so the runner never sees those lines; re-emit them here, which is how
  # the per-location and per-corpus numbers become readable.
  grep -E "^::(notice|warning|error) " "${log_path}" | head -n 12 || true

  if [ -z "${failure}" ]; then
    # One notice per *step*, not one per test: a runner keeps only the first handful of
    # annotations from a step, and forty green notices push the one red one out of the
    # report. Passed checks are counted and announced by the caller.
    passed="${passed}${name} "
  else
    echo "::error title=${name} failed (${failure})::${summary:-no summary captured}"
    echo "${summary}"
    status=1
  fi
  checks=$((checks + 1))
  return "${code}"
}

# Reports the totals and exits non-zero if anything failed. Called at the end of the step.
run_check_summary () {
  echo "overall status: ${status}"
  echo "checks run: ${checks}"
  printf 'passed: %s\n' "${passed}"
  echo "::notice title=headless checks::${checks} check(s), status ${status}; passed: ${passed}"
  exit "${status}"
}
