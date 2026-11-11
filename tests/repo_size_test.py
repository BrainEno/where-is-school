#!/usr/bin/env python3
"""Boundary tests for ``tools/repo_size.py``.

A size check that quietly checks nothing is worse than none, and this one runs in a
shallow CI checkout where half of what it reports on is invisible. So it is tested against
repositories this file builds:

- a checkout with nothing large passes, and one with a file exactly at the ceiling still
  passes: the ceiling is a `>`, not a `>=`, and both sides of it are tested;
- one byte over the ceiling fails, and the failure names the file and its size;
- an untracked 100 MB render in somebody's working tree is *not* the repository's weight
  and must not fail the check — that is the difference between `git ls-files` and a
  directory walk, and it is tested;
- `.gitignore`d files are not counted either;
- the report lists the largest tracked file first, and still finds a blob that a later
  commit deleted, with the commit that added it — the case the 70.6 MB model left behind;
- a directory that is not a checkout reports a problem instead of passing silently.

Run it with ``python3 tests/repo_size_test.py`` (CI does). It needs `git` and nothing else.
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import repo_size  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS: int = 0

# A ceiling small enough that the test's own files stay small. The real one is 12 MiB and
# is tested separately by `the_shipped_ceiling`, which only asserts its value and its
# relation to the largest legitimate file in the tree.
CEILING = 1000


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def git(root: str, *args: str) -> str:
    return subprocess.run(
        ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", *args],
        cwd=root, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ).stdout.decode("utf-8", "replace")


def write(root: str, rel: str, size: int) -> None:
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True) if os.path.dirname(rel) else None
    with open(path, "wb") as handle:
        handle.write(b"x" * size)


def make_repo(root: str, files: dict[str, int]) -> None:
    git(root, "init", "-q", "-b", "main")
    for rel, size in files.items():
        write(root, rel, size)
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "files")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        make_repo(repo, {"assets/small.txt": 10, "docs/notes.md": 20})

        check(repo_size.oversize(repo, CEILING) == [],
              "a checkout with no large file must have no offenders")
        check(repo_size.main(["--check", "--root", repo]) == 0,
              "--check must return 0 for a clean checkout")
        check(set(repo_size.tracked_files(repo)) == {"assets/small.txt", "docs/notes.md"},
              "tracked_files must list exactly the committed files")

        # The ceiling itself passes; one byte over does not.
        write(repo, "art/exactly_at_the_line.glb", CEILING)
        write(repo, "art/one_byte_over.glb", CEILING + 1)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "two files around the ceiling")
        offenders = dict(repo_size.oversize(repo, CEILING))
        check("art/exactly_at_the_line.glb" not in offenders,
              "a file exactly at the ceiling must pass, got: %s" % sorted(offenders))
        check(offenders.get("art/one_byte_over.glb") == CEILING + 1,
              "one byte over the ceiling must be an offender with its size, got: %s" % offenders)

        print("--- expected failures below (the check is doing its job) ---")
        saved = repo_size.PER_FILE_CEILING
        try:
            repo_size.PER_FILE_CEILING = CEILING
            check(repo_size.main(["--check", "--root", repo]) == 1,
                  "--check must return 1 when a tracked file is over the ceiling")
            check(repo_size.oversize(repo) == [("art/one_byte_over.glb", CEILING + 1)],
                  "--check must default to the module ceiling")

            # An untracked file, however large, is not the repository's weight.
            write(repo, "art/render_i_have_not_committed.png", CEILING * 50)
            check("art/render_i_have_not_committed.png"
                  not in dict(repo_size.oversize(repo, CEILING)),
                  "an untracked large file must not be an offender")

            # Neither is an ignored one, once it is committed by force elsewhere.
            with open(os.path.join(repo, ".gitignore"), "w", encoding="utf-8") as handle:
                handle.write("art/ignored/\n")
            write(repo, "art/ignored/big.glb", CEILING * 2)
            git(repo, "add", ".gitignore")
            git(repo, "commit", "-q", "-m", "ignore art/ignored")
            check("art/ignored/big.glb" not in dict(repo_size.oversize(repo, CEILING)),
                  "an ignored, untracked file must not be an offender")

            # The report: largest first, and history keeps what the tree dropped.
            text = repo_size.report(repo)
            check("art/one_byte_over.glb" in text, "the report must list the largest file")
            check(text.index("art/one_byte_over.glb") < text.index("docs/notes.md"),
                  "the report must list the largest file first, got:\n%s" % text)
        finally:
            repo_size.PER_FILE_CEILING = saved

    # A file that was committed and then deleted is still in history, with its author
    # commit: this is the shape of the 70.6 MB model that this check exists to stop.
    with tempfile.TemporaryDirectory() as tmp:
        repo = os.path.join(tmp, "repo")
        os.makedirs(repo)
        make_repo(repo, {"art/keep.glb": 10})
        write(repo, "art/gone.glb", CEILING * 3)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "add the big model")
        git(repo, "rm", "-q", "art/gone.glb")
        git(repo, "commit", "-q", "-m", "drop it again")

        check(repo_size.oversize(repo, CEILING) == [],
              "a deleted file must not fail the check: only tracked files count")
        blobs = repo_size.history_blobs(repo, rows=5)
        check(blobs and blobs[0][1] == "art/gone.glb",
              "the history report must still see the deleted blob, got: %s" % blobs)
        added = repo_size.adding_commit(repo, "art/gone.glb")
        check("add the big model" in added,
              "the history report must credit the commit that added it, got: %r" % added)
        check(repo_size.history_depth(repo) is False,
              "a repository this test built is not shallow")

    # Not a checkout at all: a problem, not a pass.
    with tempfile.TemporaryDirectory() as tmp:
        print("--- expected failure below (not a checkout) ---")
        check(repo_size.main(["--check", "--root", tmp]) == 1,
              "--check must fail outside a checkout instead of reporting success")

    # The real ceiling, and the files it has to clear. If someone lowers it below the
    # largest legitimate source in the tree, this says so before CI does.
    check(repo_size.PER_FILE_CEILING == 12 * 1024 * 1024,
          "the per-file ceiling moved; update this test and the ADR together")
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    largest = max(
        (os.path.getsize(os.path.join(root, path)), path)
        for path in repo_size.tracked_files(root)
        if os.path.exists(os.path.join(root, path))
    )
    check(largest[0] <= repo_size.PER_FILE_CEILING,
          "the tree holds %s at %d bytes, over its own ceiling (%s)"
          % (largest[1], largest[0], repo_size._human(repo_size.PER_FILE_CEILING)))

    if FAILURES:
        for failure in FAILURES:
            print("REPO_SIZE_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("REPO_SIZE_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
