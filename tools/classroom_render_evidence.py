#!/usr/bin/env python3
"""Second witness for the classroom render gate (issue #150).

`tests/run_classroom_checks.sh --render-only` runs two real-renderer Godot scripts per
rendering method and leaves their evidence in one folder:

    <evidence>/ENGINE.txt                          godot --version
    <evidence>/classroom_pixels_<method>.log       full engine log of the wall pixel test
    <evidence>/classroom_capture_<method>.log      full engine log of the classroom capture
    <evidence>/pixels-<method>/RESULT.txt          the pixel test's own record and verdict
    <evidence>/pixels-<method>/{reference,fader}.png   the raw 256 x 256 viewport frames
    <evidence>/capture-<method>/CAPTURE.txt        renderer, adapter, wall states, shot hashes
    <evidence>/capture-<method>/0N_*.png           the raw 1600 x 900 viewport frames

`run_check` already judges each script by its log. This tool judges the evidence itself,
without trusting any single line of it:

  * the renderer and driver Godot actually started (in RESULT.txt, CAPTURE.txt and the
    log) must be the ones the job asked for - Godot falls back from Vulkan to OpenGL on
    its own, and a Forward+ job measured on Compatibility is a failure, not a pass;
  * the engine must be 4.7.2 stable and the display must not be headless;
  * each script must have recorded `verdict=PASS` and printed `PASS:`, and no log may
    carry a failure, a script error, a parse error or a watchdog timeout;
  * every expected image must exist, decode, have the expected size and not be blank;
  * the wall is measured again from the saved PNGs with the test's own limits
    (centre 32 x 32 red mean; control within [0.1, 0.7]; |control - fader| <= 0.025),
    and must agree with the numbers the test reported;
  * each capture frame's SHA-256 must match the one the capture recorded.

`verify` writes VERDICT.txt and MANIFEST.json (head SHA, run, renderer, verdict, reasons,
and the SHA-256 of every file) into the evidence folder and exits 1 on any failure.
`summarize` takes the per-renderer verdict files and exits 1 unless every required
renderer is present and passed.

Standard library only: the CI image has no Pillow or NumPy, and the gate must not
depend on them. tests/classroom_render_evidence_test.py proves each failure is caught.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

# The limits of tests/classroom_wall_render_test.gd. They are copied, not invented here;
# tests/classroom_render_evidence_test.py fails if the GDScript ever disagrees with them.
CENTRE_START = 112
CENTRE_END = 144  # exclusive, as `range(112, 144)` in the test
MAX_ERROR = 0.025
REFERENCE_MIN = 0.1
REFERENCE_MAX = 0.7
# The blank-frame rule shared by both scripts: coarse brightness range below this.
BLANK_RANGE = 0.15
# How far the re-measured values may differ from the ones the test printed with %.5f.
AGREEMENT = 0.002

PIXEL_SIZE = (256, 256)
CAPTURE_SIZE = (1600, 900)
CAPTURE_SHOTS = (
    "01_gameplay.png",
    "02_wall_occlusion.png",
    "03_walls_restored.png",
    "04_full_classroom.png",
    "05_blackboard_platform_lectern.png",
    "06_double_doors.png",
    "07_two_windows_and_curtains.png",
    "08_twelve_student_desks.png",
)
EXPECTED_DRIVERS = {"forward_plus": "vulkan", "gl_compatibility": "opengl3"}
ENGINE_MARK = "4.7.2 stable"
# `godot --version` prints "4.7.2.stable.official.<hash>"; Engine.get_version_info().string,
# which the scripts record, reads "4.7.2-stable (official)". Both name the same build.
ENGINE_PATTERN = re.compile(r"(?<![\d.])4\.7\.2[.-]stable\b")
# Lines that make a log a failure whatever else it says (run_check's rule, plus the
# watchdog line, which a timed-out script prints before it quits).
LOG_FAILURE = re.compile(r"TEST FAILURE|TEST WATCHDOG|^FAIL:|SCRIPT ERROR|Parse Error", re.M)


class Evidence:
    """Collects reasons; a run passes only with none."""

    def __init__(self) -> None:
        self.reasons: list[str] = []
        self.facts: dict[str, str] = {}

    def fail(self, reason: str) -> None:
        self.reasons.append(reason)


# --- PNG --------------------------------------------------------------------------------


class PngError(ValueError):
    pass


def read_png(path: Path) -> tuple[int, int, int, bytes]:
    """Decodes an 8-bit, non-interlaced PNG. Returns (width, height, channels, rows) where
    `rows` is the unfiltered pixel data, row after row, `channels` bytes per pixel."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise PngError("not a PNG file")
    pos = 8
    width = height = channels = 0
    idat = bytearray()
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if len(body) != length:
            raise PngError("truncated chunk")
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, colour, _comp, _filter, interlace = struct.unpack(
                ">IIBBBBB", body
            )
            if depth != 8 or interlace != 0:
                raise PngError("only 8-bit non-interlaced PNGs are supported")
            channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(colour, 0)
            if channels == 0:
                raise PngError("unsupported colour type %d" % colour)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if width == 0 or height == 0 or not idat:
        raise PngError("no image data")
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as error:
        raise PngError("corrupt image data: %s" % error) from error
    stride = width * channels
    if len(raw) != height * (stride + 1):
        raise PngError("image data has the wrong length")
    out = bytearray(height * stride)
    previous = bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind = raw[start]
        line = bytearray(raw[start + 1:start + 1 + stride])
        if kind == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif kind == 2:
            line = bytearray((a + b) & 0xFF for a, b in zip(line, previous))
        elif kind == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif kind == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif kind != 0:
            raise PngError("unknown filter type %d" % kind)
        out[y * stride:(y + 1) * stride] = line
        previous = line
    return width, height, channels, bytes(out)


