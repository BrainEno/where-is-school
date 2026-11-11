# The football: not in this repository

`dirty_football_4k.glb` was uploaded with the classroom set (PR #85) and committed here in
PR #90 as a source file. It is **no longer tracked**: 67.4 MiB in one file is the largest
thing this repository ever carried, and issue #97 named it. Its commit is still in history
— removing a file does not remove the blob — so this directory now holds the record and
the instructions, not the bytes.

| | |
|---|---|
| What it is | Poly Haven, "Dirty Football" — https://polyhaven.com/a/dirty_football — **CC0 1.0**, no attribution required. It was the only third-party file in the classroom set |
| Size | 67.3 MiB: 35,210 vertices / 37,486 triangles, one material, three embedded 4096² maps (54.5 MiB PNG normal, 6.3 MiB PNG roughness, 5.3 MiB JPEG albedo) |
| Real-world size | 0.221 × 0.220 × 0.220 m, standing on its origin |
| Where a copy can come from | Poly Haven's own 1K/2K glTF download (the source this was exported from), or the owner's local export |

## Why it is not here

Three separate budgets said no, and the repository had none of its own to say it:

- **The release pack.** `tools/verify_build.py` allows 1.5 MiB for a model and 2 MiB for a
  texture; the normal map alone is 27× that. While the file sat under `assets/models/`, the
  `Export, verify, package` job failed with *"151.9 MiB is not a plausible size for this
  build"*.
- **The repository.** `tools/repo_size.py --check` now fails on any tracked file over
  12 MiB. This one was 5.6× over.
- **The history.** Every edit to a tracked binary adds another copy to `.git` forever. This
  file is why issue #97 exists.

## What a shippable export needs

1. Resample the three maps to 512² (the imported production props use 512²; see
   `assets/models/school_desk/`), and re-encode the normal map as JPEG rather than PNG —
   that is most of the 54.5 MiB.
2. Decimate the mesh. 37,486 triangles for a ball that is 22 cm across is a 4K display
   asset's geometry, not a game prop's; the playground's tyre stack is 4,016 triangles for
   something 1.84 m wide.
3. Export it as `assets/models/playground/playground_football.glb` with a `playground_`
   prefix, drop the `dirty_` working prefix, and commit the `.import` sidecar Godot writes
   beside it.
4. Run `python3 tools/model_library.py --check` and `python3 tools/repo_size.py --check`;
   the first measures it against the model and texture budgets, the second against the
   repository's.

Until then the playground's ball is whatever the room already draws.

## Making it come back out of history

That needs a rewrite of every branch and every clone — `git filter-repo --path
art/props/dirty_football/ --invert-paths` — and the owner's authorisation, because it
invalidates every existing checkout and every open pull request. The recipe and its
consequences are in `docs/adr/0007-large-binaries-and-repository-size.md`.
