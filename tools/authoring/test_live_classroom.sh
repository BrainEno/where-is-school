#!/usr/bin/env bash
# Run only on disposable copies of the same sources. Never replace this checkout's dialogue.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 || -z "$1" || ( $# -eq 2 && $2 != --render ) ]]; then
  echo 'Usage: bash tools/authoring/test_live_classroom.sh EMPTY_WORK_DIR [--render]' >&2
  exit 2
fi
cd "$(dirname "$0")/../.."
repo="$PWD"
mkdir -p -- "$1"
work="$(cd -- "$1" && pwd -P)"
if [[ -n "$(find "$work" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo 'The classroom evidence directory must be empty.' >&2
  exit 2
fi
export XDG_DATA_HOME="$work/user"
export XDG_CONFIG_HOME="$work/config"
export WIS_TEST_NATIVE_ZIP="$work/classroom-candidate.zip"
export LIBGL_ALWAYS_SOFTWARE=1
normal="$XDG_DATA_HOME/godot/app_userdata/where-is-school"
mkdir -p -- "$normal"
printf '%s\n' 'ordinary save fixture: must not be read, reset or replaced by author mode' > "$normal/save.json"
printf '%s\n' 'ordinary read log fixture: must not be quarantined or replaced by author mode' > "$normal/read_log.json"
sha256sum "$normal/save.json" "$normal/read_log.json" > "$work/normal-profile.sha256"
python3 tools/authoring_build.py --prepare-only --output "$work/author"
baseline="$(git rev-parse --verify "${WIS_CLASSROOM_BASE:-HEAD}^{commit}")"
echo "Native replacement reader: $baseline"
mkdir -p "$work/clean"
git archive "$baseline" -- assets data scenes scripts addons project.godot export_presets.cfg default_bus_layout.tres \
  | tar -xf - -C "$work/clean"
for tree in "$work/author" "$work/clean"; do
  mkdir -p "$tree/tests"
  cp tests/{test_harness,authoring_live_classroom_test}.gd "$tree/tests/"
done
(cd "$work/author" && bash "$repo/tools/ci_import_godot.sh" "$work/author-import")

assert_log() {
  local log="$1" status="$2" marker="$3"
  if (( status != 0 )) || grep -qE 'SCRIPT ERROR|Parse Error|ObjectDB instances leaked|^FAIL:' "$log" || ! grep -Fq "$marker" "$log"; then
    echo "::error title=Live author classroom::See ${log##*/} (exit $status)"
    # The annotation above cannot link anywhere in CI; carry the actual verdict lines into
    # the annotation stream, or a red run is unreadable from the checks page alone.
    grep -m 8 -E 'SCRIPT ERROR|Parse Error|TEST FAILURE|^FAIL:' "$log" |
      while IFS= read -r line; do
        printf '::error title=Live author classroom::%s\n' "$line"
      done || true
    return 1
  fi
}
result=0
if [[ ${2:-} == --render ]]; then
  timeout 160 xvfb-run -a --server-args="-screen 0 1600x900x24" godot --rendering-driver opengl3 \
    --path "$work/author" --script res://tests/authoring_live_classroom_test.gd |& tee "$work/live-desktop.log" || result=$?
else
  timeout 160 godot --headless --path "$work/author" --script res://tests/authoring_live_classroom_test.gd \
    |& tee "$work/live-desktop.log" || result=$?
fi
assert_log "$work/live-desktop.log" "$result" 'PASS: same classroom cursor edits'
sha256sum -c "$work/normal-profile.sha256"
[[ $(find "$normal" -mindepth 1 | wc -l) -eq 2 ]]
result=0
timeout 160 godot --headless --path "$work/author" --script res://tests/authoring_live_classroom_test.gd -- --recovered \
  |& tee "$work/live-restart.log" || result=$?
assert_log "$work/live-restart.log" "$result" 'PASS: new author process recovered'
sha256sum -c "$work/normal-profile.sha256"
[[ $(find "$normal" -mindepth 1 | wc -l) -eq 2 ]]

# Validate the full pair and the fingerprints before replacing only the test copy.
python3 - "$WIS_TEST_NATIVE_ZIP" "$work/clean" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
from zipfile import ZipFile

archive, clean = map(Path, sys.argv[1:])
zh_path, en_path = (f"data/dialogue/{locale}/prologue.json" for locale in ("zh-CN", "en"))
paths = (zh_path, en_path)
meta = {"chapter-manifest.json", "pending_en.json", "BASE.sha256", "CANDIDATE.sha256"}
sha = lambda data: hashlib.sha256(data).hexdigest()
with ZipFile(archive) as z:
    assert {info.filename for info in z.infolist() if not info.is_dir()} == {*paths, *meta}
    manifest = json.loads(z.read("chapter-manifest.json"))
    assert manifest["format"] == "where-is-school/chapter-candidate" and manifest["version"] == 1
    assert manifest["status"] == "review_only" and manifest["chapter"] == "prologue"
    original = {name: (clean / name).read_bytes() for name in paths}
    copies = {name: z.read(name) for name in paths}
    for data, field, sidecar in ((original, "base_sha256", "BASE.sha256"),
                                 (copies, "candidate_sha256", "CANDIDATE.sha256")):
        hashes = {name: sha(content) for name, content in data.items()}
        assert manifest[field] == hashes
        assert z.read(sidecar).decode() == "".join(f"{hashes[name]}  {name}\n" for name in paths)
    assert len(json.loads(z.read("pending_en.json"))) == manifest["pending_en"] == 9
    assert all("未应用输入应跨进程保留".encode() not in z.read(path) for path in (*paths, "pending_en.json"))
    for name in paths:
        base = json.loads(original[name])
        candidate = json.loads(copies[name])
        assert candidate["chapter"] == "prologue" and type(candidate["format_version"]) is int, name
        b, c = base["conversations"], candidate["conversations"]
        assert set(b) == set(c) and all(b[k] == c[k] for k in b if k != "student")
        keep, edited = b["student"]["nodes"][0], c["student"]["nodes"][0]
        assert keep["choices"][0] == edited["choices"][0]  # the sibling's whole record
        assert keep["choices"][1]["next"] != edited["choices"][1]["next"]
        nodes = {row["id"]: row for row in c["student"]["nodes"]}
        first = nodes[edited["choices"][1]["next"]]
        new_choices = nodes[first["next"]]["choices"]
        assert len(new_choices) == 4 and new_choices[3]["next"] == "st_quiet"
        if name == en_path:
            assert keep["text"] == edited["text"]  # the changed old line's translation is kept
    for name in paths:
        (clean / name).write_bytes(copies[name])
print("PASS: baseline fingerprints and native bilingual chapter contents")
PY
(cd "$work/clean" && bash "$repo/tools/ci_import_godot.sh" "$work/clean-import")
result=0
XDG_DATA_HOME="$work/clean-user" timeout 160 godot --headless --path "$work/clean" \
  --script res://tests/authoring_live_classroom_test.gd -- --imported-chapter |& tee "$work/live-replacement.log" || result=$?
assert_log "$work/live-replacement.log" "$result" 'PASS: native chapter loads with authoring off'
result=0
XDG_DATA_HOME="$work/touch-user" WIS_TEST_NATIVE_ZIP="$work/touch-candidate.zip" timeout 160 godot --headless \
  --path "$work/author" --script res://tests/authoring_live_classroom_test.gd -- --mobile-preview \
  |& tee "$work/live-touch.log" || result=$?
assert_log "$work/live-touch.log" "$result" 'PASS: same classroom cursor edits'
git diff --exit-code -- data/dialogue
