#!/usr/bin/env bash
# CI evidence only. Uses the current harness/scene in two real engine sessions. Changes
# only the selected baseline GLBs (and the lead's motion profile) between sessions; always
# restores the current runtime bytes.
# No checkout of another branch/revision, no offline rendering, no generated portrait.
# bash tools/capture_character_geometry.sh n 'face,hands,cloth' <prepared-baseline-dir>
set -euo pipefail

group=${1:?n, student or protagonist}
frames=${2-}
baseline=${3:?directory with selected .glb/.tres inputs and base-sha.txt}
declare -A models
motion=assets/characters/protagonist/protagonist_motion.tres
case "$group" in
  n|student)
    models=([n]=assets/models/teacher-n/teacher-n.glb [student]=assets/models/protagonist/protagonist.glb)
    motion= ;;
  protagonist) models=([protagonist]=assets/models/protagonist/Protagonist_Character.glb) ;;
  *) echo "unsupported geometry group: $group" >&2; exit 2 ;;
esac
for label in "${!models[@]}"; do
  test -s "$baseline/$label.glb"
  test -s "$baseline/$label.tres"
done
if [ -n "$motion" ]; then test -s "$baseline/protagonist_motion.tres"; fi
engine=${GODOT_BIN:-godot}
python=${EVIDENCE_PYTHON:-python3}
shots=docs/screenshots/character_integration
mkdir -p "$shots"
: > capture.log
vault=$(mktemp -d)
restore_models() {
  for label in "${!models[@]}"; do
    if [ -f "$vault/$label.glb" ]; then cp "$vault/$label.glb" "${models[$label]}"; fi
  done
  if [ -f "$vault/protagonist_motion.tres" ]; then cp "$vault/protagonist_motion.tres" "$motion"; fi
  if [ -f "$vault/cache-paths.txt" ]; then
    while IFS= read -r cache; do cp "$vault/cache/$cache" "$cache"; done < "$vault/cache-paths.txt"
  fi
  rm -rf "$vault"
}
trap restore_models EXIT
for label in "${!models[@]}"; do cp "${models[$label]}" "$vault/$label.glb"; done
if [ -n "$motion" ]; then cp "$motion" "$vault/protagonist_motion.tres"; fi
base_sha=$(cat "$baseline/base-sha.txt")
head_sha=$(git rev-parse HEAD)
engine_version=$("$engine" --version)
export GEOMETRY_BASE_SHA="$base_sha" GEOMETRY_HEAD_SHA="$head_sha" GEOMETRY_ENGINE="$engine_version"
export GEOMETRY_BASELINE="$baseline" GEOMETRY_VAULT="$vault" GEOMETRY_GROUP="$group"
# Record the actual inputs before any swap. This isolates asset changes in the head scene;
# it is explicitly NOT a historical whole-game build.
"$python" - "${!models[@]}" <<'PY'
import hashlib, json, os, sys
from pathlib import Path
base, head = Path(os.environ['GEOMETRY_BASELINE']), Path(os.environ['GEOMETRY_VAULT'])
group = os.environ['GEOMETRY_GROUP']
roles = sorted(sys.argv[1:])
looks = {
    'n': 'teacher_n/teacher_n_look.tres',
    'student': 'classroom_student/student_look.tres',
    'protagonist': 'protagonist/protagonist_look.tres',
}
def pair(before, after):
    return {k: hashlib.sha256(p.read_bytes()).hexdigest()
            for k, p in [('baseline_sha256', before), ('head_sha256', after)]}
inputs = 'GLB, look and motion profile' if group == 'protagonist' else 'GLB and look'
record = {
    'schema': 'where-is-school/character-geometry-evidence/1',
    'status': 'inputs-only; not a completed capture',
    'base_sha': os.environ['GEOMETRY_BASE_SHA'], 'code_head_sha': os.environ['GEOMETRY_HEAD_SHA'],
    'engine': os.environ['GEOMETRY_ENGINE'], 'method': 'gl_compatibility', 'driver': 'opengl3',
    'columns': [f'base {inputs}', f'head {inputs}'],
    'scene_camera_shader_pose_code': 'head in BOTH legs; held walk phases or idle/sit stills, NOT motion signoff',
    'models': {k: pair(base / (k + '.glb'), head / (k + '.glb')) for k in roles},
    'looks': {k: pair(base / (k + '.tres'), Path('assets/characters') / looks[k]) for k in roles},
}
if group == 'protagonist':
    name = 'protagonist_motion.tres'
    record['motion_profiles'] = {'protagonist': pair(base / name, head / name)}
