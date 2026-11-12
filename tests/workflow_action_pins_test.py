#!/usr/bin/env python3
"""Boundary tests for ``tools/check_workflow_action_pins.py``.

A pin check that misses a tag is a green run over exactly the risk it exists to stop, and
one that flags a local action or a shell script mentioning ``uses:`` is a check people learn
to ignore. So it is tested both ways, with workflow files this test writes:

- a full lowercase 40-character SHA with a version comment passes, in every spelling YAML
  allows: ``- uses:``, ``uses:``, double and single quotes, a quoted key, an inline
  ``{ uses: ... }`` mapping, the value on the line after the key, CRLF line endings, and a
  job-level reusable workflow;
- local ``./`` actions and reusable workflows pass with no SHA and no comment;
- a ``uses:`` inside a ``run: |`` / ``run: >-`` script, in a ``- |`` item, or in a comment is
  not a reference at all and must not be reported;
- tags (``v4``, ``v2.4.3``), branches (``main``, ``releases/v6``), short SHAs (7 and 39
  characters), an uppercase SHA, a 41-character "SHA", a missing ``@ref``, a ``#`` glued to
  the ref, a docker tag instead of a digest, a block-scalar ``uses:``, a value continuing on
  the next line, a missing comment and a comment that is not a version are each rejected,
  and the message says which of those it is;
- the same action pinned to two SHAs, or one SHA under two version comments, in two
  workflows is reported as drift;
- composite actions under ``.github/actions/`` are scanned too, and ``.yaml`` is read like
  ``.yml``;
- the command returns 1 on any finding, 1 when there is nothing to scan, and 0 on the
  repository's own workflows, which also have to agree with ``release.yml``'s pins.

Run it with ``python3 tests/workflow_action_pins_test.py`` (CI does). It needs no network.
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import check_workflow_action_pins as pins  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0

SHA = "d23441a48e516b6c34aea4fa41551a30e30af803"  # actions/checkout v6.1.0
OTHER_SHA = "ea165f8d65b6e75b540449e92b4886f43607fa02"  # actions/upload-artifact v4.6.2


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def workflow(steps: str, extra: str = "") -> str:
    """A complete workflow with ``steps`` under one job (``steps`` already indented by 6)."""
    return (
        "name: Test\n"
        "on: [push]\n"
        "jobs:\n"
        "  build:\n"
        "    runs-on: ubuntu-latest\n"
        "    steps:\n" + steps + extra)


def problems_in(text: str, path: str = "w.yml") -> tuple[list[pins.Use], list[str]]:
    uses = pins.scan_text(text, path)
    found = [p for u in uses for p in pins.judge(u)]
    return uses, found


def expect_ok(name: str, steps: str, count: int = 1) -> None:
    uses, found = problems_in(workflow(steps))
    check(len(uses) == count, f"{name}: expected {count} uses, found {[u.value for u in uses]}")
    check(not found, f"{name}: must pass, got {found}")


def expect_rejected(name: str, steps: str, needle: str) -> None:
    uses, found = problems_in(workflow(steps))
    check(bool(uses), f"{name}: the reference was not seen at all")
    check(any(needle in p for p in found),
          f"{name}: expected a problem with {needle!r}, got {found}")


def write_tree(root: Path, files: dict[str, str]) -> None:
    for rel, text in files.items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text.encode("utf-8"))


def run_main(argv: list[str]) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = pins.main(argv)
    return code, out.getvalue()


# --- accepted -----------------------------------------------------------------------


def accepted_spellings() -> None:
    expect_ok("list item", f"      - uses: actions/checkout@{SHA} # v6.1.0\n")
    expect_ok("named step",
              f"      - name: Checkout\n        uses: actions/checkout@{SHA} # v6.1.0\n")
    expect_ok("double quotes", f'      - uses: "actions/checkout@{SHA}" # v6.1.0\n')
    expect_ok("single quotes", f"      - uses: 'actions/checkout@{SHA}'   #   v6.1.0\n")
    expect_ok("quoted key", f'      - "uses": actions/checkout@{SHA} # v6.1.0\n')
    expect_ok("flow mapping", f"      - {{ name: c, uses: actions/checkout@{SHA} }} # v6.1.0\n")
    expect_ok("value on the next line",
              f"      - name: Checkout\n        uses:\n          actions/checkout@{SHA} # v6.1.0\n")
    expect_ok("comment with free text after the version",
              f"      - uses: actions/checkout@{SHA} # v6.1.0 (same commit as v6)\n")
    expect_ok("action in a sub-directory of its repository",
              f"      - uses: github/codeql-action/init@{SHA} # v3.28.0\n")
    expect_ok("trailing whitespace", f"      - uses: actions/checkout@{SHA} # v6.1.0   \n")

    crlf = workflow(f"      - uses: actions/checkout@{SHA} # v6.1.0\n").replace("\n", "\r\n")
    uses, found = problems_in(crlf)
    check(len(uses) == 1 and not found, f"CRLF: must pass, got {[u.value for u in uses]} {found}")
    check(uses and uses[0].comment == "v6.1.0", "CRLF: the \\r must not end up in the comment")

    reusable = ("name: Call\non: [push]\njobs:\n  call:\n"
                f"    uses: octo-org/shared/.github/workflows/ci.yml@{SHA} # v1.0.0\n")
    uses, found = problems_in(reusable)
    check(len(uses) == 1 and not found, f"external reusable workflow pinned: got {found}")

    digest = "sha256:" + "a" * 64
    expect_ok("docker by digest", f"      - uses: docker://alpine@{digest} # 3.20.0\n")


def local_actions_allowed() -> None:
    expect_ok("local action, no SHA, no comment",
              "      - uses: ./.github/actions/evidence-check\n")
    expect_ok("local action, quoted", "      - uses: './.github/actions/evidence-check'\n")
    local_reusable = "name: Call\non: [push]\njobs:\n  call:\n    uses: ./.github/workflows/b.yml\n"
    uses, found = problems_in(local_reusable)
    check(len(uses) == 1 and uses[0].is_local and not found,
          f"local reusable workflow must pass, got {found}")


def not_references() -> None:
    script = (
        "      - name: Script\n"
        "        run: |\n"
        "          echo 'uses: actions/checkout@v6'\n"
        "          uses: evil/action@main\n"
        "\n"
        "            uses: deeper/still@v1\n"
        "      - name: Folded\n"
        "        run: >-\n"
        "          uses: also/not@v2\n"
        f"      - uses: actions/checkout@{SHA} # v6.1.0\n")
    uses, found = problems_in(workflow(script))
    check([u.value for u in uses] == [f"actions/checkout@{SHA}"],
          f"block scalars must be skipped, found {[u.value for u in uses]}")
    check(not found, f"block scalars: no problems expected, got {found}")

    items = ("      - name: Args\n        with:\n          args:\n            - |\n"
             "              uses: in/a-list-item@main\n"
             f"      - uses: actions/checkout@{SHA} # v6.1.0\n")
    uses, _ = problems_in(workflow(items))
    check(len(uses) == 1, f"`- |` item content must be skipped, found {[u.value for u in uses]}")

    comments = ("      # - uses: actions/checkout@v6\n"
                "      #   uses: anything@main\n"
                "  # workflow uses: the build job runs on every pull request\n"
                f"      - uses: actions/checkout@{SHA} # v6.1.0 uses: x@main\n")
    uses, found = problems_in(workflow(comments))
    check(len(uses) == 1 and not found,
          f"comments must not be references, found {[u.value for u in uses]} {found}")

    keys = ("      - name: uses is mentioned here\n"
            "        env:\n          USES: foo@main\n          uses_cache: bar@v1\n"
            f"        uses: actions/checkout@{SHA} # v6.1.0\n")
    uses, _ = problems_in(workflow(keys))
    check(len(uses) == 1, f"only the `uses` key counts, found {[u.value for u in uses]}")


# --- rejected -----------------------------------------------------------------------


def rejected_refs() -> None:
    expect_rejected("major tag", "      - uses: actions/checkout@v6 # v6\n", "tag `v6`")
    expect_rejected("full tag", "      - uses: chickensoft-games/setup-godot@v2.4.3\n",
                    "tag `v2.4.3`")
    expect_rejected("tag even with a comment",
                    "      - uses: actions/upload-artifact@v4 # v4.6.2\n",
                    "tag `v4`")
    expect_rejected("branch", "      - uses: actions/checkout@main # v6.1.0\n", "branch")
    expect_rejected("release branch", "      - uses: actions/checkout@releases/v6 # v6.1.0\n",
                    "branch")
    expect_rejected("short SHA (7)", "      - uses: actions/checkout@d23441a # v6.1.0\n",
                    "short SHA (7")
    expect_rejected("short SHA (39)", f"      - uses: actions/checkout@{SHA[:39]} # v6.1.0\n",
                    "short SHA (39")
    expect_rejected("uppercase SHA", f"      - uses: actions/checkout@{SHA.upper()} # v6.1.0\n",
                    "lowercase")
    expect_rejected("41 characters", f"      - uses: actions/checkout@{SHA}0 # v6.1.0\n",
                    "full 40-character")
    expect_rejected("no ref", "      - uses: actions/checkout\n", "no @ref")
    expect_rejected("hash glued to the ref", f"      - uses: actions/checkout@{SHA}#v6.1.0\n",
                    "full 40-character")
    expect_rejected("not owner/repo", f"      - uses: checkout@{SHA} # v6.1.0\n",
                    "neither `./local`")
    expect_rejected("docker tag", "      - uses: docker://alpine:3.20 # 3.20\n", "digest")
    expect_rejected("quoted tag", "      - uses: \"actions/checkout@v6\"\n", "tag `v6`")
    expect_rejected("flow mapping tag", "      - { uses: actions/checkout@v6 }\n", "tag `v6`")
    expect_rejected("tag on the next line", "      - uses:\n          actions/checkout@v6\n",
                    "tag `v6`")
    reusable = ("name: Call\non: [push]\njobs:\n  call:\n"
                "    uses: o/r/.github/workflows/c.yml@main\n")
    _, found = problems_in(reusable)
    check(any("branch" in p for p in found), f"reusable workflow on a branch: got {found}")


def rejected_comments_and_shapes() -> None:
    expect_rejected("missing comment", f"      - uses: actions/checkout@{SHA}\n",
                    "missing version comment")
    expect_rejected("comment that is not a version",
                    f"      - uses: actions/checkout@{SHA} # pinned\n",
                    "does not start with a version")
    expect_rejected("empty comment", f"      - uses: actions/checkout@{SHA} #\n",
                    "missing version comment")
    expect_rejected("block scalar uses", f"      - uses: >-\n          actions/checkout@{SHA}\n",
                    "block scalar")
    expect_rejected("plain scalar on two lines",
                    f"      - uses: actions/checkout@\n          {SHA} # v6.1.0\n",
                    "continues on the next line")
    expect_rejected("empty uses", "      - name: x\n        uses:\n      - name: y\n", "no value")


# --- across files and the command ---------------------------------------------------


def drift_across_files() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_tree(root, {
            ".github/workflows/a.yml": workflow(f"      - uses: actions/checkout@{SHA} # v6.1.0\n"),
            ".github/workflows/b.yaml": workflow(
                f"      - uses: actions/checkout@{OTHER_SHA} # v6.0.0\n"),
        })
        _, problems = pins.audit(root)
        check(any("actions/checkout is pinned more than one way" in p for p in problems),
              f"two SHAs for one action must be drift, got {problems}")
        check(any("b.yaml" in p for p in problems), "a .yaml workflow must be scanned too")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_tree(root, {
            ".github/workflows/a.yml": workflow(f"      - uses: actions/checkout@{SHA} # v6.1.0\n"),
            ".github/workflows/b.yml": workflow(f"      - uses: actions/checkout@{SHA} # v6.0.0\n"),
        })
        _, problems = pins.audit(root)
        check(any("pinned more than one way" in p for p in problems),
              f"one SHA under two version comments must be drift, got {problems}")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_tree(root, {
            ".github/workflows/a.yml": workflow(
                f"      - uses: github/codeql-action/init@{SHA} # v3.28.0\n"
                f"      - uses: github/codeql-action/analyze@{SHA} # v3.28.0\n"),
        })
        _, problems = pins.audit(root)
        check(not problems, f"sub-actions of one repository on one pin are not drift: {problems}")


def composite_actions_scanned() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_tree(root, {
            ".github/workflows/a.yml": workflow("      - uses: ./.github/actions/x\n"),
            ".github/actions/x/action.yml": (
                "name: x\nruns:\n  using: composite\n  steps:\n"
                "    - uses: actions/setup-python@v5\n"),
        })
        _, problems = pins.audit(root)
        check(any(".github/actions/x/action.yml:5" in p and "tag `v5`" in p for p in problems),
              f"a composite action's external uses must be checked, got {problems}")


def command_line() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        code, out = run_main(["--root", str(root)])
        check(code == 1 and "no workflow files" in out,
              f"nothing to scan must fail, not pass: {code} {out!r}")

        write_tree(root, {
            ".github/workflows/ok.yml": workflow(
                f"      - uses: actions/checkout@{SHA} # v6.1.0\n"
                "      - uses: ./.github/actions/local\n"),
        })
        code, out = run_main(["--root", str(root)])
        check(code == 0 and "WORKFLOW_PINS_OK: 1 external" in out and "1 local" in out,
              f"a clean tree must return 0 and count both kinds: {code} {out!r}")

        write_tree(root, {".github/workflows/bad.yml":
                          workflow("      - uses: actions/checkout@v6\n")})
        code, out = run_main(["--root", str(root), "--list"])
        check(code == 1, f"a tag must make the command return 1, got {code}")
        check("WORKFLOW_PINS_FAILURE: .github/workflows/bad.yml:7:" in out,
              f"the failure must name the file and line: {out!r}")
        check("local ./.github/actions/local" in out, f"--list must show local uses: {out!r}")


def this_repository() -> None:
    """The real workflows pass, and every external action agrees with release.yml's pin."""
    code, out = run_main([])
    check(code == 0, f"the repository's own workflows must pass:\n{out}")
    uses, _ = pins.audit(pins.ROOT)
    files = {u.path for u in uses}
    for name in ("godot-ci.yml", "playthrough-capture.yml", "bake-animation-retarget.yml",
                 "release.yml"):
        check(f".github/workflows/{name}" in files, f"{name} was not scanned")
    release = {u.repository: (u.ref, u.version) for u in uses
               if u.path.endswith("release.yml") and not u.is_local}
    for use in uses:
        if use.is_local:
            check(use.value.startswith("./.github/"), f"unexpected local reference {use.value}")
            continue
        check(release.get(use.repository) == (use.ref, use.version),
              f"{use.path}:{use.line} pins {use.repository} differently from release.yml")
    check(any(u.is_local for u in uses), "the local evidence-check action must be seen as local")


def main() -> int:
    accepted_spellings()
    local_actions_allowed()
    not_references()
    rejected_refs()
    rejected_comments_and_shapes()
    drift_across_files()
    composite_actions_scanned()
    command_line()
    this_repository()

    if FAILURES:
        for failure in FAILURES:
            print("WORKFLOW_PINS_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("WORKFLOW_PINS_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
