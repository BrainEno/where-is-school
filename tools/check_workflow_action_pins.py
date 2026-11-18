#!/usr/bin/env python3
"""Keep every external GitHub Action pinned to a full commit SHA.

Issue #116 (part of #67). A tag such as ``actions/checkout@v6`` is a pointer the upstream
repository can move at any time, and a branch moves on every push. What CI executes is then
decided by somebody else, on a day nobody here chose. A 40-character commit SHA cannot be
moved: the same reference names the same code forever. `release.yml` already pinned its
actions that way; this tool makes it the rule for every workflow and stops a later edit from
quietly going back to a tag.

The rule, for every ``uses:`` in ``.github/workflows/*.yml|*.yaml`` and in the repository's
own composite actions (``.github/actions/**/action.yml|action.yaml``, which can call external
actions too):

- ``./path`` is a local action or reusable workflow. It is code from this commit, so it is
  allowed as it is and needs no SHA.
- ``owner/repo[/path]@<ref>`` must use a full, lowercase, 40-character hexadecimal commit SHA,
  followed on the same line by a comment naming the upstream version, e.g.
  ``uses: actions/checkout@<sha> # v6.1.0``. The comment is what a human (and Dependabot)
  reads; the SHA is what runs.
- ``docker://image`` must be pinned by digest (``@sha256:<64 hex>``) with the same comment.
- one action repository, one pin: if two places use ``owner/repo`` with different SHAs or
  different version comments, that is drift and it fails.

**And one engine version, written once (issue #217).** The project pins one Godot version in
``.godot-version``, which ``./.github/actions/setup-godot`` reads. A workflow that installs
the engine any other way - ``chickensoft-games/setup-godot`` directly, or a ``version:``
input that is a literal instead of the composite action's output - has its own copy of that
number, and an upgrade that misses it makes evidence from a different engine than the
release. So a ``version:`` key inside a step that uses ``setup-godot`` must be absent or an
expression (``${{ ... }}``); a literal fails, and so does a ``setup-godot`` step that is not
the local action.

Rejected references are classified so the message says what is wrong: a tag (``v4``,
``v2.4.3``), a short SHA (7-39 hex characters), a branch or other movable name (``main``,
``releases/v6``), an uppercase SHA, a missing ``@ref``, a missing or non-version comment.

The reader is a small line-oriented YAML scanner, not a string search, because the cases a
string search gets wrong are all in this repository already: a ``uses:`` inside a ``run: |``
script, a ``# ... uses: ...`` comment, quoted values, ``- uses:`` list items, a value on the
line after the key, and inline ``{ uses: ... }`` flow mappings. Block scalars (``|`` and
``>``) are skipped by indentation exactly as YAML defines them. A ``uses:`` written as a
block scalar or as a multi-line plain scalar is rejected rather than guessed at: there is
no place on such a value for the version comment, and a check that fails closed is the safe
kind. It needs only the Python standard library, so it runs before anything is installed.

Usage:

    python3 tools/check_workflow_action_pins.py                     # CI: fail on any finding
    python3 tools/check_workflow_action_pins.py --list              # inventory of every uses:
    python3 tools/check_workflow_action_pins.py --verify-upstream   # also ask GitHub (network)

``--verify-upstream`` runs ``git ls-remote`` against ``https://github.com/<owner>/<repo>``
for the tag named in each version comment and fails if the tag does not resolve (peeled, for
annotated tags) to the pinned SHA. It is for the person changing a pin, not for CI: CI must
not depend on the network for its verdict.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

FULL_SHA = re.compile(r"[0-9a-f]{40}")
ANY_HEX = re.compile(r"[0-9a-fA-F]+")
DOCKER_DIGEST = re.compile(r"sha256:[0-9a-f]{64}")
# A version comment: `v6.1.0`, `v2.4.3`, `4.3.0`, `v1.2.3-beta.1`. The first word of the
# comment must look like one; anything after it is free text.
VERSION = re.compile(r"v?\d+(?:\.\d+)*(?:[-+][0-9A-Za-z.\-]+)?")
# A tag-shaped ref: `v4`, `v2.4.3`, `4.3`, `v1-beta`.
TAG_LIKE = re.compile(r"v?\d+(?:\.\d+)*(?:[-+.][0-9A-Za-z.\-]+)?")
# `uses` as a mapping key, optionally quoted, at the start of a (de-indented, de-dashed) line.
USES_KEY = re.compile(r"""(?P<q>["']?)uses(?P=q)[ \t]*:(?=[ \t]|$)""")
# Any mapping key, used to find the column a block scalar's content must exceed.
ANY_KEY = re.compile(r"""(?:"[^"]*"|'[^']*'|[^\s#'"{\[][^:#]*?)[ \t]*:(?=[ \t]|$)""")
BLOCK_INDICATOR = re.compile(r"[|>][0-9+\-]*")
# The action whose `version:` input is the engine version.
ENGINE_ACTION = "chickensoft-games/setup-godot"
# The repository's own wrapper around it: the only acceptable caller.
ENGINE_WRAPPER = "./.github/actions/setup-godot"
# The wrapper's own definition, which is where the upstream action is called.
WRAPPER_FILE = ".github/actions/setup-godot/action.yml"
# `version:` as a mapping key, the way USES_KEY is written.
VERSION_KEY = re.compile(r"""(?P<q>["']?)version(?P=q)[ \t]*:(?=[ \t]|$)""")
# A value that is an expression, e.g. `${{ steps.version.outputs.version }}`.
EXPRESSION = re.compile(r"^\$\{\{.*\}\}$")


@dataclass
class Use:
    """One ``uses:`` value as written, with where it was found."""

    path: str
    line: int
    value: str
    comment: str
    problems: list[str] = field(default_factory=list)
    # 1-based line of a `version:` input in this step's block, and its value, when the step
    # is the engine install. Kept on the Use because the block is what the scanner reads.
    version_lines: list[tuple[int, str]] = field(default_factory=list)

    @property
    def is_local(self) -> bool:
        return self.value.startswith("./")

    @property
    def is_docker(self) -> bool:
        return self.value.startswith("docker://")

    @property
    def name(self) -> str:
        return self.value.split("@", 1)[0]

    @property
    def ref(self) -> str:
        return self.value.split("@", 1)[1] if "@" in self.value else ""

    @property
    def repository(self) -> str:
        """``owner/repo`` for an action, the image for docker; the unit pins must agree on."""
        if self.is_docker:
            return self.name
        return "/".join(self.name.split("/")[:2])

    @property
    def version(self) -> str:
        match = VERSION.match(self.comment)
        return match.group(0) if match else ""

    @property
    def installs_engine(self) -> bool:
        """True for the engine install: the local wrapper, or the upstream action itself."""
        return self.value == ENGINE_WRAPPER or self.value.split("@", 1)[0] == ENGINE_ACTION


# --- reading -------------------------------------------------------------------------


def _strip_comment(text: str) -> tuple[str, str]:
    """Split ``text`` into (value, comment) the way YAML does.

    A comment starts at a ``#`` that is at the start or follows whitespace, and is not inside
    a quoted scalar. ``a@b#c`` is one scalar; ``a@b # c`` is a scalar and a comment.
    """
    quote = ""
    i = 0
    while i < len(text):
        ch = text[i]
        if quote:
            if quote == "'" and ch == "'" and text[i + 1:i + 2] == "'":
                i += 2
                continue
            if quote == '"' and ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = ""
        elif ch in "\"'" and (i == 0 or text[i - 1] in " \t:,{["):
            quote = ch
        elif ch == "#" and (i == 0 or text[i - 1] in " \t"):
            return text[:i].rstrip(), text[i + 1:].strip()
        i += 1
    return text.rstrip(), ""


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1].replace("''", "'")
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return value


