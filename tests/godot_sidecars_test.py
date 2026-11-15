#!/usr/bin/env python3
"""Boundary tests for ``tools/godot_sidecars.py`` (issue #67).

The audit is only worth running if its reading of a UID is the engine's reading. So:

- ``decode``/``encode`` agree with ``core/io/resource_uid.cpp`` on fixed values taken from
  the engine (``uid://d4n4ub6itg400`` is 2^63 - 1; ``uid://a`` is 0) and round-trip random
  ones; ``z`` reads as the digit ``0`` does and ``9`` carries; a 13-character value past the
  maximum wraps and is masked instead of refused; a bad prefix, an empty value and a foreign
  character are refused;
- in trees this test writes: a clean tree passes; a malformed value, two owners with one
  UID (including two *texts* that decode to one number), and an orphaned ``.uid`` each fail
  ``--check``; the same owner declaring one UID twice does not;
- non-canonical values, a reference to an undeclared UID, a reference whose UID belongs to
  another file and a script without a sidecar are reported and do **not** fail;
- ``--after-import`` reads a real ``git status``: a ``.uid`` the "engine" created is listed
  with its value, a rewritten tracked ``.import`` is listed, and a script that got nothing
  stays "not requested";
- notices are chunked so that a long list survives a runner's per-step annotation limit;
- the repository itself has no errors.

Run with ``python3 tests/godot_sidecars_test.py`` (CI does). No network, no engine.
"""

from __future__ import annotations

import contextlib
import io
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import godot_sidecars as uids  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run(root: Path, *args: str) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = uids.main(list(args) + ["--root", str(root)])
    return code, out.getvalue()


def scene(uid: str | None, refs: list[tuple[str, str]] | None = None) -> str:
    header = '[gd_scene load_steps=2 format=3%s]\n\n' % (' uid="%s"' % uid if uid else "")
    for index, (ref_uid, path) in enumerate(refs or []):
        header += '[ext_resource type="Script" uid="%s" path="res://%s" id="%d_x"]\n' % (
            ref_uid, path, index
        )
    return header + '\n[node name="Root" type="Node3D"]\n'


# --- The engine's arithmetic --------------------------------------------------


def engine_values() -> None:
    check(uids.decode("uid://a") == 0, "uid://a is 0")
    check(uids.decode("uid://d4n4ub6itg400") == (1 << 63) - 1, "the engine's maximum")
    check(uids.encode((1 << 63) - 1) == "uid://d4n4ub6itg400", "the maximum encodes back")
    check(uids.encode(0) == "uid://a", "0 encodes as a")
    check(uids.encode(33) == "uid://8", "the last digit is 8")
    check(uids.encode(34) == "uid://ba", "34 carries")
    rng = random.Random(67)
    for _ in range(500):
        value = rng.randrange(0, 1 << 63)
        text = uids.encode(value)
        check(uids.decode(text) == value and uids.is_canonical(text), "round trip %d" % value)
    # The two characters the engine reads but never writes.
    check(uids.decode("uid://bz") == uids.decode("uid://b0"), "z reads as the digit 0")
    check(not uids.is_canonical("uid://bz"), "z is not canonical")
    check(uids.decode("uid://b9") == uids.decode("uid://ca"), "9 reads as 34 and carries")
    check(not uids.is_canonical("uid://b9"), "9 is not canonical")
    # Past the maximum: wrapped and masked, as `text_to_id` does - not refused.
    past = "uid://foh8ozflzjosm"
    value = uids.decode(past)
    check(value is not None and 0 <= value <= (1 << 63) - 1, "an overflow is masked, not refused")
    check(not uids.is_canonical(past), "an overflowing text is not canonical")
    check(uids.encode(value or 0) == "uid://bs3d3xidgcs1u", "the masked value's engine text")
    for bad in ("", "uid://", "res://abc", "uid://AB", "uid://ab-c", "uid://<invalid>"):
        check(uids.decode(bad) is None, "%r must be refused" % bad)


# --- Trees ------------------------------------------------------------------


