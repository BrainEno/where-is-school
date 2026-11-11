# `dirty_football_4k.glb` — source file, not a runtime asset

This is the football that arrived with the classroom set in PR #85, kept exactly as it was
uploaded and kept **out of `assets/models/`** on purpose.

| | |
|---|---|
| Size | 67.3 MiB (one file) |
| Geometry | 35,210 vertices / 37,486 triangles, one mesh, one material |
| Textures | three 4096² maps, embedded: normal PNG 54.5 MiB, roughness PNG 6.3 MiB, albedo JPEG 5.3 MiB |
| Real-world size | 0.221 × 0.220 × 0.220 m, standing on its origin (lowest point 1 mm below it) |
| Source | Poly Haven, "Dirty Football" — https://polyhaven.com/a/dirty_football — CC0 1.0, no attribution required. It is the only third-party file in the classroom set (the other 16 are project-authored, pending the owner's confirmation recorded in the ledger) |

## Why it is here

While it sat under `assets/models/`, the `Export, verify, package` job failed on it:
*"151.9 MiB is not a plausible size for this build"*. The budgets it breaks are in
`tools/verify_build.py` and `docs/ASSET_PIPELINE.md` §9:

- a single model may be 1.5 MiB before it is a hard failure — this one is 45× that;
- a single texture may be 2 MiB — the normal map alone is 27× that;
- a whole release may carry 16 MiB — this one file is 4× the entire pack.

`art/` is `.gdignore`d (see `art/props/.gdignore`) and is excluded from the exported pack
by `tools/verify_build.py`, which is exactly what a 67 MiB source export is for. The
precedent is `art/props/where_is_school_bench_bag.blend`: the editable source of a shipped
model lives here, the `.glb` that goes in the build lives in `assets/models/`.

## What would make it a runtime asset

1. Resample the three maps to 512² (the imported production props use 512²; see
   `assets/models/school_desk/`), and re-encode the normal map as JPEG rather than PNG —
   that is most of the 54.5 MiB.
2. Decimate the mesh. 37,486 triangles for a ball that is 22 cm across is a 4K display
   asset's geometry, not a game prop's; the playground's tyre stack is 4,016 triangles for
   something 1.84 m wide.
3. Export it as `assets/models/playground/playground_football.glb` with an
   `playground_` prefix and the `dirty_` working prefix dropped, plus the `.import`
   sidecar Godot writes beside it.
4. Run `python3 tools/model_library.py --check`; it measures the file against the budgets
   above and fails if any of them is still over.

Until then the playground's ball is whatever the room already draws, and this file is the
only copy of the ball.