def _content_start(line: str) -> int:
    """Column of the first character after indentation and any ``- `` list markers."""
    i = len(line) - len(line.lstrip(" "))
    while line.startswith("- ", i) or line[i:].rstrip() == "-":
        i += 2
        while i < len(line) and line[i] == " ":
            i += 1
    return i


def _flow_uses(flow: str) -> str | None:
    """The ``uses`` value inside an inline ``{ ... }`` mapping, if it has one."""
    match = re.search(r"""[{,][ \t]*(["']?)uses\1[ \t]*:[ \t]*("[^"]*"|'[^']*'|[^,}]*)""", flow)
    if not match:
        return None
    return _unquote(match.group(2))


def scan_text(text: str, path: str) -> list[Use]:
    """Every ``uses:`` in one YAML file, outside comments and block scalars."""
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    uses: list[Use] = []
    block_floor = -1  # while >= 0: inside a block scalar whose content must be deeper than this
    i = 0
    while i < len(lines):
        raw = lines[i].replace("\t", "    ")
        stripped = raw.strip()
        indent = len(raw) - len(raw.lstrip(" "))
        if block_floor >= 0:
            if not stripped or indent > block_floor:
                i += 1
                continue
            block_floor = -1
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        start = _content_start(raw)
        body = raw[start:]
        value_part, comment = _strip_comment(body)
        key = ANY_KEY.match(value_part)
        if BLOCK_INDICATOR.fullmatch(value_part):
            # `- |`: a sequence item that is itself a block scalar. Its content is deeper
            # than the dash, wherever the dash is.
            block_floor = indent
            i += 1
            continue
        if value_part.startswith("{") or value_part.startswith("["):
            found = _flow_uses(value_part)
            if found is not None:
                uses.append(Use(path, i + 1, found, comment))
            i += 1
            continue
        if not key:
            i += 1
            continue
        after_key = value_part[key.end():].strip()
        if BLOCK_INDICATOR.fullmatch(after_key or "-x-"):
            block_floor = start
            if USES_KEY.match(value_part):
                uses.append(Use(path, i + 1, "", comment,
                                ["`uses:` is a block scalar; write it on one line with a "
                                 "version comment"]))
            i += 1
            continue
        if not USES_KEY.match(value_part):
            # A key whose value is an inline flow mapping can hold `uses` too.
            if after_key.startswith("{"):
                found = _flow_uses(after_key)
                if found is not None:
                    uses.append(Use(path, i + 1, found, comment))
            i += 1
            continue
        line_no = i + 1
        if not after_key:
            # `uses:` with the value on the next significant, deeper line.
            j = i + 1
            while j < len(lines) and (not lines[j].strip() or lines[j].strip().startswith("#")):
                j += 1
            nxt = lines[j].replace("\t", "    ") if j < len(lines) else ""
            if nxt.strip() and len(nxt) - len(nxt.lstrip(" ")) > start:
                after_key, comment = _strip_comment(nxt.strip())
                line_no = j + 1
                i = j
            else:
                uses.append(Use(path, line_no, "", comment, ["`uses:` has no value"]))
                i += 1
                continue
        use = Use(path, line_no, _unquote(after_key), comment)
        # A plain scalar may continue on deeper lines; such a value is not what it looks like
        # on its first line, so it is rejected rather than read half-way.
        j = i + 1
        while j < len(lines) and not lines[j].strip():
            j += 1
        if j < len(lines):
            nxt = lines[j].replace("\t", "    ")
            nxt_indent = len(nxt) - len(nxt.lstrip(" "))
            if nxt_indent > start and not nxt.strip().startswith(("#", "- ")) \
                    and not ANY_KEY.match(nxt.strip()):
                use.problems.append("`uses:` continues on the next line; write it on one line")
        uses.append(use)
        i += 1
    # A second pass over the same lines, because the `with:` inputs of a step are read
    # after its `uses:` and belong to it by indentation. Only the engine install's
    # `version:` is judged (see `judge_version`), and only what a step writes under its own
    # `with:` counts, so an unrelated `version:` key elsewhere is not reported.
    _collect_engine_versions(lines, uses)
    return uses


