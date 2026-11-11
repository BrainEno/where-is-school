# ADR 0007 — Large binaries and repository size

- **Status:** Proposed — the rule and the check are implemented; the history rewrite it recommends needs the owner's authorisation, and one item (the runtime music) is scheduled but not done.
- **Date:** 2026-11-11
- **Depends on:** ADR 0001 (engine), `docs/ASSET_PIPELINE.md` §9 (build budgets), `docs/ASSET_PROVENANCE.md` (what each binary is and where it came from)
- **Scope:** what may be committed to this repository, how large it may be, and how the two are enforced.

## Context

Issue #97: the repository grew from 169 MB to 433 MB in ten hours. Three sources, in order
of size:

1. **The screenshot write-back.** A workflow committed captured frames on every run. PR #88
   stopped it: captures are now downloaded as workflow artifacts, and only curated frames
   live under `docs/screenshots/`.
2. **A 4K source model.** PR #90 committed `dirty_football_4k.glb` — 67.4 MiB, a Poly Haven
   CC0 prop whose three embedded maps alone are 66 MiB. It was the largest thing this
   repository ever carried, and nothing checked it: the pack budget in
   `tools/verify_build.py` only sees files that *ship*, and a source file never ships.
3. **Ordinary asset edits.** A binary is stored in full on every change, so a `.blend`, an
   uncompressed recording or a re-baked animation library adds its whole size again the
   second time it is touched — even though the runtime may only ever use a 500 KiB
   derivative of it.

Nothing in the repository said where a large file may live, how large is too large, or what
to do instead. This ADR is that rule, and it comes with the check that enforces it.

Measured on the commit that adds this record, with `python3 tools/repo_size.py --report`:

