#!/usr/bin/env python3
"""Keep large binaries out of the repository, and make the ones already in it explainable.

Issue #97: this repository went from 169 MB to 433 MB in ten hours. Most of that was the
screenshot write-back, which PR #88 stopped; what is left is the ordinary way a game
repository grows — a source model, an uncompressed recording, a re-baked animation
resource, each one copied into history the moment it changes, forever. One commit was
worth 70.6 MB on its own: a 4K prop's source export.

No budget checked that. The pack budget in `tools/verify_build.py` only sees what ships,
so a 67 MiB file that never ships costs every clone and fails nothing; `git` has no opinion
either. This tool is the missing check, and it is deliberately about *the repository*, not
the build:

- `--check` fails when any tracked file is over `PER_FILE_CEILING`, whatever it is and
  wherever it lives. There is no exception list, because an exception list is how the
  70 MB file got in: someone would have added it to the list.
- `--report` prints the largest tracked files and the largest blobs in the clone's
  history, with the commit that added each one, plus the size of the packfiles. That is
  what makes a week of growth explainable instead of mysterious: a number, a path, a
  commit.

What the ceiling is, and why it is not the pack's 2 MiB: a file under `assets/` is judged by
`tools/verify_build.py` *as shipped* — that check is the one that matters for a runtime
asset, and it is stricter. This one is about what a clone has to carry: the repository
legitimately holds two uncompressed font sources (the OFL files the bundled subsets are
built from: Noto Sans SC at 10.1 MiB and Noto Serif SC at 11.1 MiB) and a 7.3 MiB third-party
animation library used by a dev-only retarget test. 12 MiB clears all three and stops anything of the 70 MB class, which is the size at which a file
is a source export, a raw recording, or a mistake.

Rules this encodes, written out in `docs/adr/0007-large-binaries-and-repository-size.md`:

| Where | What it may hold | Judged by |
|---|---|---|
| `assets/**` | what the game imports | `tools/verify_build.py`, as shipped (2 MiB per file) |
| `art/**`, `scenes/dev/**`, `docs/**` | sources, scratch, evidence | this tool (12 MiB per file) |
| anything | — | `git ls-files` is the list; untracked work is not the repository's weight |

Usage:

    python3 tools/repo_size.py --check     # CI: fails on an oversized tracked file
    python3 tools/repo_size.py --report    # the largest files, in the tree and in history

It needs `git` and nothing else — no engine, no network, no Python packages.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

MiB = 1024 * 1024

# The per-file ceiling for anything in the repository. See the module docstring: it clears
# the larger font source (11.1 MiB) by 0.9 MiB and is 5x under the 67.4 MiB file that made this
# necessary.
PER_FILE_CEILING = 12 * MiB

# How many entries `--report` prints from each list.
REPORT_ROWS = 10

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _git(root: str, *args: str) -> str:
    """Run git in `root` and return its stdout as text.

    Raises `RuntimeError` with git's own message when the command fails, so a broken
    checkout reports "not a git repository" instead of silently checking nothing.
    """
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=root,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError as error:
        raise RuntimeError("git is not installed") from error
    except subprocess.CalledProcessError as error:
        message = error.stderr.decode("utf-8", "replace").strip().splitlines()
        raise RuntimeError(message[-1] if message else "git failed") from error
    return result.stdout.decode("utf-8", "surrogateescape")


def tracked_files(root: str) -> list[str]:
    """Every path git tracks, relative to `root`.

    `git ls-files` and not a directory walk: the question is what the repository carries,
    and an untracked 500 MB render in someone's working tree is not that. It also keeps
    the check honest about `.gitignore`: anything deliberately ignored is not counted.
    """
    listing = _git(root, "ls-files", "-z")
    return sorted(path for path in listing.split("\0") if path)


def _human(size: int) -> str:
    if size >= MiB:
        return "%.1f MiB" % (size / MiB)
    if size >= 1024:
        return "%.0f KiB" % (size / 1024.0)
    return "%d bytes" % size


def oversize(root: str, ceiling: int | None = None) -> list[tuple[str, int]]:
    """Tracked files larger than `ceiling` (default `PER_FILE_CEILING`), largest first."""
    ceiling = PER_FILE_CEILING if ceiling is None else ceiling
    found = []
    for path in tracked_files(root):
        try:
            size = os.path.getsize(os.path.join(root, path))
        except OSError:
            continue  # a tracked file deleted from the working tree; not this check's job
        if size > ceiling:
            found.append((path, size))
    return sorted(found, key=lambda pair: pair[1], reverse=True)


def adding_commit(root: str, path: str) -> str:
    """The oldest commit this clone can see that added `path`: `sha (date) subject`.

    This is the answer to "where did this come from" that a size report is useless
    without. `--diff-filter=A` follows merges, so a file that arrived through a pull
    request is credited to the merge that landed it. The *oldest* such commit is the one
    that introduced it; `git log` prints newest first, so the last line is the one wanted.

    A shallow clone only knows its own history, so the answer there is its boundary
    commit, and the caller says so instead of implying the file was born at HEAD.
    """
    try:
        output = _git(root, "log", "--all", "--diff-filter=A", "--format=%h (%ad) %s",
                      "--date=short", "--", path).strip()
    except RuntimeError:
        return "unknown"
    return output.splitlines()[-1] if output else "unknown"


def history_depth(root: str) -> bool:
    """True when this clone's history is truncated, so attribution stops at a boundary."""
    try:
        return _git(root, "rev-parse", "--is-shallow-repository").strip() == "true"
    except RuntimeError:
        return False