def _collect_engine_versions(lines: list[str], uses: list[Use]) -> None:
    """Attach each engine-install step's ``version:`` inputs to its ``Use``."""
    for use in uses:
        if not use.installs_engine:
            continue
        # The `uses:` line, then every following line deeper than it and before the next
        # sequence item - the step's own block.
        uses_indent = len(lines[use.line - 1]) - len(lines[use.line - 1].lstrip(" "))
        step_indent = _content_start(lines[use.line - 1].replace("\t", "    "))
        i = use.line
        while i < len(lines):
            raw = lines[i].replace("\t", "    ")
            stripped = raw.strip()
            indent = len(raw) - len(raw.lstrip(" "))
            if stripped and indent <= uses_indent and stripped.startswith("- "):
                break
            if stripped and indent < step_indent:
                break
            if stripped and not stripped.startswith("#"):
                value_part, _ = _strip_comment(stripped)
                match = VERSION_KEY.match(value_part)
                if match:
                    # Quoted and unquoted are the same value to YAML, so they are the same
                    # value here: `"${{ ... }}"` is an expression, `"4.7.2"` is a literal.
                    use.version_lines.append((i + 1, _unquote(value_part[match.end():].strip())))
            i += 1


def workflow_files(root: Path) -> list[Path]:
    """The workflows, plus the repository's own composite actions."""
    files: list[Path] = []
    workflows = root / ".github" / "workflows"
    if workflows.is_dir():
        files += [p for p in workflows.iterdir() if p.suffix in (".yml", ".yaml") and p.is_file()]
    actions = root / ".github" / "actions"
    if actions.is_dir():
        files += [p for p in actions.rglob("action.y*ml") if p.suffix in (".yml", ".yaml")]
    return sorted(files)