def centre_red_mean(width: int, channels: int, rows: bytes) -> float:
    """The test's measurement: mean red of the centre 32 x 32 block, in 0..1."""
    total = 0
    for y in range(CENTRE_START, CENTRE_END):
        base = y * width * channels
        for x in range(CENTRE_START, CENTRE_END):
            total += rows[base + x * channels]
    count = (CENTRE_END - CENTRE_START) ** 2
    return total / count / 255.0


def brightness_range(width: int, height: int, channels: int, rows: bytes) -> float:
    """Spread of block-mean brightness over a coarse 32 x 18 grid (0..1). A frame of one
    flat colour - black, a fade panel, an uncleared target - scores near zero. Each block
    is averaged from an even 6 x 6 lattice of its pixels, which is plenty for a mean."""
    columns, lines, lattice = 32, 18, 6
    colour = min(channels, 3)
    means = []
    for gy in range(lines):
        y0, y1 = gy * height // lines, max(gy * height // lines + 1, (gy + 1) * height // lines)
        for gx in range(columns):
            x0 = gx * width // columns
            x1 = max(x0 + 1, (gx + 1) * width // columns)
            total = samples = 0
            for sy in range(lattice):
                y = y0 + (y1 - y0) * (2 * sy + 1) // (2 * lattice)
                base = y * width * channels
                for sx in range(lattice):
                    x = x0 + (x1 - x0) * (2 * sx + 1) // (2 * lattice)
                    offset = base + x * channels
                    total += sum(rows[offset:offset + colour])
                    samples += colour
            means.append(total / samples / 255.0)
    return (max(means) - min(means)) if means else 0.0


# --- helpers ----------------------------------------------------------------------------


def read_text(path: Path, evidence: Evidence, label: str) -> str | None:
    if not path.is_file():
        evidence.fail("%s is missing (%s)" % (label, path.name))
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def key_values(text: str) -> dict[str, list[str]]:
    values: dict[str, list[str]] = {}
    for line in text.splitlines():
        if "=" in line and not line.startswith(" "):
            key, _, value = line.partition("=")
            values.setdefault(key.strip(), []).append(value.strip())
    return values


def first(values: dict[str, list[str]], key: str) -> str | None:
    found = values.get(key)
    return found[0] if found else None


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def check_log(path: Path, evidence: Evidence, label: str) -> str | None:
    text = read_text(path, evidence, label)
    if text is None:
        return None
    bad = LOG_FAILURE.findall(text)
    if bad:
        evidence.fail("%s reports %s" % (label, ", ".join(sorted(set(bad)))))
    if not re.search(r"^PASS:", text, re.M):
        evidence.fail("%s has no PASS verdict" % label)
    return text


def check_environment(values: dict[str, list[str]], evidence: Evidence, label: str,
                      method: str, driver: str) -> None:
    renderer = first(values, "renderer")
    actual_driver = first(values, "driver")
    if renderer != method:
        evidence.fail("%s ran on renderer %r, not %r" % (label, renderer, method))
    if actual_driver != driver:
        evidence.fail("%s ran on driver %r, not %r" % (label, actual_driver, driver))
    display = first(values, "display")
    if display is not None and display == "headless":
        evidence.fail("%s ran headless; that draws nothing" % label)
    engine = first(values, "engine") or ""
    if not ENGINE_PATTERN.search(engine):
        evidence.fail("%s ran on engine %r, not Godot %s" % (label, engine, ENGINE_MARK))
    if not (first(values, "adapter") or "").strip():
        evidence.fail("%s recorded no video adapter" % label)


def load_image(path: Path, size: tuple[int, int], evidence: Evidence,
               label: str) -> tuple[int, int, int, bytes] | None:
    if not path.is_file():
        evidence.fail("%s is missing (%s)" % (label, path.name))
        return None
    try:
        image = read_png(path)
    except (PngError, OSError, struct.error) as error:
        evidence.fail("%s cannot be decoded: %s" % (label, error))
        return None
    if (image[0], image[1]) != size:
        evidence.fail("%s is %dx%d, not %dx%d" % (label, image[0], image[1], size[0], size[1]))
        return None
    spread = brightness_range(*image)
    evidence.facts["%s_range" % path.stem] = "%.5f" % spread
    if spread < BLANK_RANGE:
        evidence.fail("%s is blank (brightness range %.5f)" % (label, spread))
    return image


# --- the two scripts' evidence ----------------------------------------------------------


def verify_pixels(root: Path, method: str, driver: str, evidence: Evidence) -> None:
    log = check_log(root / ("classroom_pixels_%s.log" % method), evidence, "pixel test log")
    if log is not None:
        printed = re.search(r"^CLASSROOM_WALL_PIXELS renderer=(\S+)", log, re.M)
        if printed is None:
            evidence.fail("pixel test log has no CLASSROOM_WALL_PIXELS measurement")
        elif printed.group(1) != method:
            evidence.fail("pixel test log measured on %r, not %r" % (printed.group(1), method))
    folder = root / ("pixels-%s" % method)
    text = read_text(folder / "RESULT.txt", evidence, "pixel RESULT.txt")
    reported: dict[str, float] = {}
    if text is not None:
        values = key_values(text)
        check_environment(values, evidence, "pixel test", method, driver)
        verdict = first(values, "verdict")
        if verdict != "PASS":
            evidence.fail("pixel RESULT.txt verdict is %r, not PASS" % verdict)
        for failure in values.get("failure", []):
            evidence.fail("pixel test: %s" % failure)
        for key in ("reference", "actual", "error"):
            raw = first(values, key)
            try:
                reported[key] = float(raw) if raw is not None else float("nan")
            except ValueError:
                reported[key] = float("nan")
            if reported[key] != reported[key]:
                evidence.fail("pixel RESULT.txt has no numeric %s" % key)
        for key in ("engine", "adapter", "adapter_vendor", "adapter_api", "display"):
            if first(values, key) is not None:
                evidence.facts["pixels_" + key] = first(values, key) or ""
    reference = load_image(folder / "reference.png", PIXEL_SIZE, evidence, "reference.png")
    fader = load_image(folder / "fader.png", PIXEL_SIZE, evidence, "fader.png")
    if reference is None or fader is None:
        return
    expected = centre_red_mean(reference[0], reference[2], reference[3])
    actual = centre_red_mean(fader[0], fader[2], fader[3])
    error = abs(expected - actual)
    evidence.facts.update(
        measured_reference="%.5f" % expected,
        measured_actual="%.5f" % actual,
        measured_error="%.5f" % error,
    )
    if expected < REFERENCE_MIN or expected > REFERENCE_MAX:
        evidence.fail(
            "re-measured control %.5f is outside [%.1f, %.1f]" % (expected, REFERENCE_MIN, REFERENCE_MAX)
        )
    if error > MAX_ERROR:
        evidence.fail(
            "re-measured fader wall differs from the 18%% control by %.5f (> %.3f)" % (error, MAX_ERROR)
        )
    for key, value in (("reference", expected), ("actual", actual), ("error", error)):
        if key in reported and reported[key] == reported[key] and abs(reported[key] - value) > AGREEMENT:
            evidence.fail(
                "the test reported %s=%.5f but the saved frames measure %.5f" % (key, reported[key], value)
            )


def verify_capture(root: Path, method: str, driver: str, evidence: Evidence) -> None:
    check_log(root / ("classroom_capture_%s.log" % method), evidence, "capture log")
    folder = root / ("capture-%s" % method)
    text = read_text(folder / "CAPTURE.txt", evidence, "CAPTURE.txt")
    recorded: dict[str, str] = {}
    if text is not None:
        values = key_values(text)
        # The capture writes "engine=... renderer=... display=..." on one line.
        merged: dict[str, list[str]] = {}
        for line in text.splitlines():
            for key, value in re.findall(r"(\w+)=(\S+)", line):
                if key in ("engine", "renderer", "display"):
                    merged.setdefault(key, []).append(value)
        for key in ("adapter", "driver", "verdict"):
            if key in values:
                merged[key] = values[key]
        check_environment(merged, evidence, "capture", method, driver)
        verdict = first(merged, "verdict")
        if verdict != "PASS":
            evidence.fail("CAPTURE.txt verdict is %r, not PASS" % verdict)
        for failure in values.get("failure", []):
            evidence.fail("capture: %s" % failure)
        for name, digest in re.findall(r"shot=(\S+) sha256=([0-9a-f]{64})", text):
            recorded[name] = digest
    for name in CAPTURE_SHOTS:
        path = folder / name
        if load_image(path, CAPTURE_SIZE, evidence, "capture %s" % name) is None:
            continue
        digest = recorded.get(name)
        if digest is None:
            evidence.fail("CAPTURE.txt records no hash for %s" % name)
        elif digest != sha256(path):
            evidence.fail("%s does not match the hash the capture recorded" % name)


def verify_engine(root: Path, evidence: Evidence) -> None:
    text = read_text(root / "ENGINE.txt", evidence, "ENGINE.txt")
    if text is not None:
        evidence.facts["engine_version"] = text.strip().splitlines()[0] if text.strip() else ""
        if not ENGINE_PATTERN.search(text):
            evidence.fail("ENGINE.txt is %r, not Godot %s" % (text.strip(), ENGINE_MARK))


def git_head(root: Path) -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def verify(args: argparse.Namespace) -> int:
    root = Path(args.dir)
    method = args.method
    driver = args.driver or EXPECTED_DRIVERS.get(method, "")
    evidence = Evidence()
    if method not in EXPECTED_DRIVERS:
        evidence.fail("unknown rendering method %r" % method)
    if not root.is_dir():
        evidence.fail("evidence folder %s does not exist" % root)
    else:
        verify_engine(root, evidence)
        verify_pixels(root, method, driver, evidence)
        verify_capture(root, method, driver, evidence)
    checked_out = args.checked_out_sha or git_head(Path.cwd())
    if args.head_sha and checked_out and checked_out != args.head_sha:
        evidence.fail("evidence was produced from %s, not the PR head %s" % (checked_out, args.head_sha))
    verdict = "PASS" if not evidence.reasons else "FAIL"
    if root.is_dir():
        lines = ["method=%s" % method, "driver=%s" % driver, "verdict=%s" % verdict]
        lines += ["%s=%s" % item for item in sorted(evidence.facts.items())]
        lines += ["reason=%s" % reason for reason in evidence.reasons]
        (root / "VERDICT.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
        files = []
        for path in sorted(p for p in root.rglob("*") if p.is_file()):
            if path.name == "MANIFEST.json":
                continue
            files.append({
                "path": path.relative_to(root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            })
        manifest = {
            "issue": 150,
            "rendering_method": method,
            "rendering_driver": driver,
            "verdict": verdict,
            "reasons": evidence.reasons,
            "measurements": evidence.facts,
            "head_sha": args.head_sha,
            "checked_out_sha": checked_out,
            "base_sha": args.base_sha,
            "repository": os.environ.get("GITHUB_REPOSITORY", ""),
            "workflow": os.environ.get("GITHUB_WORKFLOW", ""),
            "run_id": os.environ.get("GITHUB_RUN_ID", ""),
            "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", ""),
            "event": os.environ.get("GITHUB_EVENT_NAME", ""),
            "note": "Linux software rendering (Mesa) under Xvfb. Not Windows/RTX hardware "
                    "visual or performance acceptance.",
            "files": files,
        }
        (root / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("classroom render evidence (%s): %s" % (method, verdict))
    for key, value in sorted(evidence.facts.items()):
        print("  %s = %s" % (key, value))
    # One annotation with the facts, so the run page shows which device and numbers the
    # verdict is about without downloading the artifact.
    summary = "; ".join("%s=%s" % item for item in sorted(evidence.facts.items()))
    print("::notice title=classroom render evidence (%s): %s::%s"
          % (method, verdict, summary.replace("\n", " ") or "no facts recorded"))
    for reason in evidence.reasons:
        print("::error title=classroom render evidence (%s)::%s" % (method, reason))
    return 0 if verdict == "PASS" else 1


def summarize(args: argparse.Namespace) -> int:
    """Every required renderer must have at least one VERDICT.txt, and all of them PASS."""
    found: dict[str, list[str]] = {}
    for item in args.verdicts:
        path = Path(item)
        if not path.is_file():
            print("::error title=classroom render verdict::%s is missing" % item)
            continue
        values = key_values(path.read_text(encoding="utf-8", errors="replace"))
        found.setdefault(first(values, "method") or "", []).append(first(values, "verdict") or "")
    status = 0
    required = [method.strip() for method in args.require.split(",") if method.strip()]
    if not required:
        print("::error title=classroom render verdict::--require names no renderer")
        return 1
    for method in required:
        verdicts = found.get(method, [])
        if not verdicts:
            print("::error title=classroom render verdict::no evidence verdict for %s" % method)
            status = 1
        elif any(verdict != "PASS" for verdict in verdicts):
            print("::error title=classroom render verdict::%s verdict is %s" % (method, ",".join(verdicts)))
            status = 1
        else:
            print("%s: PASS" % method)
    return status


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    one = sub.add_parser("verify", help="verify one renderer's evidence folder")
    one.add_argument("--dir", required=True)
    one.add_argument("--method", required=True)
    one.add_argument("--driver", default="")
    one.add_argument("--head-sha", default="")
    one.add_argument("--base-sha", default="")
    one.add_argument("--checked-out-sha", default="")
    one.set_defaults(func=verify)
    many = sub.add_parser("summarize", help="require a PASS verdict from every renderer")
    # One comma-separated value, not nargs="+": a list option would swallow the verdict
    # paths that follow it and leave nothing to check.
    many.add_argument("--require", default="forward_plus,gl_compatibility",
                      help="comma-separated renderers that must each have a PASS verdict")
    many.add_argument("verdicts", nargs="*")
    many.set_defaults(func=summarize)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
