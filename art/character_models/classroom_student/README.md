# Seated classroom student: immutable source

`student_source.glb` is the exact, previously shipped owner-authored blockout, preserved
before the owner-requested geometry refinement. It is not another playable protagonist.
The parent `.gdignore` excludes it from Godot import and game exports.

- Source snapshot: task base `7379ff7239bee6254ab3242901be9705488e282d`.
- Original path: `assets/models/protagonist/protagonist.glb`.
- Source bytes: `525912`; SHA-256:
  `5928e55a26bc03168d61618815724d7555881710f54715405e18428af855cd8d`.
- Existing provenance: owner-authored procedural Blender 5.2.3 LTS export, as recorded in
  `docs/ASSET_PROVENANCE.md`. The original Blender-generation script was not supplied;
  it is not fabricated here. That ledger remains the rights authority.

```sh
python3 -m pip install -r tools/requirements.txt
python3 tools/prepare_classroom_student.py
python3 tools/prepare_classroom_student.py --check
python3 tests/character_geometry_test.py
python3 tools/model_library.py --check
```

`tools/prepare_classroom_student.py` owns source -> runtime. The in-repo geometry authoring
code is `tools/character_geometry.py` (Arena coding assistance, platform model not exposed).
It builds connected five-digit hands, a continuous jaw/cheek/socket/nose surface, smaller
low-relief eyes, a swept crop, shoulder/sleeve lofts and curved solid garment panels; it
selectively rounds the remaining low-sided source forms. Fourteen obsolete mesh nodes
are removed, not hidden: six separate long fingers, two thumbs, two cheek pads, two
under-eye pads and two detached nose parts. Existing names/material keys are retained
where the corresponding piece remains. Revision 2 further sculpts the sloped crop,
shared sclera/iris surface, folded lap, and shorter, more curled fingers; both sides of
each sleeve overlap share the same blended upper-arm/forearm weight field. The source
is never overwritten.

The sixteen joint names/order, parentage, rest transforms, inverse binds, standing height,
sole datum and unanimated-source contract are unchanged. The runtime still lives at the
historical `assets/models/protagonist/protagonist.glb` path and the existing
`classroom_student.tscn` remains seated at its authored desk. Fingers are modelled, not
individually rigged. New hands keep the original rigid Hand binding, without inventing
finger joints. Preserved rig inputs do not by themselves prove artistic deformation.

No commercial reference-game mesh, portrait, texture or animation was downloaded, traced
or sampled. This revision is a reviewable refinement, not a claim of commercial-reference
quality. Source rights do not clear other characters/portraits, and owner visual approval,
Windows Forward+ deformation and performance review remain separate requirements.
See `docs/CHARACTER_INTEGRATION.md` §§9–10 for genuine base/current capture instructions.
