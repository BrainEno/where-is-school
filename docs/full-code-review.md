# Full code review and engineering audit — findings, decisions, and where they went

This file is the repository-side index of the November 2026 audit of the project. The audit
itself was delivered as a long report plus thirteen GitHub issues; this page keeps the part
that has to survive in the repository: **what was measured, what was found, which decision
is still open, and which issue each finding became.**

It is an index, not a second copy of the report. When the two disagree about a *number*, the
number here is the one that was re-measured; when they disagree about a *finding's status*,
this page is newer.

## The baseline the audit was written against

`main` at `f027f35`. That matters for reading it now:

| The audit said | Status today |
| --- | --- |
| `main` has no animation system at all; the work sits in PR #53 | **Stale.** #53 merged (`b4faf46`). `main` has the retargeting bake, 42 library clips and `character_animation.gd`. |
| PR #53's head is red and the PR should be split | **Stale.** The rest-relative tolerance was the failure; it was raised to 5° with the reason written down, and the PR was merged whole. |
| The bake job has a `push` trigger, so every push re-bakes binary assets | **Stale.** It is `workflow_dispatch` only now. |
| The CI check list has 47 entries; the docs say thirty-five | Both re-measured: **51** entries now, and the roadmap states that number and points at the workflow. |

The audit's headline figures — delivery about 26%, player-visible content about 7%,
engineering about 69% — were estimates from that baseline and are not repeated as facts here.

### What it measured (at `f027f35`)

- `.git` 169 MB; screenshots are 76% of the 233 MB working tree, across 850 historical
  versions of 73 files.
- Rendering side: 0 `.gdshader` files. Of 386 `MeshInstance3D`, 347 are `BoxMesh`; 20
  materials are flat colours; both character meshes have 0 tangents, UV coverage 38/78 and
  1/15. That is a grey box, and the audit's point was that it is a *deliberate* grey box with
  no path out of it yet.
- `protagonist.glb`: 78 meshes, 16 joints, 0 animations, 7,591 weighted vertices all with a
  single bone influence, 42 unweighted vertices left over from an Icosphere.
- `q.glb`: 7 meshes, 0 bones.
- Content: about 4,500 English words (about 6,400 Chinese characters), 25 conversations,
  169 nodes, 7 checks. Re-measured: 25 conversations and 2,309 words per language.
- Input: 10 actions defined, 0 joypad events.
- Shipped font: 385,416 bytes (376 KiB). The docs said 325 KiB until this was fixed; the
  audit's 325 KiB was right about the *earlier* font and wrong about the current one.

## The three decisions that gate the art work

The audit's strongest structural point: three decisions are load-bearing, everything else in
the art plan depends on them, and they are the owner's to make, not a developer's to guess.

1. **Camera projection — decide first.** Orthographic, or a long lens at 15–20°. Every
   framing judgement, every prop silhouette and the entire screenshot evidence set follow from
   it. Nothing else in the art plan can be settled before this.
2. **Environment route.** Grey-box-plus-light first (route B) with one classroom vertical
   slice as the pilot, versus a full art pass per room. The audit recommends B plus a
   classroom slice (route C as the pilot), and says so explicitly as a recommendation rather
   than a decision.
3. **Character shading.** Which look the two characters are supposed to have, which decides
   whether the meshes are re-UV'd and re-tangented at all.

They belong in **ADR 0004**, which does not exist yet. Until it does, #54 (the
"rendering pipeline is zero" finding) cannot be worked on responsibly.

## Findings and where each one went

Confirmed defects first — these are bugs, not gaps:

| Finding | Issue | Status |
| --- | --- | --- |
| The director awaits a conversation-finished signal that `start()` may already have emitted, so the player lock never clears | #57 (duplicate #56) | **Fixed** in PR #68, with a regression check (`tests/dialogue_sync_finish_test.gd`) and a content rule that refuses a conditional start node |
| `camera_fov` in `PlayerController` (60) silently overrides the scene's `fov` (58) | #58 | **Fixed**: `CameraRig` owns the only field of view; the player has none |
| `camera_occluder_fader` only clears its faded state on a frame with no occluder, so a fade can outlive the wall | #58 | **Fixed**: the fader rebuilds its set every frame; `camera_rig_test` walks blocker A to blocker B to nothing |
| `NarrativeState.restore_snapshot()` bypasses every check `record()` performs, and an unknown source degrades to `OBSERVED` | #60 | Open |
| Check seeds come from `Time.get_unix_time_from_system()` and never enter a save | #60 | Open |

Structural findings, in the audit's own priority order:

1. **#67 hygiene** — partially fixed in PR #68: the tracked `.pyc` is gone, every script that had no
   `.uid` got one, and the stale numbers (font size, check count) are corrected. Still open:
   Actions pinned to commit SHAs, and the object leak the audit saw at exit (needs an engine
   run to reproduce).
2. **#58 camera rig** — the camera is a child of the player, which is why the scene's field of
   view is dead config. **Done in the same pull request as this page**: `CameraRig` is a sibling
   of the player and owns the offset, the field of view and the roll. ADR 0004 is the draft that
   decides what the rig should be pointed at and how wide.
3. **#59 director recoverability and hard-coded location ids** — the prerequisite for both
   saving and adding a location. The audit's sequencing: this before #60.
4. **#60 save/load**, **#61 portraits**, **#62 settings and input**, **#63 artifacts in
   history**, **#64 asset provenance**, **#65 `narrative_store.gd` (1,216 lines, 63
   functions)**, **#66 release engineering**.
5. **#54 art pipeline** (blocked on ADR 0004) and **#55 animation into the game** — the
   animation *assets* now exist on `main`; what is missing is the state machine that picks a
   clip from movement and presentation state, and that is #55's remaining half.

## What the audit could not see

- It read an older `main`. Anything it says about PR #53, the bake job, or the animation
  system describes a branch that has since been merged.
- It could not see the game run. Every judgement about feel, pacing and camera framing is
  inferred from code and screenshots, which is one more reason the projection decision is the
  owner's.
- Its file-size and history numbers need a full clone to reproduce; this repository is
  checked out shallow in agent sessions, so they are quoted from the audit rather than
  re-derived.

## Keeping this page honest

When a finding above is fixed or a decision is taken, change the row here in the same pull
request. A findings index that drifts is worse than no index — it is the same failure mode the
audit was written to catch.
