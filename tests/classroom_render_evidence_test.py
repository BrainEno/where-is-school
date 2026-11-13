#!/usr/bin/env python3
"""The classroom render gate must not go green on bad evidence (issue #150).

tools/classroom_render_evidence.py is the second witness behind the Forward+ and
Compatibility wall-pixel jobs. Every case here starts from one complete, passing evidence
folder built in a temporary directory (synthetic PNGs and logs shaped exactly like the
real scripts' output), breaks one thing, and requires the verdict to be FAIL. The first
case is the positive control: without it a verifier that fails everything would pass
this file.

Nothing here touches the repository's assets or res:// data; fixtures live in a
temporary directory that is removed afterwards. No engine is needed.

Usage: python3 tests/classroom_render_evidence_test.py
"""

from __future__ import annotations

import contextlib
import hashlib
import io
import re
import shutil
import struct
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import classroom_render_evidence as evidence  # noqa: E402

# What `godot --version` prints (ENGINE.txt) and what Engine.get_version_info().string
# reads inside the scripts (RESULT.txt, CAPTURE.txt).
ENGINE = "4.7.2.stable.official.0000000"
ENGINE_INFO = "4.7.2-stable (official)"
SHA = "0123456789abcdef0123456789abcdef01234567"


# --- synthetic frames -------------------------------------------------------------------


def png(width: int, height: int, pixel, path: Path) -> None:
    """Writes an RGBA PNG; `pixel(x, y)` returns (r, g, b). Small frames alternate filter 0
    and filter 1 rows so the decoder's filter handling is exercised; big ones use filter 0
    to keep this file quick."""
    raw = bytearray()
    for y in range(height):
        row = bytearray()
        for x in range(width):
            r, g, b = pixel(x, y)
            row += bytes((r, g, b, 255))
        if y % 2 and width <= 256:
            filtered = bytearray(row)
            for i in range(len(row) - 1, 3, -1):
                filtered[i] = (row[i] - row[i - 4]) & 0xFF
            raw.append(1)
            raw += filtered
        else:
            raw.append(0)
            raw += row

    def chunk(kind: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 1))
        + chunk(b"IEND", b"")
    )


def wall(level: int):
    """The pixel fixture: black background, a white-ish wall of `level` in the middle."""
    def pixel(x: int, y: int):
        inside = 38 <= x < 218 and 38 <= y < 218
        value = level if inside else 0
        return value, value, value
    return pixel


def room(x: int, y: int):
    """A capture frame with real structure: floor, wall and a dark board."""
    if y < 300:
        return 200, 190, 170
    if 500 < x < 1100 and 350 < y < 600:
        return 30, 60, 40
    return 120, 120, 130


def flat(value: int):
    return lambda _x, _y: (value, value, value)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# --- one complete passing evidence folder ----------------------------------------------


def build(root: Path, method: str, driver: str) -> None:
    root.mkdir(parents=True)
    (root / "ENGINE.txt").write_text(ENGINE + "\n")
    pixels = root / ("pixels-%s" % method)
    pixels.mkdir()
    png(256, 256, wall(118), pixels / "reference.png")  # 118/255 = 0.46275
    png(256, 256, wall(117), pixels / "fader.png")      # 117/255 = 0.45882
    reference, actual = 118 / 255, 117 / 255
    error = abs(reference - actual)
    line = ("renderer=%s reference=%.5f actual=%.5f error=%.5f instance_transparency=0.8200 "
            "material_alpha=1.0000 material_mode=0" % (method, reference, actual, error))
    (pixels / "RESULT.txt").write_text("\n".join([
        "engine=" + ENGINE_INFO,
        "renderer=" + method,
        "driver=" + driver,
        "expected_renderer=" + method,
        "expected_driver=" + driver,
        "display=X11",
        "adapter=llvmpipe (LLVM 19.1.1, 256 bits)",
        "adapter_vendor=Mesa",
        "adapter_api=4.5",
        "reference_range=0.46275",
        "fader_range=0.45882",
        line,
        "reference=%.5f" % reference,
        "actual=%.5f" % actual,
        "error=%.5f" % error,
        "verdict=PASS",
    ]) + "\n")
    (root / ("classroom_pixels_%s.log" % method)).write_text(
        "Godot Engine v4.7.2.stable.official\n"
        "CLASSROOM_WALL_RENDERER method=%s driver=%s display=X11 adapter=llvmpipe\n"
        "CLASSROOM_WALL_PIXELS %s\n"
        "PASS: the real wall fade matches the single-alpha opacity control.\n" % (method, driver, line)
    )
    capture = root / ("capture-%s" % method)
    capture.mkdir()
    notes = [
        "engine=%s renderer=%s display=X11" % (ENGINE_INFO, method),
        "adapter=llvmpipe (LLVM 19.1.1, 256 bits)",
        "driver=%s" % driver,
        "viewport=(1600, 900)",
    ]
    for name in evidence.CAPTURE_SHOTS:
        shot = capture / name
        if name == evidence.CAPTURE_SHOTS[0]:
            png(1600, 900, room, shot)
        else:
            shutil.copyfile(capture / evidence.CAPTURE_SHOTS[0], shot)
        notes.append("shot=%s sha256=%s" % (name, sha256(shot)))
    notes.append("occlusion WallSouthLeft/MeshInstance3D instance_transparency=0.8200 "
                 "material_mode=0 alpha=1.0000 material=res://x.tres")
    notes.append("verdict=PASS")
    (capture / "CAPTURE.txt").write_text("\n".join(notes) + "\n")
    (root / ("classroom_capture_%s.log" % method)).write_text(
        "".join("CLASSROOM_CAPTURE %s\n" % note for note in notes)
        + "PASS: captured eight unmodified classroom viewport images and wall states.\n"
    )


