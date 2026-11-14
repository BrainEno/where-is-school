#!/usr/bin/env python3
"""Carry the dialogue evidence frames from a CI run into `docs/screenshots/` (#186).

Actions does not commit frames back to Git (#88), and from some places the artifact store
cannot be reached at all - a download there ends in `EOF`. What can always be read is a
run's **annotations**, through the REST API. So the relay jobs of `Playthrough capture`
split the frames into annotation-sized parts, and this tool puts them back together:

``pack`` (in CI, after the captures)
    Reads the capture logs for their ``EVIDENCE {json}`` lines (printed by
    `tests/evidence_contract.gd`), checks that every wanted frame has both a record and a
    full-size JPEG, and writes into ``--out``: the JPEGs, ``frames.json`` (the records plus
    each file's SHA-256 and byte count, the commit and the run) and ``queue.txt`` - one
    line per part, ``<file> <i>/<n> <base64>``, with ``frames.json`` first. It prints the
    shard list for the publishing jobs (``--per-job`` parts each: GitHub keeps at most 50
    annotations per job).

``fetch`` (here, with `gh`)
    Lists the run's jobs, reads every ``relay <file> <i>/<n>`` notice, reassembles each
    file, and refuses any whose SHA-256 is not the one ``frames.json`` recorded - a part
    lost or reordered is caught, not committed. With ``--apply`` it writes the frames into
    `docs/screenshots/`, removes the PNGs they replace, and records them as current in
    `MANIFEST.json` through `tools/screenshot_evidence.apply_relay()`.

Usage:

    python3 tools/dialogue_evidence_relay.py pack --log opening.log --log ui.log \\
        --frames docs/screenshots --out "$RUNNER_TEMP/relay"
    python3 tools/dialogue_evidence_relay.py fetch --run 123456789            # verify only
    python3 tools/dialogue_evidence_relay.py fetch --run 123456789 --apply    # and write
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import screenshot_evidence  # noqa: E402  (the path has to be set up first)

REPOSITORY = "BrainEno/where-is-school"
WORKFLOW_NAME = "Playthrough capture"
# The frames the repository keeps as the picture of the opening line and the reading band.
WANTED_FRAMES = (
    "01_opening_line",
    "ui-dialogue-1280x720-en",
    "ui-dialogue-1280x720-zh",
    "ui-dialogue-1600x900-en",
    "ui-dialogue-1600x900-zh",
    "ui-dialogue-1920x1080-en",
    "ui-dialogue-1920x1080-zh",
)
PART_SIZE = 4000
PER_JOB = 45
INDEX_FILE = "frames.json"
TITLE_RE = re.compile(r"^relay (\S+) (\d+)/(\d+)$")


# --- pack ----------------------------------------------------------------------------


def evidence_records(log_paths: list[Path]) -> dict[str, dict]:
    """The last `EVIDENCE` record per frame stem across the logs."""
    records: dict[str, dict] = {}
    for path in log_paths:
        if not path.is_file():
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            at = line.find("EVIDENCE {")
            if at < 0:
                continue
            try:
                record = json.loads(line[at + len("EVIDENCE ") :])
            except json.JSONDecodeError:
                continue
            frame = str(record.get("frame", ""))
            stem = frame.rsplit(".", 1)[0] if frame.endswith((".png", ".jpg")) else frame
            if stem:
                records[stem] = record
    return records


def split_parts(name: str, data: bytes, part_size: int = PART_SIZE) -> list[str]:
    encoded = base64.b64encode(data).decode("ascii")
    count = max(1, math.ceil(len(encoded) / part_size))
    return [
        f"{name} {index + 1}/{count} {encoded[index * part_size : (index + 1) * part_size]}"
        for index in range(count)
    ]


def pack(
    log_paths: list[Path],
    frames_dir: Path,
    out: Path,
    *,
    wanted: tuple[str, ...] = WANTED_FRAMES,
    commit: str = "",
    run_id: int = 0,
    part_size: int = PART_SIZE,
    per_job: int = PER_JOB,
) -> tuple[list[str], list[int]]:
    """Returns (problems, shards). Nothing is written when there are problems."""
    records = evidence_records(log_paths)
    problems: list[str] = []
    files: list[tuple[str, bytes]] = []
    index: dict = {"commit": commit, "run_id": run_id, "frames": []}
    for stem in wanted:
        record = records.get(stem)
        jpeg = frames_dir / f"{stem}.jpg"
        if record is None:
            problems.append(f"{stem}: no EVIDENCE record in the capture logs")
            continue
        if not jpeg.is_file():
            problems.append(f"{stem}: {jpeg} was not written")
            continue
        data = jpeg.read_bytes()
        size = screenshot_evidence.image_size(jpeg)
        if size is None or list(size) != list(record.get("size", [])):
            problems.append(f"{stem}: the JPEG is {size}, the record says {record.get('size')}")
            continue
        files.append((jpeg.name, data))
        index["frames"].append(
            {
                "file": jpeg.name,
                "sha256": hashlib.sha256(data).hexdigest(),
                "bytes": len(data),
                "record": record,
            }
        )
    if problems:
        return problems, []
    out.mkdir(parents=True, exist_ok=True)
    index_bytes = json.dumps(index, ensure_ascii=False, sort_keys=True).encode("utf-8")
    (out / INDEX_FILE).write_bytes(index_bytes)
    lines = split_parts(INDEX_FILE, index_bytes, part_size)
    for name, data in files:
        (out / name).write_bytes(data)
        lines.extend(split_parts(name, data, part_size))
    (out / "queue.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
    shards = list(range(math.ceil(len(lines) / per_job)))
    return [], shards


# --- fetch ---------------------------------------------------------------------------


def gh_json(path: str) -> object:
    completed = subprocess.run(["gh", "api", path], check=True, capture_output=True)
    return json.loads(completed.stdout)


def run_annotations(run_id: int) -> tuple[dict, list[dict]]:
    run = gh_json(f"repos/{REPOSITORY}/actions/runs/{run_id}")
    jobs: list[dict] = []
    page = 1
    while True:
        batch = gh_json(f"repos/{REPOSITORY}/actions/runs/{run_id}/jobs?per_page=100&page={page}")
        jobs.extend(batch.get("jobs", []))
        if len(batch.get("jobs", [])) < 100:
            break
        page += 1
    annotations: list[dict] = []
    for job in jobs:
        page = 1
        while True:
            batch = gh_json(f"repos/{REPOSITORY}/check-runs/{job['id']}/annotations?per_page=100&page={page}")
            annotations.extend(batch)
            if len(batch) < 100:
                break
            page += 1
    return run, annotations


def reassemble(annotations: list[dict]) -> tuple[dict[str, bytes], list[str]]:
    """Files rebuilt from `relay <file> <i>/<n>` notices, and what is missing or malformed."""
    parts: dict[str, dict[int, str]] = {}
    totals: dict[str, int] = {}
    problems: list[str] = []
    for annotation in annotations:
        match = TITLE_RE.match(str(annotation.get("title", "")))
        if not match:
            continue
        name, index, total = match.group(1), int(match.group(2)), int(match.group(3))
        if totals.setdefault(name, total) != total:
            problems.append(f"{name}: parts disagree on their count ({totals[name]} and {total})")
        parts.setdefault(name, {})[index] = str(annotation.get("message", "")).strip()
    files: dict[str, bytes] = {}
    for name, total in sorted(totals.items()):
        missing = [index for index in range(1, total + 1) if index not in parts[name]]
        if missing:
            problems.append(f"{name}: {len(missing)} of {total} part(s) missing (first: {missing[0]})")
            continue
        try:
            files[name] = base64.b64decode("".join(parts[name][i] for i in range(1, total + 1)), validate=True)
        except ValueError as error:
            problems.append(f"{name}: the parts do not decode ({error})")
    return files, problems


def verify(files: dict[str, bytes]) -> tuple[dict | None, list[str]]:
    if INDEX_FILE not in files:
        return None, [f"{INDEX_FILE} was not relayed"]
    index = json.loads(files[INDEX_FILE].decode("utf-8"))
    problems = []
    for frame in index.get("frames", []):
        data = files.get(frame["file"])
        if data is None:
            problems.append(f"{frame['file']}: not relayed")
        elif hashlib.sha256(data).hexdigest() != frame["sha256"]:
            problems.append(f"{frame['file']}: SHA-256 differs from the one the capture recorded")
    return index, problems


def apply(index: dict, files: dict[str, bytes], *, run: dict, root: Path = ROOT) -> list[str]:
    shots = root / screenshot_evidence.SCREENSHOTS
    written: dict[str, str] = {}
    retire: dict[str, str] = {}
    for frame in index.get("frames", []):
        name = frame["file"]
        (shots / name).write_bytes(files[name])
        written[name] = frame["sha256"]
        old = name.rsplit(".", 1)[0] + ".png"
        if (shots / old).is_file():
            (shots / old).unlink()
            retire[old] = name
    manifest, problem = screenshot_evidence.load_manifest(root)
    if manifest is None:
        raise SystemExit(problem)
    changes = screenshot_evidence.apply_relay(
        manifest,
        [frame["record"] for frame in index.get("frames", [])],
        run_id=int(run["id"]),
        commit=str(run["head_sha"]),
        workflow=str(run.get("name", WORKFLOW_NAME)),
        files=written,
        retire=retire,
    )
    # A retired PNG may be named by a historical entry as the thing it was superseded by;
    # point those at the frame that exists now.
    for frame in manifest.get("frames", []):
        successor = frame.get("superseded_by")
        if successor in retire:
            frame["superseded_by"] = retire[successor]
    screenshot_evidence.write_manifest(root, manifest)
    return changes


# --- command line --------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    pack_parser = sub.add_parser("pack", help="split the captured frames into annotation parts (CI)")
    pack_parser.add_argument("--log", action="append", type=Path, default=[], required=True)
    pack_parser.add_argument("--frames", type=Path, required=True)
    pack_parser.add_argument("--out", type=Path, required=True)
    pack_parser.add_argument("--per-job", type=int, default=PER_JOB)
    fetch_parser = sub.add_parser("fetch", help="rebuild the frames from a run's annotations")
    fetch_parser.add_argument("--run", type=int, required=True)
    fetch_parser.add_argument("--apply", action="store_true", help="write them into docs/screenshots")
    args = parser.parse_args(argv)

    if args.command == "pack":
        problems, shards = pack(
            args.log,
            args.frames,
            args.out,
            # The workflow checks out the pull request's head (not the merge ref) and says
            # so here, so the frames name a commit that exists on the branch.
            commit=os.environ.get("RELAY_COMMIT") or os.environ.get("GITHUB_SHA", ""),
            run_id=int(os.environ.get("GITHUB_RUN_ID", "0") or 0),
            per_job=args.per_job,
        )
        for problem in problems:
            print(f"::error title=dialogue evidence relay::{problem}")
        if problems:
            return 1
        queue = (args.out / "queue.txt").read_text(encoding="ascii").splitlines()
        print(f"{len(queue)} part(s) in {len(shards)} shard(s) of {args.per_job}")
        output = os.environ.get("GITHUB_OUTPUT")
        if output:
            with open(output, "a", encoding="utf-8") as handle:
                handle.write(f"shards={json.dumps(shards)}\n")
                handle.write(f"parts={len(queue)}\n")
        return 0

    run, annotations = run_annotations(args.run)
    files, problems = reassemble(annotations)
    index, more = verify(files)
    problems.extend(more)
    for problem in problems:
        print(f"error: {problem}", file=sys.stderr)
    if index is None or problems:
        return 1
    for frame in index["frames"]:
        shows = frame["record"].get("shows", {})
        print(f"{frame['file']}: {frame['bytes']} bytes, {shows.get('locale')} \"{shows.get('text')}\"")
    if run.get("head_sha") and index.get("commit") and run["head_sha"] != index["commit"]:
        print(f"error: the frames say commit {index['commit']}, the run is {run['head_sha']}", file=sys.stderr)
        return 1
    if args.apply:
        for change in apply(index, files, run=run):
            print(change)
    return 0


if __name__ == "__main__":
    sys.exit(main())
