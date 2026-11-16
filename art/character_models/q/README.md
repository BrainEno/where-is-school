# Approved Q source

`new-Q_source.glb` is the immutable owner-approved upload, not a second production model.
The parent `.gdignore` prevents Godot import/export. All runtime and preview placements
instance `scenes/environment/characters/q.tscn` → `assets/models/q/new-Q.glb`.

- Owner declaration: **ChatGPT AI-generated original for this project, approved for formal use**.
  This is a separate replacement, not the former Q's Blender/Python generation chain.
- Upload commit: `f9aa19d4fa8ad56b0e4d2e46c48c799d10ffbb42`.
- Original path: `assets/models/q/new-Q.glb` on the upload ref.
- Blob: `0d71fcf65cf76fa7abe7124cba7f74fbfa02efb9`.
- Bytes: `1187664`.
- SHA-256: `4d2d7d5939840bdfcc8b94f111f864e1d080a715380969ec335a7e1e60509f45`.

Rebuild/check with stdlib Python only:

```sh
python3 tools/prepare_q.py
python3 tools/prepare_q.py --check
python3 tests/q_model_prepare_test.py
```

The preparation removes the supplied skeleton-display mesh, drops only channels equal
to the actual rest pose, fills missing material colours using the established Q palette
and copies live accessor data verbatim (including sparse morphs). It does not change the
mesh shape, normals, indices, skin weights, joints, rest transforms, inverse binds, morphs
or non-rest animation data. All six original actions are retained. Tests compare these
properties directly against this source; they do not certify engine deformation quality.

See `docs/Q_MODEL_MIGRATION.md`, `docs/ASSET_PROVENANCE.md` and the reviewed runtime
manifest for rig/action/material mapping, exact engine evidence and remaining owner review.
Q's approval does not clear the protagonist, portraits, UAL or Issue #64.