def clean_tree() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write(root, "a.gd", "extends Node\n")
        write(root, "a.gd.uid", uids.encode(1234) + "\n")
        write(root, "s.tscn", scene(uids.encode(99), [(uids.encode(1234), "a.gd")]))
        write(root, "m.glb.import", '[remap]\n\nimporter="scene"\nuid="%s"\n' % uids.encode(7))
        code, out = run(root, "--check")
        check(code == 0, "a clean tree passes: " + out)
        check("UID declarations: 3; ext_resource UID references: 1" in out, "counts: " + out)
        check("0 non-canonical" in out and "0 script/shader file(s) without" in out, "no findings: " + out)


def errors_fail() -> None:
    cases = {
        "malformed": {"a.gd": "extends Node\n", "a.gd.uid": "uid://NOT-A-UID\n"},
        "duplicate": {
            "a.gd": "", "a.gd.uid": uids.encode(5) + "\n",
            "b.gd": "", "b.gd.uid": uids.encode(5) + "\n",
        },
        # Two different texts, one number: the engine would cache one and lose the other.
        "duplicate by decoding": {
            "a.tscn": scene("uid://bz"), "b.tscn": scene("uid://b0"),
        },
        "orphan": {"gone.gd.uid": uids.encode(8) + "\n"},
    }
    for label, files in cases.items():
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for rel, text in files.items():
                write(root, rel, text)
            code, out = run(root, "--check", "--github")
            check(code == 1, "%s must fail --check: %s" % (label, out))
            word = label.split()[0].upper()
            check(word in out, "%s is named in the output: %s" % (label, out))
            check("::error title=UID" in out, "%s gets an ::error annotation" % label)
            check("UID_AUDIT=failure" in out, "%s reports failure" % label)


def same_owner_twice_is_one_identity() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write(root, "s.tscn", scene(uids.encode(42)))
        write(root, "s.tscn.uid", uids.encode(42) + "\n")
        code, out = run(root, "--check")
        check(code == 0 and "DUPLICATE" not in out, "one owner, one UID twice, is not a collision: " + out)


def findings_do_not_fail() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write(root, "a.gd", "")
        write(root, "a.gd.uid", "uid://bz\n")  # non-canonical
        write(root, "b.gd", "")  # no sidecar
        write(root, "c.gdshader", "")  # no sidecar either
        write(root, "other.gd", "")
        write(root, "other.gd.uid", uids.encode(77) + "\n")
        write(root, "s.tscn", scene(uids.encode(10), [
            (uids.encode(555), "nowhere.gd"),  # undeclared
            (uids.encode(77), "b.gd"),  # declared by other.gd, not b.gd
        ]))
        code, out = run(root, "--check", "--github")
        check(code == 0, "findings alone must not fail: " + out)
        check("1 non-canonical value(s), 1 reference(s) to an undeclared UID, "
              "1 reference(s) whose UID names another file, 2 script/shader file(s) without a sidecar"
              in out, "findings counted: " + out)
        check("(the engine writes uid://b0)" in out, "the engine's form is shown")
        check("no sidecar b.gd" in out and "no sidecar c.gdshader" in out, "missing sidecars listed")
        check("::warning title=UID references" in out, "references get one warning")
        code, report = run(root, "--report")
        check(code == 0 and "| ... without a `.uid` sidecar | 2 |" in report, "report table: " + report)
        check("- `b.gd`" in report and "`uid://bz` (engine form `uid://b0`)" in report, "report lists")