# --- judging -------------------------------------------------------------------------


def classify_ref(ref: str) -> str:
    """Why a ref that is not a full lowercase SHA is not acceptable."""
    if not ref:
        return "no @ref: it runs whatever the default branch holds"
    if ANY_HEX.fullmatch(ref) and len(ref) == 40:
        return "SHA is not lowercase; write the 40 hex characters in lowercase"
    if ANY_HEX.fullmatch(ref) and 7 <= len(ref) < 40 and not ref.isdigit():
        return f"short SHA ({len(ref)} characters); use the full 40-character commit SHA"
    if TAG_LIKE.fullmatch(ref):
        return f"tag `{ref}` can be moved upstream; pin the commit it points to"
    return f"branch or other movable ref `{ref}`; pin a full 40-character commit SHA"


def judge(use: Use) -> list[str]:
    """Problems with one ``uses:``; empty when it is acceptable."""
    problems = list(use.problems)
    if use.is_local:
        # A local action needs no SHA, but the engine wrapper is the one local action with
        # a rule about its inputs (`judge_version`), so it is judged either way.
        return problems + judge_version(use)
    if problems:
        return problems + judge_version(use)
    if use.is_docker:
        if not DOCKER_DIGEST.fullmatch(use.ref):
            problems.append("docker image is not pinned by digest; use @sha256:<64 hex>")
    elif "/" not in use.name or use.name.startswith("/") or use.name.endswith("/"):
        problems.append(f"`{use.value}` is neither `./local` nor `owner/repo@sha`")
    elif not FULL_SHA.fullmatch(use.ref):
        problems.append(classify_ref(use.ref))
    if not problems:
        if not use.comment:
            problems.append("missing version comment; add e.g. `# v1.2.3` after the SHA")
        elif not use.version:
            problems.append(f"comment `# {use.comment}` does not start with a version")
    problems += judge_version(use)
    return problems


def judge_version(use: Use) -> list[str]:
    """Problems with how one engine-install step names the engine version (issue #217).

    Two mistakes, both of which leave a copy of the version number in a workflow:

    - installing ``chickensoft-games/setup-godot`` directly instead of the local wrapper,
      which is what reads ``.godot-version``;
    - passing ``version:`` a literal (``4.7.2``) rather than an expression. The wrapper
      passes ``${{ steps.version.outputs.version }}``; anything that is not an expression
      is a second copy of the number, and the copy is what goes stale.
    """
    if not use.installs_engine:
        return []
    problems: list[str] = []
    # The wrapper is the one place allowed to call the upstream action: it is the thing
    # that turns `.godot-version` into the input.
    if use.value.split("@", 1)[0] == ENGINE_ACTION and use.path != WRAPPER_FILE:
        problems.append(
            f"installs the engine directly; use `{ENGINE_WRAPPER}`, which reads the one "
            "version from `.godot-version` (issue #217)")
    for line, value in use.version_lines:
        if not EXPRESSION.match(value):
            problems.append(
                f"line {line}: engine `version: {value or '(empty)'}` is a literal; the "
                f"version is written once in `.godot-version` and `{ENGINE_WRAPPER}` reads "
                "it (issue #217)")
    return problems


