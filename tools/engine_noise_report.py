#!/usr/bin/env python3
"""Attribute the engine's ERROR/WARNING lines in a set of headless Godot logs (issue #67).

`godot-ci.yml` already counts these lines per check ("engine noise (camera_rig): 1 ERROR,
1 WARNING"), and stops there on purpose: a count is not a judgement. Issue #67 asks for the
next step for the one line that shows up in most checks - "N ObjectDB instances were leaked
at exit" - a minimal reproduction, a `--verbose` log and the *source* of the objects, and
for no warning to be hidden on the way. This tool is the reading half of that. It never
changes a verdict and never removes a line; it puts every line in a named bucket, with the
evidence that put it there, so "is this noise or a bug?" has an answer in the run instead
of in somebody's memory.

What it reads, per log:

- every engine `ERROR:` / `WARNING:` line (a `SCRIPT ERROR` is counted as well, but it is
  already a failure in `tools/ci_run_check.sh`, so it is reported, not attributed), with
  the `at: function (file:line)` line the engine prints under it;
- `--verbose` leak detail: `Leaked instance: Class:id - Node path: ...` /
  `- Resource path: ...` (ObjectDB), `Resource still in use: res://... (Class)`, and
  `Orphan StringName: ...`.

What it writes:

- one row per log: counts, the leak count, and which leaked classes the verbose detail
  named;
- the buckets (`RULES` below): each one says what the line is and why it is filed there,
  and lists the logs it came from;
- for logs whose name starts with `probe_` (the ladder in `tests/engine_hygiene/`), the
  instances each rung adds over the one below it - the minimal reproduction, read off the
  logs rather than claimed;
- an `unclassified` bucket with the first occurrences, which is where a new problem appears.

Usage:

    python3 tools/engine_noise_report.py ci-logs/            # Markdown on stdout
    python3 tools/engine_noise_report.py ci-logs/ --github   # plus ::notice lines
    python3 tools/engine_noise_report.py a.log b.log --summary "$GITHUB_STEP_SUMMARY"

Standard library only.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import Counter
from dataclasses import dataclass, field

ENGINE_LINE_RE = re.compile(r"^\s*(ERROR|WARNING|SCRIPT ERROR): (.*)$")
AT_RE = re.compile(r"^\s+at: (.*)$")
OBJECTDB_RE = re.compile(r"(?:(\d+) )?ObjectDB instances? (?:were |was )?leaked at exit")
LEAKED_INSTANCE_RE = re.compile(
    r"^Leaked instance: ([A-Za-z0-9_]+):(\d+)"
    # A node outside the tree prints an empty path, and the line is stripped, so the
    # space after the colon is optional.
    r"(?: - Node path:\s*(.*?))?(?: - Resource path:\s*(.*?))?\s*$"
)
RESOURCE_IN_USE_RE = re.compile(r"^Resource still in use: (.*?) \(([A-Za-z0-9_]+)\)\s*$")
ORPHAN_STRINGNAME_RE = re.compile(r"^Orphan StringName: (.*)$")


@dataclass(frozen=True)
class Rule:
    bucket: str
    pattern: re.Pattern
    meaning: str


# Ordered: the first match files a line. Each `meaning` is what the evidence in this
# repository says the line is; a rule that is only a guess does not belong here.
RULES: tuple[Rule, ...] = (
    Rule(
        "objectdb_leak",
        re.compile(r"ObjectDB instances? (?:were |was )?leaked at exit"),
        "Objects still alive when the engine shut down. The verbose detail below names them; "
        "the probe ladder says which step of a test's set-up adds them.",
    ),
    Rule(
        "resources_in_use",
        re.compile(r"resources? still in use at exit"),
        "Resources still referenced at shutdown - usually held by a leaked object above.",
    ),
    Rule(
        "rid_leak",
        re.compile(r"RIDs? of type .* (?:was|were) leaked|RID allocations of type"),
        "Server-side resources (meshes, textures, physics bodies) never freed; follows a "
        "leaked owner.",
    ),
    Rule(
        "portrait_no_room",
        re.compile(r"DialoguePanel portrait: .* px of the .* px band are left"),
        "The dialogue panel declining a portrait it has no room for (#167/#183). The band "
        "is 57 px because the check runs in the headless default 64x64 window and never "
        "sizes it; the panel is doing what it should at that size. Reported, not hidden.",
    ),
    Rule(
        "harness_teardown",
        re.compile(r"TestHarness:"),
        "The shared test harness reporting its own set-up problem.",
    ),
    Rule(
        "save_refusal",
        re.compile(r"^Save: |OpeningSequence: the save was refused"),
        "The save system refusing or reporting a file - in a check, usually on purpose "
        "(save_validation, save_quit). Judge it against the check that printed it.",
    ),
)


@dataclass
class LogReport:
    name: str
    errors: int = 0
    warnings: int = 0
    script_errors: int = 0
    leak_count: int | None = None
    leaked: Counter = field(default_factory=Counter)  # "Class @ path" -> count
    resources_in_use: Counter = field(default_factory=Counter)
    orphan_stringnames: int = 0
    buckets: Counter = field(default_factory=Counter)
    unclassified: list[str] = field(default_factory=list)
    locations: dict[str, Counter] = field(default_factory=dict)  # bucket -> "at:" lines


def _instance_key(match: re.Match) -> str:
    cls = match.group(1)
    node_path = (match.group(3) or "").strip()
    resource_path = (match.group(4) or "").strip()
    if node_path:
        return "%s @ %s" % (cls, node_path)
    if resource_path:
        return "%s @ %s" % (cls, resource_path)
    return cls


def classify(message: str) -> str:
    for rule in RULES:
        if rule.pattern.search(message):
            return rule.bucket
    return "unclassified"


def read_log(name: str, text: str) -> LogReport:
    report = LogReport(name)
    lines = text.splitlines()
    for index, line in enumerate(lines):
        engine = ENGINE_LINE_RE.match(line)
        if engine:
            kind, message = engine.group(1), engine.group(2).strip()
            if kind == "SCRIPT ERROR":
                report.script_errors += 1
                continue
            if kind == "ERROR":
                report.errors += 1
            else:
                report.warnings += 1
            bucket = classify(message)
            report.buckets[bucket] += 1
            if bucket == "unclassified" and len(report.unclassified) < 5:
                report.unclassified.append("%s: %s" % (kind, message[:240]))
            if index + 1 < len(lines):
                at = AT_RE.match(lines[index + 1])
                if at:
                    report.locations.setdefault(bucket, Counter())[at.group(1).strip()] += 1
            leak = OBJECTDB_RE.search(message)
            if leak:
                report.leak_count = int(leak.group(1)) if leak.group(1) else -1
            continue
        instance = LEAKED_INSTANCE_RE.match(line.strip())
        if instance:
            report.leaked[_instance_key(instance)] += 1
            continue
        resource = RESOURCE_IN_USE_RE.match(line.strip())
        if resource:
            report.resources_in_use["%s (%s)" % (resource.group(1), resource.group(2))] += 1
            continue
        if ORPHAN_STRINGNAME_RE.match(line.strip()):
            report.orphan_stringnames += 1
    return report


def collect(paths: list[str]) -> list[LogReport]:
    files: list[str] = []
    for path in paths:
        if os.path.isdir(path):
            files += sorted(
                os.path.join(path, name) for name in os.listdir(path) if name.endswith(".log")
            )
        elif os.path.isfile(path):
            files.append(path)
    reports = []
    for path in files:
        with open(path, encoding="utf-8", errors="replace") as handle:
            name = os.path.basename(path)
            reports.append(read_log(name[: -len(".log")] if name.endswith(".log") else name, handle.read()))
    return reports


# --- The probe ladder -------------------------------------------------------


def probe_ladder(reports: list[LogReport]) -> list[tuple[str, int | None, Counter, Counter]]:
    """`(name, leak_count, instances, added_over_previous_rung)` for the `probe_*` logs,
    in name order (the probes are numbered so that order is the order of the ladder)."""
    rungs = sorted((r for r in reports if r.name.startswith("probe_")), key=lambda r: r.name)
    ladder = []
    previous: Counter = Counter()
    for rung in rungs:
        added = rung.leaked - previous
        ladder.append((rung.name, rung.leak_count, rung.leaked, added))
        previous = rung.leaked
    return ladder


# --- Output -----------------------------------------------------------------


def _leak_text(count: int | None) -> str:
    if count is None:
        return "0"
    return "yes (count not printed)" if count < 0 else str(count)


def format_markdown(reports: list[LogReport]) -> list[str]:
    lines = ["# Engine noise, attributed", ""]
    if not reports:
        return lines + ["No logs were found.", ""]
    total = Counter()
    for report in reports:
        total.update(report.buckets)
    lines += [
        "%d log(s); %d ERROR, %d WARNING, %d SCRIPT ERROR line(s)." % (
            len(reports), sum(r.errors for r in reports), sum(r.warnings for r in reports),
            sum(r.script_errors for r in reports),
        ),
        "",
        "| Log | ERROR | WARNING | SCRIPT ERROR | ObjectDB leak | Leaked classes (verbose) |",
        "|---|---:|---:|---:|---|---|",
    ]
    for report in reports:
        classes = Counter()
        for key, count in report.leaked.items():
            classes[key.split(" @ ")[0]] += count
        lines.append("| %s | %d | %d | %d | %s | %s |" % (
            report.name, report.errors, report.warnings, report.script_errors,
            _leak_text(report.leak_count),
            ", ".join("%s x%d" % item for item in sorted(classes.items())) or "-",
        ))
    lines.append("")

    ladder = probe_ladder(reports)
    if ladder:
        lines += [
            "## Minimal reproduction (probe ladder)",
            "",
            "Each rung does one more thing than the one above it; *added* is what that "
            "step leaves alive at exit.",
            "",
            "| Probe | Leak | Added over the rung above |",
            "|---|---|---|",
        ]
        for name, count, _instances, added in ladder:
            lines.append("| %s | %s | %s |" % (
                name, _leak_text(count),
                "<br>".join("`%s` x%d" % item for item in sorted(added.items())) or "-",
            ))
        lines.append("")

    leaked_everywhere = Counter()
    for report in reports:
        for key in report.leaked:
            leaked_everywhere[key] += 1
    if leaked_everywhere:
        lines += ["## Leaked instances across logs", "", "| Instance | In how many logs |", "|---|---:|"]
        for key, count in leaked_everywhere.most_common():
            lines.append("| `%s` | %d |" % (key, count))
        lines.append("")
    in_use = Counter()
    for report in reports:
        in_use.update(report.resources_in_use)
    if in_use:
        lines += ["## Resources still in use at exit", ""]
        lines += ["- `%s` x%d" % item for item in in_use.most_common(20)]
        lines.append("")

    lines += ["## Buckets", ""]
    meanings = {rule.bucket: rule.meaning for rule in RULES}
    for bucket, count in total.most_common():
        sources = sorted(r.name for r in reports if r.buckets.get(bucket))
        lines.append("### %s - %d line(s) in %d log(s)" % (bucket, count, len(sources)))
        lines.append("")
        if bucket in meanings:
            lines.append(meanings[bucket])
        else:
            lines.append("Not attributed yet. First occurrences:")
            for report in reports:
                for sample in report.unclassified:
                    lines.append("- `%s`: %s" % (report.name, sample.replace("|", "\\|")))
        locations = Counter()
        for report in reports:
            locations.update(report.locations.get(bucket, Counter()))
        if locations:
            lines.append("")
            lines.append("Printed at: " + "; ".join(
                "`%s` x%d" % item for item in locations.most_common(3)
            ))
        lines.append("")
        lines.append("Logs: " + ", ".join(sources))
        lines.append("")
    return lines


def _notice(title: str, message: str) -> str:
    message = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return "::notice title=%s::%s" % (title, message)


def _chunked(title: str, items: list[str], limit: int = 2400) -> list[str]:
    """Items packed into as few numbered notices as fit (a step keeps about ten)."""
    chunks: list[list[str]] = []
    size = 0
    for item in items:
        if not chunks or size + len(item) + 3 > limit:
            chunks.append([])
            size = 0
        chunks[-1].append(item)
        size += len(item) + 3
    return [
        _notice("%s %d/%d" % (title, index + 1, len(chunks)), " | ".join(chunk))
        for index, chunk in enumerate(chunks)
    ]


def format_github(reports: list[LogReport]) -> list[str]:
    """At most a handful of notices: the ladder, the leaked instances, the buckets."""
    rungs = [
        "%s: leak %s, adds %s" % (
            name, _leak_text(count),
            ", ".join("%s x%d" % item for item in sorted(added.items())) or "nothing",
        )
        for name, count, _instances, added in probe_ladder(reports)
    ]
    leaks = [
        "%s: %s" % (report.name, ", ".join("%s x%d" % item for item in report.leaked.most_common(8)))
        for report in reports
        if report.leaked and not report.name.startswith("probe_")
    ]
    total = Counter()
    for report in reports:
        total.update(report.buckets)
    unclassified = [
        "%s: %s" % (report.name, sample) for report in reports for sample in report.unclassified[:2]
    ]
    out = _chunked("leak probe ladder", rungs) + _chunked("leaked at exit", leaks)
    out.append(_notice(
        "engine noise buckets", ", ".join("%s %d" % item for item in total.most_common()) or "none"
    ))
    out += _chunked("unclassified engine lines", unclassified[:12])
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("paths", nargs="+", help="log files or directories of *.log")
    parser.add_argument("--github", action="store_true", help="also print GitHub annotations")
    parser.add_argument("--summary", help="append the Markdown to this file (a step summary)")
    args = parser.parse_args(argv)
    reports = collect(args.paths)
    markdown = format_markdown(reports)
    print("\n".join(markdown))
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as handle:
            handle.write("\n".join(markdown) + "\n")
    if args.github:
        print("\n".join(format_github(reports)))
    # A report, not a gate: the verdicts belong to `tools/ci_run_check.sh`.
    return 0


if __name__ == "__main__":
    sys.exit(main())