| | |
|---|---|
| Tracked files | 668, **70.3 MiB** in the working tree (137.6 MiB before the 4K model was removed) |
| Largest tracked files | 10.1 MiB `art/fonts/NotoSansSC-Regular.ttf` (OFL source of the bundled font subset), 7.3 MiB `scenes/dev/animation_retarget_test/UAL1_Standard.glb` (third-party animation library, dev-only test), 4.3 MiB `art/audio/Guitar_loop_01.wav` (the owner's original recording), 4.2 MiB `assets/audio/music/guitar_ambient_loop_01.wav` (the derived loop) |
| By directory | `docs/` 29.3 MiB (28.9 of it screenshots), `art/` 17.0, `scenes/` 11.2, `assets/` 10.8, everything else 2.7 |
| Object store | 114 MiB of packfiles in a shallow clone; a full clone carries the 4K model and the screenshot history |

## Decision

### 1. Two classes of binary, two budgets

A binary in this repository is either something the game imports, or the source that
something the game imports is made from. They are judged by different checks because they
have different jobs:

| Where | Class | Ceiling | Enforced by |
|---|---|---|---|
| `assets/**` | **runtime**: the engine imports it | 2 MiB per file, 16 MiB per pack, as shipped | `tools/verify_build.py` on the exported PCK, every PR |
| `art/**`, `scenes/dev/**`, `docs/**` | **source / scratch / evidence**: never shipped | 12 MiB per file | `tools/repo_size.py --check`, every PR |
| anywhere else | anything git tracks | 12 MiB per file | `tools/repo_size.py --check` |

`tools/repo_size.py` has **no exception list**. An exception list is how the 67 MiB file got
in: a file that needs an exception needs a decision, and the decision is this ADR being
amended, in a commit someone can read.

The ceilings are not the same number on purpose. The runtime ceiling is about the build —
it is the one that keeps the release small, and it applies to the *imported* file, which is
why a 4.2 MiB WAV can be legitimate under `assets/audio/`: the engine imports it as
QOA-compressed audio and the pack carries the compressed form (see "Not fixed here" below).
The repository ceiling is about the clone — every collaborator, every CI job and every agent
workspace pays it once per checkout, forever, in the history.

### 2. A file that a script can rebuild is rebuilt, never re-committed by hand

The repository already has the stronger pattern and keeps it:

| Artefact | Script | Check |
|---|---|---|
| `assets/models/sample/*.glb` | `tools/build_sample_models.py` | `--check`: byte-identical to a fresh build |
| `assets/fonts/NotoSansSC-Regular.ttf` | `tools/subset_font.py` | `--check`: the subset covers the current text |
| `assets/audio/music/guitar_ambient_loop_01.wav` | `tools/build_music_loop.py` | `--check`: byte-identical, and the loop seam is measured |

Committed derivatives stay committed (the engine has to import them) but are never edited
by hand: the script is the source of truth, and CI fails on drift. A binary with no such
script and no reason to be re-edited is a candidate for not being in the repository at all.

### 3. Anything over the ceiling lives outside the repository

The file itself stays on the owner's machine, or upstream; the repository keeps the record:
`docs/ASSET_PROVENANCE.md` gets a row with the source URL, the licence, the exact
measurements and — when the file has to come back — the steps that produce a version which
passes the checks. `art/props/dirty_football/README.md` is the worked example.

### 4. Screenshots are evidence, and evidence is curated

CI captures are workflow artifacts (PR #88). Frames committed under `docs/screenshots/` are
the ones a document links to, they are re-captured rather than edited, and they are the
reason `docs/` is the largest directory in the tree — 28.9 MiB for 73 files. That is
acceptable because each file is small, but a new capture pass that commits a hundred frames
is not: replace, do not accumulate.

### 5. Clones for collaborators and agents use a partial clone

The history carries what this ADR cannot remove without a rewrite, so a working copy that
does not need old blobs should not fetch them:

```
git clone --filter=blob:none https://github.com/BrainEno/where-is-school
# or, to also skip the tree history:
git clone --depth=1 …
```

`--filter=blob:none` fetches commits and trees but no file contents until they are needed,
which is exactly right for a code review, a documentation pass or an agent workspace that
opens the current tree.

## Consequences

- **Adding a large asset is now a decision.** A file over 12 MiB fails CI with its size and
  the commit that would have introduced it, and the way through is a change to this record.
  The 67 MiB model is what that looks like when it is skipped.
- **History is not shrunk retroactively.** Removing `dirty_football_4k.glb` from the tree
  took the working tree from 137.6 MiB to 70.3 MiB and stops the next edit of it from
  adding another 67 MiB, but the blob is still in `.git`, and a full clone still pays for
  it and for the screenshot history. Removing it means rewriting every branch:

  ```
  git filter-repo --path art/props/dirty_football/ --invert-paths   # rewrites all refs
  git push --force --all && git push --force --tags
  ```

  That invalidates every existing clone, every open pull request's base and every agent
  workspace, so it needs the owner's explicit authorisation and a moment when no branch is
  mid-review. It has **not** been done; `git filter-repo` is not even installed in the
  sandbox that wrote this record.
- **The runtime budgets still do their job.** Nothing here relaxes
  `tools/verify_build.py`; the repository ceiling is an *additional* check, and a file under
  `assets/` has to pass both.

## Not fixed here

Three items the issue names, with what is true today:

1. **The runtime music is a 4.2 MiB WAV.** It is imported with `compress/mode=2` (QOA), so
   the shipped sample is roughly 1.7 MiB by the container's own 0.8 bytes/sample overhead
   (46 s at 48 kHz mono) — under the 2 MiB audio hard limit, which is why `Export, verify,
   package` is green, and 3.3× over the 512 KiB warning line. `tools/verify_build.py` has no
   exemption for it: it classifies any `.wav`/`.ogg` path by the audio category alone. The
   fix is to ship Ogg Vorbis (≈0.5 MiB at 96 kbps) built by `tools/build_music_loop.py`,
   which needs an encoder in the pipeline and, critically, an encode that keeps the loop
   exactly sample-length so the seam measured by that script and asserted by
   `tests/music_test.gd` does not become audible. That is an audio pass with the engine in
   the loop, not a format swap in a repository-hygiene pull request.
2. **`scenes/dev/animation_retarget_test/protagonist_ual.res`** (0.96 MiB) is a baked
   animation library that `.github/workflows/bake-animation-retarget.yml` regenerates; it is
   under the ceiling, so nothing forces a decision, but by rule 2 it should either be
   committed-and-checked or not committed at all. It belongs with whoever finishes the
   animation retargeting work.
3. **The 4K model's blob in history** — see "Consequences", last bullet.

## Revisit when

- the owner authorises (or refuses) the history rewrite — the ceiling and the check stay
  either way, only the packfile number changes;
- the music moves to Ogg, at which point the audio row above is deleted and the runtime file
  drops to about a tenth of its size;
- a second asset legitimately needs more than 12 MiB: that is the signal to revisit the
  ceiling, or to move that class of source out of the repository entirely (Git LFS was
  considered and rejected — it moves the bytes to a second quota, keeps a pointer in the
  tree, and every clone still has to fetch it to build).