def drift(uses: list[Use]) -> list[str]:
    """One message per external repository pinned to more than one SHA or version."""
    pins: dict[str, dict[tuple[str, str], list[Use]]] = {}
    for use in uses:
        if use.is_local or not use.ref:
            continue
        pins.setdefault(use.repository, {}).setdefault((use.ref, use.version), []).append(use)
    messages = []
    for repository, variants in sorted(pins.items()):
        if len(variants) > 1:
            where = "; ".join(
                f"@{ref[:12]} # {version or '?'} at "
                + ", ".join(f"{u.path}:{u.line}" for u in found)
                for (ref, version), found in sorted(variants.items()))
            messages.append(f"{repository} is pinned more than one way: {where}")
    return messages


def audit(root: Path) -> tuple[list[Use], list[str]]:
    """All uses under ``root`` and every problem found, as ``path:line: message``."""
    uses: list[Use] = []
    for path in workflow_files(root):
        rel = path.relative_to(root).as_posix()
        uses += scan_text(path.read_text(encoding="utf-8"), rel)
    problems = [f"{u.path}:{u.line}: `{u.value}`: {p}" for u in uses for p in judge(u)]
    problems += drift(uses)
    return uses, problems


# --- upstream (network, opt-in) -------------------------------------------------------


def ls_remote_tag(repository: str, tag: str) -> str:
    """The commit ``tag`` names in ``github.com/<repository>``, peeled; '' if absent."""
    out = subprocess.run(
        ["git", "ls-remote", "--tags", f"https://github.com/{repository}.git",
         f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}"],
        capture_output=True, text=True, check=False, timeout=60)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or f"git ls-remote failed for {repository}")
    refs = dict(reversed(line.split("\t", 1)) for line in out.stdout.splitlines() if "\t" in line)
    return refs.get(f"refs/tags/{tag}^{{}}") or refs.get(f"refs/tags/{tag}", "")


def verify_upstream(uses: list[Use]) -> list[str]:
    problems = []
    seen: set[tuple[str, str, str]] = set()
    for use in uses:
        if use.is_local or use.is_docker or not FULL_SHA.fullmatch(use.ref) or not use.version:
            continue
        key = (use.repository, use.ref, use.version)
        if key in seen:
            continue
        seen.add(key)
        try:
            commit = ls_remote_tag(use.repository, use.version)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            problems.append(f"{use.repository} {use.version}: could not ask upstream: {error}")
            continue
        status = "ok" if commit == use.ref else "MISMATCH"
        print(f"UPSTREAM {status}: github.com/{use.repository} refs/tags/{use.version} -> "
              f"{commit or '(no such tag)'}; pinned {use.ref}")
        if commit != use.ref:
            problems.append(f"{use.repository}: tag {use.version} is {commit or 'missing'} "
                            f"upstream, but the pin is {use.ref}")
    return problems


# --- command line ---------------------------------------------------------------------


def main(argv: list[str] | None = None, root: Path = ROOT) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--root", type=Path, default=root, help="repository root to scan")
    parser.add_argument("--list", action="store_true", help="print every uses: found")
    parser.add_argument("--verify-upstream", action="store_true",
                        help="check each version tag on github.com resolves to its pin")
    args = parser.parse_args(argv)

    if not workflow_files(args.root):
        print(f"WORKFLOW_PINS_FAILURE: no workflow files under {args.root}/.github/workflows")
        return 1
    uses, problems = audit(args.root)
    if args.list:
        for use in uses:
            kind = "local" if use.is_local else "external"
            print(f"{use.path}:{use.line}: {kind} {use.value}"
                  + (f" # {use.comment}" if use.comment else ""))
    if args.verify_upstream:
        problems += verify_upstream(uses)
    if problems:
        for problem in problems:
            print("WORKFLOW_PINS_FAILURE: " + problem)
        print(f"{len(problems)} problem(s) in {len(uses)} uses: reference(s).")
        return 1
    external = [u for u in uses if not u.is_local]
    print(f"WORKFLOW_PINS_OK: {len(external)} external reference(s) pinned by full SHA "
          f"({len({u.repository for u in external})} repositories), "
          f"{len(uses) - len(external)} local reference(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
