# Character rig audit

Historical structural audits of the original character source files, produced in Blender
5.2.3 LTS. The Q audit describes the unrigged source now preserved at
`art/character_rigging/q/q_unrigged_source.glb`, not the current runtime model
`assets/models/q/q.glb`, which is its rigged derivative. These audits are records, not
build steps; nothing here is imported by the game.

| File | What it holds |
|---|---|
| `q_rig_audit.md` / `.json` | Armatures, bones, weights, modifier bindings and Actions for `q.glb` |
| `q_component_audit.md` / `.json` | Every mesh object split into edge-connected components, with size, centroid and materials |
| `protagonist_rig_audit.md` / `.json` | The same rig audit for `protagonist.glb` |
| `protagonist_component_audit.md` / `.json` | The same component inventory for `protagonist.glb` |

## What they say

| | Q | Protagonist |
|---|---|---|
| Armatures | 0 | 1 (`RIG_Protagonist_Blockout`, 16 bones) |
| Weighted vertices | 0 of 18 031 | 7 591 of 7 633 |
| Vertices with one influence | 0 | 7 591 (rigid-part bind, not smooth skinning) |
| Meshes with an Armature modifier | 0 | 78 |
| Actions | 0 | 0 |

Two consequences worth stating plainly:

- **Q cannot be animated as supplied.** There is no armature, no vertex group and no
  modifier, so the model is a static mesh. Anything that looks like Q moving is the whole
  node being transformed.
- **The protagonist's rig is a rigid part bind.** All but 42 vertices follow exactly one
  bone, which is the right choice for a blockout made of separate parts, and the wrong one
  for a bend at a knee or an elbow: single-influence weights rotate the part, they do not
  deform it. Neither character has a single Action, so every animation either of them will
  ever play still has to be authored.

## The one number that does not match

Both component audits list an object the committed exports do not contain:

```
| `Icosphere` | 1 | 0 | 42 | 80 | 1.902 × 2.000 × 2.000 | 0.000, 0.000, -0.000 | <no material> |
```

A two-metre, untextured icosphere sitting at the origin of both scenes. The arithmetic
locates it exactly: the component audits report 8 objects / 18 073 vertices / 35 512
triangles for Q where the rig audit reports 7 / 18 031 / 35 432 — and 42 and 80 are that
line. The same holds for the protagonist, 79 objects and 12 468 triangles against 78 and
12 388.

So the audits describe the owner's **Blender scene**, and the committed `.glb`s are that
scene minus the icosphere: it is a leftover new-scene primitive, hidden from the export.
The original source is preserved without that icosphere at
`art/character_rigging/q/q_unrigged_source.glb`. The current runtime
`assets/models/q/q.glb` is a separate 16-joint rigged derivative; this historical audit
must not be used to infer that the runtime Q model is unrigged. The protagonist source
still has 78 meshes, one 16-joint skin and no embedded animations.

It is worth knowing before the next export: if the leftover is ever visible at export time
it becomes a two-metre untextured ball around whichever character was exported, and the
first place it would be noticed is a release build.

## Re-reading the committed files

The counts above come from the GLB's own JSON chunk, not from a renderer:

```python
import json, struct
data = open("art/character_rigging/q/q_unrigged_source.glb", "rb").read()
offset = 12
length, _ = struct.unpack("<II", data[offset:offset + 8])
doc = json.loads(data[offset + 8:offset + 8 + length].decode("utf-8"))
print(len(doc["meshes"]), len(doc.get("skins", [])), len(doc.get("animations", [])))
```
