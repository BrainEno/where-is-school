#!/usr/bin/env bash
# CI evidence only. Uses the current harness/scene in two real engine sessions, swapping
# just the two baseline GLBs between sessions; always restores the current runtime bytes.
# No checkout of another branch/revision, no offline rendering, no generated portrait.
# bash tools/capture_character_geometry.sh n 'face,hands,cloth' <prepared-baseline-dir>
set -euo pipefail

group=${1:?n or student}
frames=${2-}
baseline=${3:?directory with n/student .glb/.tres and base-sha.txt}
case "$group" in n|student) ;; *) echo "unsupported geometry group: $group" >&2; exit 2 ;; esac
engine=${GODOT_BIN:-godot}
python=${EVIDENCE_PYTHON:-python3}
shots=docs/screenshots/character_integration
mkdir -p "$shots"
: > capture.log
vault=$(mktemp -d)
n_model=assets/models/teacher-n/teacher-n.glb
student_model=assets/models/protagonist/protagonist.glb
cp "$n_model" "$vault/n.glb"
cp "$student_model" "$vault/student.glb"
restore_models() {
  cp "$vault/n.glb" "$n_model"
  cp "$vault/student.glb" "$student_model"
  if [ -f "$vault/cache-paths.txt" ]; then
    while IFS= read -r cache; do cp "$vault/cache/$cache" "$cache"; done < "$vault/cache-paths.txt"
  fi
  rm -rf "$vault"
}
trap restore_models EXIT
for label in n student; do
  test -s "$baseline/$label.glb"
  test -s "$baseline/$label.tres"
done
base_sha=$(cat "$baseline/base-sha.txt")
head_sha=$(git rev-parse HEAD)
engine_version=$("$engine" --version)
export GEOMETRY_BASE_SHA="$base_sha" GEOMETRY_HEAD_SHA="$head_sha" GEOMETRY_ENGINE="$engine_version"
export GEOMETRY_BASELINE="$baseline" GEOMETRY_VAULT="$vault" GEOMETRY_GROUP="$group"
# Record the actual inputs before any swap. Capturing old assets through the head scene
# isolates geometry/material changes; it is explicitly NOT a historical whole-game build.
"$python" - <<'PY'
import hashlib, json, os
from pathlib import Path
base, head = Path(os.environ['GEOMETRY_BASELINE']), Path(os.environ['GEOMETRY_VAULT'])
group = os.environ['GEOMETRY_GROUP']
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
record = {
    'schema': 'where-is-school/character-geometry-evidence/1',
    'status': 'inputs-only; not a completed capture',
    'base_sha': os.environ['GEOMETRY_BASE_SHA'], 'code_head_sha': os.environ['GEOMETRY_HEAD_SHA'],
    'engine': os.environ['GEOMETRY_ENGINE'], 'method': 'gl_compatibility', 'driver': 'opengl3',
    'columns': ['base GLB and look', 'head GLB and look'],
    'scene_camera_shader_pose_code': 'head in BOTH legs; held idle/sit/walk stills, NOT motion signoff',
    'models': {k: {'baseline_sha256': sha(base / (k + '.glb')), 'head_sha256': sha(head / (k + '.glb'))}
               for k in ('n', 'student')},
    'looks': {k: {'baseline_sha256': sha(base / (k + '.tres')),
                  'head_sha256': sha(Path('assets/characters') / directory / filename)}
              for k, directory, filename in [('n', 'teacher_n', 'teacher_n_look.tres'),
                                               ('student', 'classroom_student', 'student_look.tres')]},
}
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
"$python" - <<'PY_CACHE'
import os, re, shutil
from pathlib import Path
vault = Path(os.environ['GEOMETRY_VAULT'])
paths = []
for model in ['assets/models/teacher-n/teacher-n.glb', 'assets/models/protagonist/protagonist.glb']:
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
cp "$baseline/n.glb" "$n_model"
cp "$baseline/student.glb" "$student_model"
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
share = 184000 // len(frames)
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
    for quality in (80, 72, 64, 56, 48, 40):
        buffer = io.BytesIO(); sheet.save(buffer, 'JPEG', quality=quality)
        encoded = base64.b64encode(buffer.getvalue()).decode('ascii')
        if len(encoded) <= share:
            break
    print(f'ARTSHEET: {name}.jpg {encoded}')
record['status'] = 'complete; static rendered comparisons, not motion or owner signoff'
manifest_path.write_text(json.dumps(record, indent=2) + '\n')
print('ARTNOTE: geometry comparison uses actual base/current GLBs and looks; head scene/camera/shader in both legs')
PY