def run_verify(folder: Path, method: str, head: str = SHA, checked_out: str = SHA) -> tuple[int, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = evidence.main([
            "verify", "--dir", str(folder), "--method", method,
            "--head-sha", head, "--checked-out-sha", checked_out,
        ])
    return code, out.getvalue()


def edit(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old not in text:
        raise AssertionError("fixture text %r not found in %s" % (old, path))
    path.write_text(text.replace(old, new))


# --- the cases --------------------------------------------------------------------------
# Each mutation takes (folder, method, driver); `expect` is the reason fragment that must
# appear, so a case cannot pass by failing for an unrelated reason.

P = "pixels-forward_plus"
C = "capture-forward_plus"
PLOG = "classroom_pixels_forward_plus.log"
CLOG = "classroom_capture_forward_plus.log"


def fallback_renderer(d: Path) -> None:
    # What Godot's own Vulkan -> OpenGL fallback would leave behind.
    edit(d / P / "RESULT.txt", "renderer=forward_plus\n", "renderer=gl_compatibility\n")
    edit(d / P / "RESULT.txt", "driver=vulkan", "driver=opengl3")


CASES = [
    ("a wrong renderer in the pixel record", "not 'forward_plus'", fallback_renderer),
    ("a wrong driver in the pixel record", "driver 'opengl3'",
     lambda d: edit(d / P / "RESULT.txt", "driver=vulkan", "driver=opengl3")),
    ("a pixel log measured on another renderer", "measured on 'gl_compatibility'",
     lambda d: edit(d / PLOG, "CLASSROOM_WALL_PIXELS renderer=forward_plus",
                    "CLASSROOM_WALL_PIXELS renderer=gl_compatibility")),
    ("a capture on another renderer", "capture ran on renderer 'gl_compatibility'",
     lambda d: edit(d / C / "CAPTURE.txt", "renderer=forward_plus", "renderer=gl_compatibility")),
    ("a headless display", "headless",
     lambda d: edit(d / P / "RESULT.txt", "display=X11", "display=headless")),
    ("another engine version", "not Godot 4.7.2 stable",
     lambda d: (d / "ENGINE.txt").write_text("4.6.1.stable.official\n")),
    ("a pixel test on another engine", "pixel test ran on engine",
     lambda d: edit(d / P / "RESULT.txt", "engine=4.7.2-stable", "engine=4.7.21-stable")),
    ("a capture on a pre-release engine", "capture ran on engine",
     lambda d: edit(d / C / "CAPTURE.txt", "engine=4.7.2-stable", "engine=4.7.2-rc1")),
    ("no recorded video adapter", "no video adapter",
     lambda d: edit(d / P / "RESULT.txt", "adapter=llvmpipe (LLVM 19.1.1, 256 bits)", "adapter=")),
    ("a missing PASS verdict in the pixel log", "pixel test log has no PASS verdict",
     lambda d: edit(d / PLOG, "PASS: the real wall", "the real wall")),
    ("a missing PASS verdict in the capture log", "capture log has no PASS verdict",
     lambda d: edit(d / CLOG, "PASS: captured", "captured")),
    ("verdict=FAIL in RESULT.txt", "verdict is 'FAIL'",
     lambda d: edit(d / P / "RESULT.txt", "verdict=PASS", "verdict=FAIL")),
    ("no verdict line in RESULT.txt", "verdict is None",
     lambda d: edit(d / P / "RESULT.txt", "verdict=PASS\n", "")),
    ("verdict=FAIL in CAPTURE.txt", "CAPTURE.txt verdict is 'FAIL'",
     lambda d: edit(d / C / "CAPTURE.txt", "verdict=PASS", "verdict=FAIL")),
    ("a script error in a passing log", "SCRIPT ERROR",
     lambda d: edit(d / PLOG, "PASS:", "SCRIPT ERROR: Invalid call. Nonexistent function\nPASS:")),
    ("a parse error in a passing log", "Parse Error",
     lambda d: edit(d / CLOG, "PASS:", "Parse Error at res://tests/x.gd:3\nPASS:")),
    ("a watchdog timeout", "TEST WATCHDOG",
     lambda d: edit(d / PLOG, "PASS:", "ERROR: TEST WATCHDOG: classroom_wall_render_test.gd exceeded 150 seconds\nPASS:")),
    ("a test failure line", "TEST FAILURE",
     lambda d: edit(d / CLOG, "PASS:", "ERROR: TEST FAILURE: 02_wall_occlusion.png is blank\nPASS:")),
    ("a black reference frame", "reference.png is blank",
     lambda d: png(256, 256, flat(0), d / P / "reference.png")),
    ("a black fader frame", "fader.png is blank",
     lambda d: png(256, 256, flat(0), d / P / "fader.png")),
    ("a uniformly grey frame", "fader.png is blank",
     lambda d: png(256, 256, flat(118), d / P / "fader.png")),
    ("a black capture frame", "02_wall_occlusion.png is blank",
     lambda d: png(1600, 900, flat(0), d / C / "02_wall_occlusion.png")),
    ("a missing fader frame", "fader.png is missing",
     lambda d: (d / P / "fader.png").unlink()),
    ("a missing capture frame", "08_twelve_student_desks.png is missing",
     lambda d: (d / C / "08_twelve_student_desks.png").unlink()),
    ("a missing RESULT.txt", "pixel RESULT.txt is missing",
     lambda d: (d / P / "RESULT.txt").unlink()),
    ("a missing pixel log", "pixel test log is missing",
     lambda d: (d / PLOG).unlink()),
    ("a corrupt PNG", "cannot be decoded",
     lambda d: (d / P / "reference.png").write_bytes(b"\x89PNG\r\n\x1a\nnot really")),
    ("a frame of the wrong size", "is 800x450, not 1600x900",
     lambda d: png(800, 450, room, d / C / "04_full_classroom.png")),
    # The 3.24% double-fade bug: control 0.46 vs a fader wall at 0.20 (error 0.27).
    ("a fader wall over the 0.025 limit", "differs from the 18% control",
     lambda d: png(256, 256, wall(50), d / P / "fader.png")),
    # Just over the limit: 118 vs 111 is 7/255 = 0.0275.
    ("a fader wall just over the limit", "differs from the 18% control",
     lambda d: png(256, 256, wall(111), d / P / "fader.png")),
    ("a control frame outside [0.1, 0.7]", "outside [0.1, 0.7]",
     lambda d: (png(256, 256, wall(230), d / P / "reference.png"),
                png(256, 256, wall(229), d / P / "fader.png"))),
    ("reported numbers the frames do not support", "but the saved frames measure",
     lambda d: edit(d / P / "RESULT.txt", "\nactual=0.45882", "\nactual=0.30000")),
    ("a capture frame that does not match its hash", "does not match the hash",
     lambda d: png(1600, 900, lambda x, y: room(x, 899 - y), d / C / "03_walls_restored.png")),
    ("a capture failure line", "capture: The renderer is",
     lambda d: edit(d / C / "CAPTURE.txt", "verdict=PASS",
                    "failure=The renderer is 'gl_compatibility', not the expected 'forward_plus'.\nverdict=PASS")),
]


def main() -> int:
    failures = []
    count = 0
    with tempfile.TemporaryDirectory() as temp:
        temp_root = Path(temp)
        good = temp_root / "good"
        build(good, "forward_plus", "vulkan")
        good_compat = temp_root / "good-compat"
        build(good_compat, "gl_compatibility", "opengl3")

        def check(label: str, ok: bool, detail: str = "") -> None:
            nonlocal count
            count += 1
            if ok:
                print("ok: %s" % label)
            else:
                failures.append(label)
                print("FAIL: %s %s" % (label, detail))

        # Positive controls: complete evidence passes, for both renderers.
        code, out = run_verify(good, "forward_plus")
        check("complete Forward+ evidence passes", code == 0, out)
        manifest = (good / "MANIFEST.json").read_text()
        check("the manifest names the head SHA and every file",
              SHA in manifest and "fader.png" in manifest and "08_twelve_student_desks.png" in manifest)
        code, out = run_verify(good_compat, "gl_compatibility")
        check("complete Compatibility evidence passes", code == 0, out)

        # A complete folder from the other renderer is not evidence for this one. (Copies,
        # so the good folders keep their PASS verdicts for the gate checks below.)
        # The file names follow the requested renderer, as the runner would name them;
        # everything inside is what a Compatibility run records.
        wrong = temp_root / "compat-as-forward"
        shutil.copytree(good_compat, wrong)
        for path in sorted(wrong.iterdir()):
            if "gl_compatibility" in path.name:
                path.rename(wrong / path.name.replace("gl_compatibility", "forward_plus"))
        code, out = run_verify(wrong, "forward_plus")
        check("Compatibility evidence cannot pass as Forward+", code == 1 and "not 'forward_plus'" in out, out)

        for index, (label, expect, mutate) in enumerate(CASES):
            folder = temp_root / ("case-%02d" % index)
            shutil.copytree(good, folder)
            for stale in ("VERDICT.txt", "MANIFEST.json"):
                (folder / stale).unlink(missing_ok=True)
            mutate(folder)
            code, out = run_verify(folder, "forward_plus")
            check("%s fails" % label, code == 1 and expect in out,
                  "(exit %d, wanted reason containing %r)\n%s" % (code, expect, out))
            check("%s records verdict=FAIL" % label,
                  "verdict=FAIL" in (folder / "VERDICT.txt").read_text())

        # A missing evidence folder (the job died before writing anything).
        code, out = run_verify(temp_root / "nothing", "forward_plus")
        check("a missing evidence folder fails", code == 1, out)
        # Evidence from another commit than the PR head.
        stale = temp_root / "stale-commit"
        shutil.copytree(good, stale)
        code, out = run_verify(stale, "forward_plus", head=SHA, checked_out="f" * 40)
        check("evidence from another commit fails", code == 1 and "not the PR head" in out, out)

        # The overall verdict: one failing renderer fails the whole gate.
        bad = temp_root / "case-00" / "VERDICT.txt"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            both = evidence.main(["summarize", str(good / "VERDICT.txt"), str(good_compat / "VERDICT.txt")])
            one_bad = evidence.main(["summarize", str(bad), str(good_compat / "VERDICT.txt")])
            one_missing = evidence.main(["summarize", str(good_compat / "VERDICT.txt")])
            missing_file = evidence.main(["summarize", str(good / "VERDICT.txt"), str(temp_root / "gone.txt")])
            mixed = evidence.main(["summarize", str(good / "VERDICT.txt"), str(bad),
                                   str(good_compat / "VERDICT.txt")])
        check("both renderers passing passes the gate", both == 0, out.getvalue())
        check("a failing Forward+ fails the gate", one_bad == 1)
        check("a renderer with no verdict fails the gate", one_missing == 1)
        check("a missing verdict file fails the gate", missing_file == 1)
        check("a PASS and a FAIL for one renderer fail the gate", mixed == 1)

    # The verifier's limits are the GDScript test's limits, not new ones.
    source = (ROOT / "tests" / "classroom_wall_render_test.gd").read_text()
    check_limits = [
        ("error limit", r"if error > ([0-9.]+):", evidence.MAX_ERROR),
        ("control lower bound", r"if expected < ([0-9.]+) or", evidence.REFERENCE_MIN),
        ("control upper bound", r"or expected > ([0-9.]+):", evidence.REFERENCE_MAX),
        ("blank range", r"const BLANK_RANGE := ([0-9.]+)", evidence.BLANK_RANGE),
        ("centre window start", r"for y in range\((\d+), \d+\):", evidence.CENTRE_START),
        ("centre window end", r"for y in range\(\d+, (\d+)\):", evidence.CENTRE_END),
    ]
    for label, pattern, value in check_limits:
        match = re.search(pattern, source)
        count += 1
        if match is None or float(match.group(1)) != float(value):
            failures.append(label)
            print("FAIL: the verifier's %s (%s) is not the GDScript's (%s)"
                  % (label, value, match.group(1) if match else "not found"))
        else:
            print("ok: the verifier's %s matches the GDScript (%s)" % (label, value))
    capture = (ROOT / "tests" / "capture_classroom_art.gd").read_text()
    count += 1
    if "if highest - lowest < 0.15:" not in capture:
        failures.append("capture blank rule")
        print("FAIL: capture_classroom_art.gd no longer uses the 0.15 blank rule")
    else:
        print("ok: the capture's blank rule is the verifier's (0.15)")
    count += 1
    missing_shots = [name for name in evidence.CAPTURE_SHOTS if '"%s"' % name not in capture]
    if missing_shots:
        failures.append("capture shot list")
        print("FAIL: the capture no longer writes %s" % ", ".join(missing_shots))
    else:
        print("ok: the capture writes the eight frames the verifier requires")

    print()
    print("%d check(s), %d failure(s)" % (count, len(failures)))
    if failures:
        return 1
    print("CLASSROOM_RENDER_EVIDENCE_TEST_OK: bad renderer, verdict, frame, pixel or timeout evidence cannot pass.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
