#!/usr/bin/env python3
"""Tests for ``tools/engine_noise_report.py`` (issue #67), on logs this test writes.

The log lines are the engine's own strings (Godot ``core/object/object.cpp``,
``core/io/resource.cpp``, ``core/templates/rid_owner.h``), so a change in how the report reads
them is caught here rather than in a CI run that silently reports "0 leaked":

- the leak count is read in both the plural and the singular form, and a log without the
  warning reports none;
- ``--verbose`` detail is attributed: a node by its path, a resource by its path, a bare
  object by its class, ``Resource still in use`` lines and ``Orphan StringName`` lines;
- every ERROR/WARNING line lands in exactly one bucket, with the ``at:`` location under it,
  and the portrait warning of a 64x64 headless window is filed as such, not as unknown;
- ``SCRIPT ERROR`` is counted but not filed (it is already a failure elsewhere);
- the probe ladder reports what each rung adds over the one below it;
- the GitHub output stays within a few notices however many logs there are, and no line
  is dropped from the Markdown;
- the command line reads a directory, appends to a step summary, and always exits 0 - it
  is a report, not a gate.

Run with ``python3 tests/engine_noise_report_test.py`` (CI does).
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))

import engine_noise_report as noise  # noqa: E402  (the path has to be set up first)

FAILURES: list[str] = []
CHECKS = 0

LEAK_2 = (
    "WARNING: 2 ObjectDB instances were leaked at exit (run with `--verbose` for details).\n"
    "     at: cleanup (core/object/object.cpp:2609)\n"
)
LEAK_1 = (
    "WARNING: 1 ObjectDB instance was leaked at exit (run with `--verbose` for details).\n"
    "     at: cleanup (core/object/object.cpp:2609)\n"
)
VERBOSE = (
    "Leaked instance: Timer:9223372094867727394 - Node path: \n"
    # Resources are reference-counted, and the engine's later class test wins: a leaked
    # script is named by its reference count, not its path.
    "Leaked instance: GDScript:9223372061229581301 - Reference count: 2\n"
    "Leaked instance: Object:27195279376\n"
    "Hint: Leaked instances typically happen when nodes are removed from the scene tree "
    "(with `remove_child()`) but not freed (with `free()` or `queue_free()`).\n"
)
IN_USE = (
    "ERROR: 1 resources still in use at exit.\n"
    "   at: clear (core/io/resource.cpp:817)\n"
    "Resource still in use: res://tests/test_harness.gd (GDScript)\n"
    "Orphan StringName: stage (static: 0, total: 1)\n"
)
PORTRAIT = (
    "WARNING: DialoguePanel portrait: Character 'q': only 0 px of the 57 px band are left "
    "for the portrait; it is not shown.\n"
    "     at: push_warning (core/variant/variant_utility.cpp:1034)\n"
)


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        FAILURES.append(message)


def leak_counts() -> None:
    check(noise.read_log("a", LEAK_2).leak_count == 2, "plural leak count")
    check(noise.read_log("b", LEAK_1).leak_count == 1, "singular leak count")
    check(noise.read_log("c", "PASS: fine\n").leak_count is None, "no warning, no leak")
    check(noise.read_log("d", LEAK_2).buckets["objectdb_leak"] == 1, "filed as objectdb_leak")


def verbose_detail() -> None:
    report = noise.read_log("v", LEAK_2 + VERBOSE + IN_USE)
    check(report.leaked["Timer"] == 1, "a node outside the tree has an empty path: by class")
    check(report.leaked["GDScript (refs 2)"] == 1, "a reference-counted object by its count")
    check(report.leaked["Object"] == 1, "a bare object by its class")
    check(sum(report.leaked.values()) == 3, "three instances, the hint line is not one")
    check(report.unread_leak_lines == [] and not report.missing_detail, "all detail read")
    node = noise.read_log("n", LEAK_1 + "Leaked instance: Timer:12 - Node path: /root/Main/T\n")
    check(node.leaked["Timer @ /root/Main/T"] == 1, "a node in a tree by its path")
    odd = noise.read_log("o", LEAK_1 + "Leaked instance: Timer:12 - Owner: somewhere\n")
    check(odd.leaked == {} and odd.unread_leak_lines == ["Leaked instance: Timer:12 - Owner: somewhere"],
          "a shape the engine did not use to print is kept as unread, not dropped")
    check(not odd.missing_detail, "an unread line is still detail")
    check(noise.read_log("q", LEAK_2).missing_detail, "a count without detail is said to be one")
    check(not noise.read_log("c", "PASS\n").missing_detail, "no leak, nothing missing")
    check(report.resources_in_use["res://tests/test_harness.gd (GDScript)"] == 1, "in use")
    check(report.orphan_stringnames == 1, "orphan StringName counted")
    check(report.buckets["resources_in_use"] == 1, "the in-use ERROR is bucketed")
    check(report.errors == 1 and report.warnings == 1, "counts: %d/%d" % (report.errors, report.warnings))


def buckets_and_locations() -> None:
    text = (
        PORTRAIT
        + "ERROR: 3 RID allocations of type 'N12RendererRD12MeshStorageE' were leaked at exit.\n"
        + "ERROR: Save: could not write user://save.json (error 7) (write).\n"
        + "   at: push_error (core/variant/variant_utility.cpp:1024)\n"
        + "WARNING: Something nobody has seen before.\n"
        + "SCRIPT ERROR: Invalid access to property or key 'x' on a base object of type 'Nil'.\n"
    )
    report = noise.read_log("mix", text)
    check(report.buckets["portrait_no_room"] == 1, "the portrait warning has its bucket")
    check(report.buckets["rid_leak"] == 1, "RID leak bucketed")
    check(report.buckets["save_refusal"] == 1, "save refusal bucketed")
    check(report.buckets["unclassified"] == 1, "the unknown line is unclassified")
    check(report.unclassified == ["WARNING: Something nobody has seen before."], "sample kept")
    check(report.script_errors == 1 and "SCRIPT ERROR" not in "".join(report.buckets), "script error counted only")
    check(sum(report.buckets.values()) == report.errors + report.warnings, "every line in exactly one bucket")
    check(report.locations["portrait_no_room"]["push_warning (core/variant/variant_utility.cpp:1034)"] == 1,
          "the at: line is kept with its bucket")


def ladder() -> None:
    rung0 = noise.read_log("probe_0_bare", LEAK_1 + "Leaked instance: Object:1\n")
    rung1 = noise.read_log(
        "probe_1_watchdog",
        LEAK_2 + "Leaked instance: Object:1\nLeaked instance: GDScript:2 - Resource path: res://t.gd\n",
    )
    rung2 = noise.read_log("probe_2_state_autoloads", LEAK_2 + "Leaked instance: Object:1\n"
                           "Leaked instance: GDScript:2 - Resource path: res://t.gd\n")
    other = noise.read_log("camera_rig", LEAK_2 + "Leaked instance: Object:1\n" + IN_USE)
    steps = noise.probe_ladder([rung2, other, rung0, rung1])
    check([s[0] for s in steps] == ["probe_0_bare", "probe_1_watchdog", "probe_2_state_autoloads"],
          "rungs in order, other logs left out: %s" % [s[0] for s in steps])
    check(dict(steps[0][3]) == {"Object": 1}, "rung 0 adds the baseline")
    check(dict(steps[1][3]) == {"GDScript @ res://t.gd": 1}, "rung 1 adds the script")
    check(dict(steps[2][3]) == {}, "rung 2 adds nothing")
    markdown = "\n".join(noise.format_markdown([rung0, rung1, rung2, other]))
    check("## Minimal reproduction (probe ladder)" in markdown, "the ladder section is written")
    check("| probe_1_watchdog | 2 | `GDScript @ res://t.gd` x1 |" in markdown, "a rung row: " + markdown)
    check("| `Object` | 4 |" in markdown, "an instance across logs")
    terse = noise.read_log("probe_0_bare", LEAK_2)
    notices = "\n".join(noise.format_github([terse, other]))
    check("probe_0_bare: leak 2, adds no --verbose detail" in notices,
          "a rung without detail says so, not 'adds nothing': " + notices)
    check("::notice title=still in use at exit 1/1::camera_rig: res://tests/test_harness.gd (GDScript)"
          in notices, "resources still in use are published")
    check("| probe_0_bare | 2 | no --verbose detail |" in "\n".join(noise.format_markdown([terse])),
          "and the Markdown says so too")


def github_output_is_bounded() -> None:
    reports = [noise.read_log("check_%02d" % i, LEAK_2 + VERBOSE + PORTRAIT) for i in range(40)]
    notices = noise.format_github(reports)
    check(len(notices) <= 8, "40 logs fit in a few notices, got %d" % len(notices))
    check(all(n.startswith("::notice title=") and len(n) < 4000 for n in notices), "well-formed and small")
    joined = "\n".join(notices)
    check(all(("check_%02d:" % i) in joined for i in range(40)), "no log is dropped from the notices")
    check("engine noise buckets::" in joined and "portrait_no_room 40" in joined, "bucket totals")
    markdown = "\n".join(noise.format_markdown(reports))
    check(markdown.count("| check_") == 40, "every log has a row")


def command_line() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "logs").mkdir()
        (root / "logs" / "probe_0_bare.log").write_text(LEAK_1 + "Leaked instance: Object:1\n")
        (root / "logs" / "camera_rig.log").write_text(LEAK_2 + VERBOSE)
        (root / "logs" / "notes.txt").write_text("WARNING: not a log\n")
        summary = root / "summary.md"
        summary.write_text("before\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = noise.main([str(root / "logs"), "--github", "--summary", str(summary)])
        text = out.getvalue()
        check(code == 0, "a report always exits 0")
        check("2 log(s)" in text, "only *.log files are read: " + text[:200])
        check(summary.read_text().startswith("before\n# Engine noise, attributed"), "summary appended")
        check("::notice title=leak probe ladder 1/1::probe_0_bare: leak 1, adds Object x1" in text,
              "ladder notice: " + text)
        check("::notice title=leaked at exit 1/1::camera_rig:" in text, "check leak notice")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = noise.main([str(root / "missing")])
        check(code == 0 and "No logs were found." in out.getvalue(), "no logs is said, not failed")


def main() -> int:
    leak_counts()
    verbose_detail()
    buckets_and_locations()
    ladder()
    github_output_is_bounded()
    command_line()
    if FAILURES:
        for failure in FAILURES:
            print("ENGINE_NOISE_REPORT_TEST_FAILURE: " + failure)
        print("%d of %d check(s) failed." % (len(FAILURES), CHECKS))
        return 1
    print("ENGINE_NOISE_REPORT_TEST_OK: %d checks." % CHECKS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