def history_blobs(root: str, rows: int = REPORT_ROWS) -> list[tuple[int, str, str]]:
    """The largest blobs anywhere in this clone's history: `(size, path, oid)`.

    `git rev-list --objects --all` names every object reachable from every ref; the
    sizes come from one `cat-file --batch-check` call rather than one per object. In a
    shallow clone this is the history the clone has, which is the history it carries.
    """
    listing = _git(root, "rev-list", "--objects", "--all")
    objects: list[tuple[str, str]] = []
    for line in listing.splitlines():
        oid, _, path = line.partition(" ")
        if path:
            objects.append((oid, path))
    if not objects:
        return []
    try:
        batch = subprocess.run(
            ["git", "cat-file", "--batch-check=%(objecttype) %(objectsize)"],
            cwd=root,
            check=True,
            input="\n".join(oid for oid, _ in objects).encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.decode("utf-8", "replace")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return []
    blobs: list[tuple[int, str, str]] = []
    for (oid, path), line in zip(objects, batch.splitlines()):
        parts = line.split()
        if len(parts) != 2 or parts[0] != "blob":
            continue
        try:
            size = int(parts[1])
        except ValueError:
            continue
        blobs.append((size, path, oid))
    blobs.sort(key=lambda row: row[0], reverse=True)
    return blobs[:rows]


def packfile_size(root: str) -> str:
    """`in-pack` size of the object store, as git reports it."""
    try:
        output = _git(root, "count-objects", "-vH")
    except RuntimeError:
        return "unknown"
    for line in output.splitlines():
        if line.startswith("size-pack:"):
            return line.split(":", 1)[1].strip()
    return "unknown"


def report(root: str) -> str:
    files = tracked_files(root)
    total = sum(os.path.getsize(os.path.join(root, path))
                for path in files if os.path.exists(os.path.join(root, path)))
    lines = [
        "%d tracked file(s), %s in the working tree" % (len(files), _human(total)),
        "%s of packfiles in .git (this clone)" % packfile_size(root),
        "",
        "Largest tracked files:",
    ]
    largest = sorted(
        ((os.path.getsize(os.path.join(root, path)), path) for path in files
         if os.path.exists(os.path.join(root, path))),
        reverse=True,
    )[:REPORT_ROWS]
    for size, path in largest:
        flag = "  <-- over the %s ceiling" % _human(PER_FILE_CEILING) \
            if size > PER_FILE_CEILING else ""
        lines.append("  %10s  %s%s" % (_human(size), path, flag))

    lines += ["", "Largest blobs in history (deleted files still count):"]
    for size, path, _oid in history_blobs(root):
        lines.append("  %10s  %s" % (_human(size), path))
        lines.append("              added by %s" % adding_commit(root, path))
    if history_depth(root):
        lines += ["",
                  "This clone is shallow: its oldest commit is where every attribution above",
                  "stops. Run `git fetch --unshallow` in a full clone for the real commit."]
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true",
                        help="fail when a tracked file is over the per-file ceiling")
    parser.add_argument("--report", action="store_true",
                        help="print the largest files in the tree and in history")
    parser.add_argument("--root", default=ROOT,
                        help="the checkout to look at (default: the one this file is in)")
    options = parser.parse_args(argv or ["--check"])
    root = os.path.abspath(options.root)

    try:
        if options.report:
            print(report(root))
            return 0

        offenders = oversize(root)
        if offenders:
            shallow = history_depth(root)
            for path, size in offenders:
                where = "" if shallow else "; added by %s" % adding_commit(root, path)
                print("REPO_SIZE_PROBLEM: %s is %s, over the %s ceiling for a single tracked "
                      "file%s" % (path, _human(size), _human(PER_FILE_CEILING), where))
            print("A file this large is a source export, a raw recording or a mistake. "
                  "Sources belong in art/ or outside the repository; runtime assets are "
                  "judged as shipped by tools/verify_build.py. See "
                  "docs/adr/0007-large-binaries-and-repository-size.md")
            return 1
        files = tracked_files(root)
        print("REPO_SIZE_OK: %d tracked file(s), none over the %s ceiling."
              % (len(files), _human(PER_FILE_CEILING)))
        return 0
    except RuntimeError as error:
        print("REPO_SIZE_PROBLEM: %s (run this inside the checkout: --root <path>)" % error)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
