#!/usr/bin/env python3
"""Check that every local step path is in the workflow's own tree (issue #217).

A composite action is read from the **working tree at the moment the step runs**, not from
the commit the workflow file belongs to. A job that checks out an older commit before its
engine install - the "before" side of an evidence capture - therefore deletes
``.github/actions/setup-godot`` out from under the step that is about to run it, and the
failure reads

    Can't find 'action.yml' ... under '.../.github/actions/setup-godot'

which is a wiring mistake, not an engine problem. The same is true of ``run:`` scripts that
call a tracked tool by relative path: after a checkout of another commit, the file may not
be there, or may be an older version than the workflow expects.

This check finds those cases statically, so a "before" job has to be written so that its
local steps run from a directory that holds them:

- for every job, its steps in order (the boundary is per job: a checkout in one job has
  nothing to do with the next one);
- a step is a *boundary* when it can replace the tree the workflow came from:

  * a ``run:`` script running ``git checkout``, ``git switch``, ``git reset --hard``,
    ``git restore`` or ``git clean -fdx``;
  * ``actions/checkout`` with a ``ref:`` that can name another commit - an expression
    mentioning ``base``, ``matrix`` or ``inputs.``. A ``ref:`` naming this run's own commit
    (``github.sha``, ``github.event.pull_request.head.sha``, an ``env.`` variable built from
    those) checks out the very tree the workflow file came from, so a local action there is
    still present and is not reported;

- a local ``uses: ./...`` after a boundary is an error: nothing guarantees the action is
  still in the tree. The fix is to **move the step before the boundary** - a `uses:` step
  has no ``working-directory`` input (GitHub only accepts one on ``run:`` steps), and
  ``actions/checkout`` always works on the job's own working tree, so there is no way to
  read the action from somewhere else. Installing the engine before either branch of a
  matrix checks out anything also keeps the engine identical on both sides, which is what
  makes a before/after comparison mean something.

``run:`` steps are deliberately not checked: a "before" capture is *supposed* to run the
older commit's scripts against the older commit's tree, and a check that called that a
mistake would be wrong about the workflow's intent.

It is deliberately about *local* paths only. External actions are pinned by SHA and are
downloaded by the runner, so a checkout does not touch them. ``actions/checkout`` itself is
exempt: it is what performs the checkout in the first place, and the ones that pin a ``ref``
are exactly what the check has to see.

This is the failure it was written for, seen on a real pull request:

    Can't find 'action.yml', 'action.yaml' or 'Dockerfile' under
    '.../.github/actions/setup-godot'. Did you forget to run actions/checkout
    before running your local action?

Usage:

    python3 tools/check_ci_step_paths.py           # CI: fail on any finding
    python3 tools/check_ci_step_paths.py --list    # every local step path and its boundary state

Standard library only: a line-oriented YAML reader for the subset the workflows use, the
same approach as ``tools/check_workflow_action_pins.py`` and for the same reason - a
dependency-free check runs before anything is installed.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A step begins at an indented `- ` whose content is a key.
STEP_START = re.compile(r"^(?P<indent>[ ]*)- (?P<rest>\S.*)$")
# `key: value` with the value possibly empty.
KEY = re.compile(r"""(?P<q>["']?)(?P<key>[A-Za-z0-9_./-]+)(?P=q)[ \t]*:[ \t]*(?P<value>.*)$""")
USES = re.compile(r"""^(?P<q>["']?)uses(?P=q)[ \t]*:[ \t]*(?P<value>.+)$""")
RUN = re.compile(r"""^(?P<q>["']?)run(?P=q)[ \t]*:[ \t]*(?P<value>.*)$""")
# Commands that rewrite the working tree in place.
REWRITES = (
    re.compile(r"\bgit\s+checkout\b"),
    re.compile(r"\bgit\s+switch\b"),
    re.compile(r"\bgit\s+reset\s+--hard\b"),
    re.compile(r"\bgit\s+restore\b"),
    re.compile(r"\bgit\s+clean\s+-[a-zA-Z]*[fdx]"),
)
# A checkout ref that can name a commit other than the one this workflow came from.
OTHER_COMMIT_REF = re.compile(r"(?i)(?:\bbase\b|\bmatrix\.|\binputs\.)")
# The run's own commit, reached directly or through an `env.` variable this file defines.
THIS_RUN_REF = re.compile(r"(?i)\bgithub\.(?:sha|event\.pull_request\.(?:head|merge_commit_sha))\b")
ENV_REF = re.compile(r"env\.([A-Za-z0-9_]+)")
ENV_DEF = re.compile(r"^[ \t]+([A-Z][A-Z0-9_]*):[ \t]*(\S.*)$", re.MULTILINE)


@dataclass
class Step:
    """One step of one job, with what it does to the working tree."""

    path: str
    line: int
    job: str
    name: str
    uses: str = ""
    run: str = ""
    # `actions/checkout` with a `ref:` input: a checkout of something other than this tree.
    checkout_ref: str = ""
    # Every `NAME: value` the workflow defines at any level, for resolving `env.NAME`.
    env: dict[str, str] = field(default_factory=dict)

    @property
    def is_local(self) -> bool:
        return self.uses.startswith("./")

    @property
    def rewrites_tree(self) -> bool:
        if self.uses.startswith("actions/checkout"):
            # A checkout with no `ref` gives the commit the run is for - the tree the
            # workflow file came from - so it is not a boundary. A `ref` naming another
            # commit (a base SHA, a matrix entry, a dispatch input) is.
            return checkout_can_leave_this_tree(self.checkout_ref, self.env)
        return any(pattern.search(self.run) for pattern in REWRITES)


def checkout_can_leave_this_tree(ref: str, env: dict[str, str]) -> bool:
    """Whether a ``ref:`` can check out a commit other than the workflow's own.

    The question is asked conservatively: an expression this check cannot resolve to the
    run's own commit is treated as another commit, because being wrong that way reports a
    workflow that is fine, while being wrong the other way hides a job that will fail.
    """
    if not ref:
        return False
    resolved = ref
    for _ in range(4):  # `env.A: ${{ env.B }}` chains, bounded
        expanded = ENV_REF.sub(lambda m: env.get(m.group(1), m.group(0)), resolved)
        if expanded == resolved:
            break
        resolved = expanded
    if OTHER_COMMIT_REF.search(resolved):
        return True
    if ENV_REF.search(resolved):  # defined nowhere this file can see
        return True
    # A ref with no `github.` expression at all is a literal SHA or a branch name, which is
    # not the commit the workflow came from.
    return not THIS_RUN_REF.search(resolved)


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def _strip_comment(text: str) -> str:
    quote = ""
    for i, ch in enumerate(text):
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "\"'":
            quote = ch
        elif ch == "#" and (i == 0 or text[i - 1] in " \t"):
            return text[:i].rstrip()
    return text.rstrip()


def steps_in(text: str, rel: str) -> list[Step]:
    """Every step in every job of one workflow file, in file order."""
    lines = text.replace("\r\n", "\n").split("\n")
    # `env.NAME` can be defined at workflow, job or step level; for the question this check
    # asks, where it is defined does not matter, only what it is.
    env = {name: _unquote(value) for name, value in ENV_DEF.findall(text)}
    steps: list[Step] = []
    job = ""
    in_job = False
    step: Step | None = None
    step_indent = 0
    run_indent: int | None = None
    block_indent: int | None = None  # inside a `run: |` scalar
    pending_ref = False  # the line after `ref:` in a checkout step
    job_indent = 0

    for number, raw in enumerate(lines, 1):
        stripped = raw.strip()
        indent = len(raw) - len(raw.lstrip(" "))

        if block_indent is not None:
            if not stripped:
                continue
            if indent > block_indent:
                if step is not None:
                    step.run += stripped + "\n"
                continue
            block_indent = None

        if not stripped or stripped.startswith("#"):
            continue

        # A job key: two-space indentation under `jobs:`, a name ending in `:`, no value.
        match = re.match(r"^ {2}([A-Za-z0-9_-]+):\s*$", raw)
        if match and not raw.startswith("   "):
            job = match.group(1)
            in_job = True
            job_indent = 2
            step = None
            continue
        if not in_job:
            continue

        start = STEP_START.match(raw)
        if start and indent >= job_indent + 2 and (step is None or indent <= step_indent):
            step_indent = indent
            body = start.group("rest")
            key = KEY.match(body)
            name = ""
            uses = ""
            if key and key.group("key") == "name":
                name = _unquote(key.group("value"))
            uses_match = USES.match(body)
            if uses_match:
                uses = _unquote(uses_match.group("value"))
            step = Step(path=rel, line=number, job=job, name=name or uses or body[:40],
                        uses=uses, env=env)
            steps.append(step)
            run_indent = None
            pending_ref = False
            continue
        if step is None:
            continue

        body = _strip_comment(stripped)
        if pending_ref:
            pending_ref = False
            if indent > run_indent if run_indent is not None else True:
                step.checkout_ref = _unquote(body)
                continue
        uses_match = USES.match(body)
        if uses_match and not step.uses:
            step.uses = _unquote(uses_match.group("value"))
            continue
        if re.match(r"^ref:\s*\S", body):
            step.checkout_ref = _unquote(body.split(":", 1)[1])
            continue
        if re.match(r"^ref:\s*$", body):
            pending_ref = True
            run_indent = indent
            continue
        run_match = RUN.match(body)
        if run_match:
            run_indent = indent
            value = run_match.group("value").strip()
            if value and value[0] in "|>":
                block_indent = indent
                step.run += "\n"
            else:
                step.run += value + "\n"
            continue
        if run_indent is not None and indent > run_indent:
            step.run += body + "\n"
    return steps


def findings_in(rel: str, text: str) -> list[str]:
    """Problems with one workflow: local steps that a tree rewrite leaves behind."""
    problems: list[str] = []
    boundary: Step | None = None
    job = ""
    for step in steps_in(text, rel):
        if step.job != job:
            # A checkout in one job says nothing about the next job's working tree.
            job = step.job
            boundary = None
        if step.rewrites_tree:
            boundary = step
            continue
        if boundary is None or not step.is_local:
            continue
        problems.append(
            f"{rel}:{step.line}: `uses: {step.uses}` runs after "
            f"{boundary.path}:{boundary.line} (`{boundary.name}`), which can replace the "
            "working tree, and a local action is read from that tree; move this step above "
            f"{boundary.path}:{boundary.line} (issue #217)")
    return problems


def workflow_files(root: Path) -> list[Path]:
    directory = root / ".github" / "workflows"
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.iterdir() if p.suffix in (".yml", ".yaml"))


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=Path, default=root)
    parser.add_argument("--list", action="store_true",
                        help="print every step that names a local path, with its boundary")
    args = parser.parse_args(argv)

    files = workflow_files(args.root)
    if not files:
        print(f"CI_STEP_PATHS_FAILURE: no workflows under {args.root}/.github/workflows")
        return 1
    problems: list[str] = []
    for path in files:
        rel = path.relative_to(args.root).as_posix()
        text = path.read_text(encoding="utf-8")
        problems += findings_in(rel, text)
        if args.list:
            boundary = None
            job = ""
            for step in steps_in(text, rel):
                if step.job != job:
                    job = step.job
                    boundary = None
                if step.rewrites_tree:
                    boundary = step
                kind = "local" if step.is_local else ("checkout" if step.uses else "run")
                print(f"{rel}:{step.line}: {step.job}: {kind} {step.uses or step.name}"
                      + (f" [after {boundary.path}:{boundary.line}]"
                         if boundary and not step.rewrites_tree else ""))
    if problems:
        for problem in problems:
            print("CI_STEP_PATHS_FAILURE: " + problem)
        print(f"{len(problems)} problem(s) in {len(files)} workflow(s).")
        return 1
    print(f"CI_STEP_PATHS_OK: {len(files)} workflow(s); every local action runs before the "
          "step that can replace the tree it is read from.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