def after_import() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        git = ["git", "-C", str(root), "-c", "user.email=t@t", "-c", "user.name=t"]
        subprocess.run(git[:3] + ["init", "-q"], check=True)
        write(root, "kept.gd", "")
        write(root, "made.gd", "")
        write(root, "skipped.gd", "")
        write(root, "m.png.import", '[remap]\n\nuid="%s"\n' % uids.encode(3))
        # Non-canonical on purpose: whether an import rewrites such a value is the question.
        write(root, "z.png.import", '[remap]\n\nuid="uid://bz"\n\n[params]\nmipmaps=false\n')
        subprocess.run(git + ["add", "-A"], check=True)
        subprocess.run(git + ["commit", "-q", "-m", "fixture"], check=True)
        # What an engine import does: create one sidecar, rewrite one .import, and leave
        # `.godot/` behind (which is not the repository's business).
        write(root, "made.gd.uid", uids.encode(31337) + "\n")
        write(root, "m.png.import", '[remap]\n\nuid="%s"\n\n[deps]\ndest_files=[]\n' % uids.encode(3))
        write(root, "z.png.import", '[remap]\n\nuid="uid://b0"\n\n[params]\nmipmaps=false\n')
        write(root, ".godot/imported/x.ctex", "x")
        code, out = run(root, "--after-import", "--github")
        check(code == 0, "--after-import reports, never fails")
        check("1 sidecar(s) created by the engine, 2 tracked UID file(s) rewritten, "
              "2 script/shader file(s) still without one" in out, "delta counts: " + out)
        check("REWRITTEN m.png.import: uid kept; [deps] dest_files" in out,
              "a rewrite that keeps the uid names the keys it changed: " + out)
        check("REWRITTEN z.png.import: uid uid://bz -> uid://b0; [remap] uid" in out,
              "a normalised uid is shown with both values")
        check("2 rewritten (1 with a new uid)" in out, "the summary notice counts uid changes")
        check("CREATED made.gd.uid %s" % uids.encode(31337) in out, "the engine's value is kept")
        check("NOT REQUESTED kept.gd" in out and "NOT REQUESTED skipped.gd" in out, "untouched scripts")
        check(".godot" not in out, ".godot/ is ignored")
        check("::notice title=engine sidecars 1/1::made.gd.uid=%s" % uids.encode(31337) in out,
              "the created sidecar is published as a notice")


def rewrite_details() -> None:
    header = '[gd_scene load_steps=2 format=3 uid="%s"]\n\n[node name="R" type="Node3D"]\n'
    rewrite = uids.describe_rewrite("a.tscn", header % "uid://bz", header % "uid://b0")
    check(rewrite.uid_before == "uid://bz" and rewrite.uid_after == "uid://b0", "scene header uid")
    check(rewrite.changed_keys == [], "the header's uid is not an INI key: %s" % rewrite.changed_keys)
    sidecar = uids.describe_rewrite("a.gd.uid", "uid://bz\n", "uid://b0\n")
    check(sidecar.describe() == "a.gd.uid: uid uid://bz -> uid://b0; nothing else changed",
          sidecar.describe())
    fresh = uids.describe_rewrite("n.png.import", "", '[remap]\nuid="uid://b0"\n')
    check(fresh.describe() == "n.png.import: uid (none) -> uid://b0; [remap] uid", fresh.describe())
    nested = uids.describe_rewrite(
        "m.glb.import",
        '[params]\n_subresources={\n"a": 1\n}\n',
        '[params]\n_subresources={\n"a": 2\n}\n',
    )
    check(nested.describe() == "m.glb.import: uid kept; changed outside single-line keys "
          "(a multi-line value or formatting)", nested.describe())
    unchanged = uids.describe_rewrite("u.png.import", "[params]\na=1\n", "[params]\na=1\n")
    check(unchanged.describe() == "u.png.import: uid kept; no change", unchanged.describe())
    same = uids.describe_rewrite("s.png.import", "[params]\na=1\n", "[params]\na=1\nb=2\n")
    check(not same.uid_changed and same.changed_keys == ["[params] b"], same.describe())


def notices_are_chunked() -> None:
    items = ["scripts/some/long/path/file_%03d.gd.uid=uid://%s" % (i, "b" * 12) for i in range(60)]
    notices = uids.chunked_notices("engine sidecars", items)
    check(1 < len(notices) <= 3, "60 entries fit in a few notices, got %d" % len(notices))
    check(all(len(n) < 4000 for n in notices), "every notice stays under the annotation size")
    joined = " ".join(notices)
    check(all(item in joined for item in items), "no entry is dropped")
    check(notices[0].startswith("::notice title=engine sidecars 1/%d::" % len(notices)), "numbered")
    check(uids.chunked_notices("x", []) == [], "nothing to say, no notice")


def this_repository() -> None:
    code, out = run(Path(uids.ROOT), "--check")
    check(code == 0, "the repository has no malformed, duplicate or orphaned UID:\n" + out)


def main() -> int:
    engine_values()
    clean_tree()
    errors_fail()
    same_owner_twice_is_one_identity()
    findings_do_not_fail()
    after_import()
    rewrite_details()
    notices_are_chunked()
    this_repository()
    if FAILURES:
        for failure in FAILURES:
            print("GODOT_SIDECARS_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("GODOT_SIDECARS_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    os.environ.setdefault("GIT_CONFIG_NOSYSTEM", "1")
    sys.exit(main())