Path(f'docs/screenshots/character_integration/geometry_comparison_{group}.json').write_text(
    json.dumps(record, indent=2) + '\n')
PY

capture_leg() {
  local variant=$1
  local args=("--group=$group" "--variants=$variant" --freeze-pose)
  if [ -n "$frames" ]; then args+=("--frames=$frames"); fi
  if [ "$variant" = baseline ]; then args+=("--baseline-dir=$baseline"); fi
  local status=0
  xvfb-run -a --server-args="-screen 0 1600x900x24" \
    "$engine" --path . --resolution 1600x900 --rendering-driver opengl3 \
    --script res://tests/capture_character_integration.gd -- "${args[@]}" \
    > "geometry-$variant.log" 2>&1 || status=$?
  # Keep every original log in the artifact. Only remove the single-column base64
  # previews from the aggregate; combined comparison sheets are published below.
  grep -v '^ARTSHEET: ' "geometry-$variant.log" >> capture.log || true
  cp "$shots/CHARACTER_INTEGRATION_$group.log" "$shots/CHARACTER_INTEGRATION_${group}_$variant.log" 2>/dev/null || true
  if [ "$status" -ne 0 ] || ! grep -q 'RESULT: SUCCESS' "geometry-$variant.log" \
      || grep -qE 'RESULT: FAILURE|SCRIPT ERROR|SHADER ERROR' "geometry-$variant.log"; then
    echo "Geometry $variant leg failed (exit $status)" >&2
    return 1
  fi
}

# Establish and preserve the current import cache too. Restoring only GLB bytes leaves
# the BASE .scn/.md5 active in a later non-editor run (or in the next group capture).
status=0
"$engine" --headless --path . --import > geometry-head-import.log 2>&1 || status=$?
cat geometry-head-import.log >> capture.log
if [ "$status" -ne 0 ] || grep -qE 'SCRIPT ERROR|Parse Error' geometry-head-import.log; then
  echo "Geometry current import failed (exit $status)" >&2
  exit 1
fi
"$python" - "${models[@]}" <<'PY_CACHE'
import os, re, shutil, sys
from pathlib import Path
vault = Path(os.environ['GEOMETRY_VAULT'])
paths = []
for model in sys.argv[1:]:
    sidecar = Path(model + '.import')
    match = re.search(r'^path="res://(\.godot/imported/[^/]+\.scn)"$', sidecar.read_text(), re.M)
    if match is None:
        raise SystemExit(f'no imported scene path in {sidecar}')
    for path in [sidecar, Path(match[1]), Path(match[1]).with_suffix('.md5')]:
        if not path.is_file():
            raise SystemExit(f'current imported asset is missing: {path}')
        target = vault / 'cache' / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        paths.append(path.as_posix())
(vault / 'cache-paths.txt').write_text('\n'.join(paths) + '\n')
PY_CACHE
capture_leg after
for label in "${!models[@]}"; do cp "$baseline/$label.glb" "${models[$label]}"; done
if [ -n "$motion" ]; then cp "$baseline/protagonist_motion.tres" "$motion"; fi
# A new engine process must actually import the changed files. Reusing the head's
# imported meshes would produce a material-only comparison and is forbidden here.
status=0
"$engine" --headless --path . --import > geometry-baseline-import.log 2>&1 || status=$?
cat geometry-baseline-import.log >> capture.log
if [ "$status" -ne 0 ] || grep -qE 'SCRIPT ERROR|Parse Error' geometry-baseline-import.log; then
  echo "Geometry baseline import failed (exit $status)" >&2
  exit 1
