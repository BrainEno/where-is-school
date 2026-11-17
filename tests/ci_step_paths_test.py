#!/usr/bin/env python3
"""Boundary tests for ``tools/check_ci_step_paths.py`` (issue #217).

The check exists because a local composite action is read from the *working tree at the
moment the step runs*: a job that checks out an older commit and then runs
``./.github/actions/setup-godot`` fails with "Can't find 'action.yml'", which happened on a
real pull request. So it is tested both ways, with workflow files this test writes:

- a local action with no checkout before it passes, and so does one after a plain
  ``actions/checkout`` (which gives this run's own commit);
- ``actions/checkout`` with a ``ref:`` naming another commit (``base``, ``matrix.side``,
  ``inputs.base``) makes a later local action an error, and so does ``git checkout
  --detach`` or ``git reset --hard`` written in a ``run:`` block;
- moving the local step above the boundary clears the finding - that is the fix the
  workflow in this repository uses, and the only one available: a ``uses:`` step cannot
  take a ``working-directory``;
- a checkout in one job does not affect the next job's steps;
- ``ref:`` naming this run's own commits (``github.sha``,
  ``github.event.pull_request.head.sha``) is not a boundary, and neither is a ``ref:``
  reached through an ``env.`` variable;
- a ``run:`` step after a boundary is *not* reported: a "before" capture is supposed to run
  the older commit's scripts, so the check stays out of that decision;
- the command returns 1 on a finding, 1 when there is nothing to scan, and 0 on this
  repository's own workflows.

Run it with ``python3 tests/ci_step_paths_test.py`` (CI does). No network needed.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_ci_step_paths as paths  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0

SHA = "d23441a48e516b6c34aea4fa41551a30e30af803"  # actions/checkout v6.1.0
CHECKOUT = f"      - uses: actions/checkout@{SHA} # v6.1.0"
LOCAL = "      - uses: ./.github/actions/setup-godot"


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def workflow(steps: str, second_job: str = "") -> str:
    text = (
        "name: Test\n"
        "on: [push]\n"
        "jobs:\n"
        "  build:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n" + steps
    )
    if second_job:
        text += (
            "  other:\n"
            "    runs-on: ubuntu-latest\n"
            "    steps:\n" + second_job
        )
    return text


def problems(steps: str, second_job: str = "") -> list[str]:
    return paths.findings_in("w.yml", workflow(steps, second_job))


def expect_ok(name: str, steps: str, second_job: str = "") -> None:
    found = problems(steps, second_job)
    check(not found, f"{name}: must pass, got {found}")


def expect_finding(name: str, steps: str, needle: str) -> None:
    found = problems(steps)
    check(any(needle in p for p in found), f"{name}: expected a finding with {needle!r}, got {found}")


def run_main(argv: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = paths.main(argv)
    return code, out.getvalue()


def write_tree(root: Path, files: dict[str, str]) -> None:
    for rel, text in files.items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")


# --- cases -------------------------------------------------------------------------


def local_action_without_a_checkout() -> None:
    expect_ok("a local action with no checkout", LOCAL + "\n")
    expect_ok("a plain checkout is not a boundary",
              CHECKOUT + "\n" + LOCAL + "\n")
    expect_ok("the checkout after the local action",
              LOCAL + "\n" + CHECKOUT + "\n")


def checkouts_that_can_reach_another_commit() -> None:
    for ref, label in (
        ("${{ github.event.pull_request.base.sha }}", "the base commit"),
        ("${{ matrix.commit }}", "a matrix entry"),
        ("${{ inputs.base }}", "a dispatch input"),
        ("${{ env.BASE_SHA }}", "an env var"),
    ):
        steps = (
            f"{CHECKOUT}\n"
            "        with:\n"
            f"          ref: {ref}\n" + LOCAL + "\n")
        expect_finding(f"a checkout of {label}", steps, "move this step above")

    for command in ("git checkout --detach", "git switch --detach", "git reset --hard"):
        steps = (
            "      - name: Go back\n"
            "        shell: bash\n"
            "        run: |\n"
            f"          {command} \"${{{{ env.BASE_SHA }}}}\"\n"
            "          cp /tmp/x.gd tests/x.gd\n" + LOCAL + "\n")
        expect_finding(f"`{command}` in a script", steps, "move this step above")


def refs_that_name_this_run() -> None:
    for ref in ("${{ github.sha }}", "${{ github.event.pull_request.head.sha }}"):
        steps = (
            f"{CHECKOUT}\n"
            "        with:\n"
            f"          ref: {ref}\n" + LOCAL + "\n")
        expect_ok(f"a checkout of this run's own commit ({ref})", steps)
    # An `env.` indirection is resolved through the file's own definitions, one hop at a
    # time: `RELAY_COMMIT: ${{ github.sha }}` still names this run's commit...
    steps = (
        f"{CHECKOUT}\n"
        "        with:\n"
        "          ref: ${{ env.RELAY_COMMIT }}\n" + LOCAL + "\n")
    text = workflow(steps).replace(
        "    runs-on: ubuntu-latest\n",
        "    runs-on: ubuntu-latest\n    env:\n      RELAY_COMMIT: ${{ github.sha }}\n", 1)
    found = paths.findings_in("w.yml", text)
    check(not found, f"an env var defined as github.sha is not a boundary, got {found}")
    # ...while an env var defined nowhere this file can see is treated as another commit,
    # because being wrong that way reports a workflow that is fine and the other way hides
    # a job that will fail.
    expect_finding("an unresolvable env ref", steps, "move this step above")


def the_fix_clears_the_finding() -> None:
    # The order the workflow in this repository now uses: install the engine while the
    # tree is still this run's, then check out the base commit.
    steps = (
        LOCAL + "\n"
        f"{CHECKOUT}\n"
        "        with:\n"
        "          ref: ${{ github.event.pull_request.base.sha }}\n"
        "      - name: Go back\n"
        "        shell: bash\n"
        "        run: git checkout --detach \"$BASE_SHA\"\n")
    expect_ok("the engine installed before the before-side checkout", steps)
    # A `working-directory` on the *step* is not a fix: GitHub does not accept one on a
    # `uses:` step, and the local action is still resolved from the checkout that ran.
    steps = (
        f"{CHECKOUT}\n"
        "        with:\n"
        "          ref: ${{ github.event.pull_request.base.sha }}\n"
        "      - uses: ./.github/actions/setup-godot\n"
        "        with:\n"
        "          working-directory: ${{ github.workspace }}\n")
    expect_finding("a working-directory is not a `uses:` input", steps, "move this step above")


def boundaries_are_per_job() -> None:
    expect_ok(
        "a checkout in the first job does not reach the second",
        CHECKOUT + "\n",
        LOCAL + "\n")
    expect_ok(
        "the second job's checkout is its own boundary, and a plain one is not",
        CHECKOUT + "\n",
        CHECKOUT + "\n" + LOCAL + "\n")


def run_steps_are_not_judged() -> None:
    steps = (
        f"{CHECKOUT}\n"
        "        with:\n"
        "          ref: ${{ github.event.pull_request.base.sha }}\n"
        "      - shell: bash\n"
        "        run: |\n"
        "          git checkout --detach \"$BASE_SHA\"\n"
        "          python3 tools/verify_build.py --preset export_presets.cfg\n")
    expect_ok("a run: step after a boundary is the workflow's own business", steps)


def multi_line_run_blocks() -> None:
    """A `run: |` body is read to its end, so a checkout inside it is found."""
    steps = (
        "      - name: Go back\n"
        "        shell: bash\n"
        "        run: |\n"
        "          set -euo pipefail\n"
        "          if true; then\n"
        "            git switch --detach \"$BASE_SHA\"\n"
        "          fi\n"
        "          echo done\n" + LOCAL + "\n")
    expect_finding("a checkout inside a nested if", steps, "move this step above")
    # ...and a `run:` block does not swallow the next step.
    steps = (
        "      - name: Nothing\n"
        "        shell: bash\n"
        "        run: |\n"
        "          echo hello\n" + LOCAL + "\n")
    expect_ok("a run: block followed by a local action", steps)


def command_line() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        code, out = run_main(["--root", str(root)])
        check(code == 1 and "no workflows" in out,
              f"nothing to scan must fail, not pass: {code} {out!r}")

        write_tree(root, {".github/workflows/ok.yml": workflow(CHECKOUT + "\n" + LOCAL + "\n")})
        code, out = run_main(["--root", str(root)])
        check(code == 0 and "CI_STEP_PATHS_OK" in out, f"a clean tree must pass: {code} {out!r}")

        write_tree(root, {".github/workflows/bad.yml": workflow(
            CHECKOUT + "\n        with:\n          ref: ${{ matrix.commit }}\n" + LOCAL + "\n")})
        code, out = run_main(["--root", str(root), "--list"])
        check(code == 1, f"a finding must return 1, got {code}")
        check("CI_STEP_PATHS_FAILURE: .github/workflows/bad.yml:" in out,
              f"the failure must name the file and line: {out!r}")
        check("local ./.github/actions/setup-godot" in out,
              f"--list must show the local step: {out!r}")


def this_repository() -> None:
    code, out = run_main([])
    check(code == 0, f"the repository's own workflows must pass:\n{out}")
    steps = paths.steps_in(
        (paths.ROOT / ".github/workflows/location-art-capture.yml").read_text(encoding="utf-8"),
        ".github/workflows/location-art-capture.yml")
    capture = [s for s in steps if s.job == "capture"]
    installs = [i for i, s in enumerate(capture) if s.is_local]
    check(len(installs) == 1, f"the capture job installs the engine once, saw {len(installs)}")
    if installs:
        first_boundary = next(i for i, s in enumerate(capture) if s.rewrites_tree)
        check(installs[0] < first_boundary,
              "the engine must be installed before the 'before' leg checks out the base "
              "commit, which does not contain the local action")
    boundaries = [s for s in steps if s.rewrites_tree]
    check(len(boundaries) == 1 and "git checkout" in boundaries[0].run,
          f"the 'before' leg is the boundary this test is about: {boundaries}")


def main() -> int:
    local_action_without_a_checkout()
    checkouts_that_can_reach_another_commit()
    refs_that_name_this_run()
    the_fix_clears_the_finding()
    boundaries_are_per_job()
    run_steps_are_not_judged()
    multi_line_run_blocks()
    command_line()
    this_repository()

    if FAILURES:
        for failure in FAILURES:
            print("CI_STEP_PATHS_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("CI_STEP_PATHS_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