fi
capture_leg baseline

# Join only the already-rendered one-column PNG panels, never re-render a mesh offline.
"$python" - <<'PY' >> capture.log
import base64, hashlib, io, json, os, re
from pathlib import Path
from PIL import Image, ImageDraw
folder = Path('docs/screenshots/character_integration')
group = os.environ['GEOMETRY_GROUP']
# Read this run's declarations, not an unbounded glob that can reuse stale PNGs.
logs = {variant: Path(f'geometry-{variant}.log').read_text()
        for variant in ('baseline', 'after')}
def names(variant):
    found = re.findall(r'^ARTSHEET: (\S+)\.jpg ', logs[variant], re.M)
    suffix = '__' + variant
    if not found or any(not name.startswith(group + '_') or not name.endswith(suffix) for name in found):
        raise SystemExit(f'no valid {variant} panels were declared by this capture')
    return {name[:-len(suffix)] for name in found}
frames = names('baseline')
if frames != names('after'):
    raise SystemExit('base/current capture declared different frame sets')
manifest_path = folder / f'geometry_comparison_{group}.json'
record = json.loads(manifest_path.read_text())
record['capture_diagnostics'] = {
    variant: {
        'errors': len(re.findall(r'^ERROR:', text, re.M)),
        'warnings': len(re.findall(r'^WARNING:', text, re.M)),
        'leak_lines': len(re.findall(r'^.*(?:leaked|still in use at exit).*$', text, re.M | re.I)),
        'renderer_lines': re.findall(r'^CHARACTER_INTEGRATION renderer=.*$', text, re.M),
    } for variant, text in logs.items()
}
record['rendered_sheets'] = {}
# GitHub counts each 4000-character chunk separately. Rounding only the aggregate
# byte total down loses the last (often seated) panel. Keep the full PNG in the
# artifact; cap each annotation preview by a whole number of chunks instead.
share = (46 // len(frames)) * 4000
if not share:
    raise SystemExit('too many geometry panels for the comparison preview budget')
for frame in sorted(frames):
    left = folder / (frame + '__baseline.png')
    right = left.with_name(left.name.replace('__baseline.png', '__after.png'))
    if not right.is_file():
        raise SystemExit(f'missing current panel: {right.name}')
    with Image.open(left) as a, Image.open(right) as b:
        if a.size != b.size:
            raise SystemExit(f'mismatched camera panel sizes: {left.name}, {right.name}')
        sheet = Image.new('RGB', (a.width * 2 + 4, a.height + 20), '#15131b')
        sheet.paste(a, (0, 20)); sheet.paste(b, (a.width + 4, 20))
        text = ImageDraw.Draw(sheet)
        text.text((4, 4), 'BASE ' + os.environ['GEOMETRY_BASE_SHA'][:12], fill='white')
        text.text((a.width + 8, 4), 'HEAD ' + os.environ['GEOMETRY_HEAD_SHA'][:12], fill='white')
    name = left.stem.replace('__baseline', '__geometry_base_after')
    output = folder / (name + '.png')
    sheet.save(output)
    record['rendered_sheets'][output.name] = hashlib.sha256(output.read_bytes()).hexdigest()
    preview = sheet
    while True:
        for quality in (80, 72, 64, 56, 48, 40):
            buffer = io.BytesIO()
            preview.save(buffer, 'JPEG', quality=quality, optimize=True)
            encoded = base64.b64encode(buffer.getvalue()).decode('ascii')
            if len(encoded) <= share:
                break
        if len(encoded) <= share:
            break
        preview = preview.resize(tuple(max(1, int(v * .86)) for v in preview.size), Image.Resampling.LANCZOS)
    print(f'ARTSHEET: {name}.jpg {encoded}')
record['status'] = 'complete; static rendered comparisons, not motion or owner signoff'
manifest_path.write_text(json.dumps(record, indent=2) + '\n')
print(f"ARTNOTE: uses actual base/current {record['columns'][0][5:]}; head scene/camera/shader in both legs")
PY
