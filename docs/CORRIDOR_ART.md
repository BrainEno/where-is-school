# The walkway that does not end: the corridor's art pass

- **Status:** In review. Changes the shipping corridor (`scenes/locations/corridor/corridor.tscn`) through its generator; no collider, exit, spawn, interactable or library prop is added, moved or removed.
- **Brief (owner):** the corridor has to feel *empty* and *endless*; done in the spirit of the art-style experiments ([VISUAL_EXPERIMENTS.md](VISUAL_EXPERIMENTS.md), [BIOLOGY_CLASSROOM_EXPERIMENT.md](BIOLOGY_CLASSROOM_EXPERIMENT.md)), with the prologue classroom ([PROLOGUE_ART_MIGRATION.md](PROLOGUE_ART_MIGRATION.md)) as the room it leads out of.
- **Generators:** `scenes/environment/props/stage_art/source/paint_stage_textures.py` (textures) and `build_stage_art.py corridor` (materials, environment, sun, stage nodes). Re-running both is idempotent; never hand-edit the stage nodes in the scene.
- **Checks:** `tests/corridor_art_test.gd` (Godot CI step `corridor_art`) for this idea; `tests/location_art_test.gd` (the `location-art-capture` workflow) for the shared stage rules; `tests/corridor_props_test.gd` for the three library props.
- **Evidence:** the `location-art-capture` workflow renders the corridor before and after at 1600×900 with the game's camera.

## 1. The idea

The experiment's own corridor zone ended on a warning: *endless as pure decoration is a cliché; it needs an exit or a meaning.* So the endlessness here is not a painted backdrop but a real one, and it has a meaning: **the walkway goes on, and you cannot.** The end wall is gone; past the yard door the same walkway — floor, wall, classrooms, windows, parapet — carries on, at the same even pace, until the haze has made it the colour of the sky. The only way on is the door, which now stands in a railing in the middle of the walkway, closed, with the walkway visibly continuing around it.

Emptiness comes from taking away: the far block across the yard is gone, the cut-out skyline of flats and a pylon is gone, the busy terrazzo and its brass strips are gone. What is left is a pale floor, a pale wall, a long low sun and the haze.

## 2. What changed

| Part | Before (stage pass) | Now |
|---|---|---|
| Light | purple dusk clear colour (0.25, 0.29, 0.39), sun (−24°, 62°) × 0.6, no fog | haze clear colour (0.88, 0.84, 0.81); a low afternoon sun from the stairs' end (−17°, 16°) × 0.55, so every shadow points down the walkway towards the door; ambient (0.60, 0.58, 0.72) × 0.85, exposure 0.68 (toon diffuse lights a lit face fully, and the albedos are pale: the first CI frames at sun × 1.25 blew the walkway out to white) |
| Fog | none | **depth fog** (`fog_mode` 1), colour = clear colour, begins 11 m from the camera (the camera stands 8 m from the player, so the player is never fogged), full by 38 m, curve 1.2; **height fog** below y −0.6 (density 0.32) washes the yard out |
| End wall | a 3.1 m wall with the yard door in it, its dado band | the wall's mesh hidden (`visible = false`); its collider is kept, full height. A railing — the parapet turned across the walkway — either side of the door; the door's frame, transom and closed leaf stand free |
| Past the door | nothing (the wall) | `StageArt/Beyond`: 96 m more walkway — slab, ruled floor, wall with its painted rhythm, coping, the leaning upper storey with its windows, parapet and rail — all in phase with the walked 16 m |
| Wall | cream plaster, pilasters closing up and the wainscot sinking towards the yard door (a forced perspective) | lilac-white plaster, a pilaster every 4 m, the classroom's deep wainscot (60, 64, 104) level at the classroom's 1.05 m line; even pacing, because an even pace is what does not end |
| Floor | red-brown terrazzo, converging brass strips | pale cast floor ruled like an answer sheet (worn blue rules, the red margin 0.7 m out from the wall): the classroom's floor carried outside; saw cuts under every pilaster |
| Upper storey | windows shrinking towards the door | one window every 2 m, all alike (an alpha-cut tile), continuing past the door |
| Yard | court fragment, hoop | the same, warmer ground; under the height fog |
| Distance | sky laid flat, flats and a pylon | the haze laid flat (`distance_corridor.png`, 320 m), a breath warmer near the building; no skyline |
| Far building | dark block at x 15 | hidden |

### The pacing

Everything repeats at one pace, set by the walked wall: pilasters at s = 4k − 0.2 m from the stairs' end (clear of the glass, the classroom door, the extinguisher and the noticeboard), the floor's saw cuts under them. The continuation begins at z −9.2 (s = 16.2) and its 8 m wall tile (two bays, one classroom: door with a lit pane and a blank number plate, lit glass) starts in the same phase; the floor tile (4 m) and the window tile (2 m, offset by the 0.2 tile the walked storey ends on) likewise. The continuation is therefore the same building going on rather than a picture of one.

### The palette

| Role | sRGB |
|---|---|
| Haze (clear colour, fog, distance) | (224, 214, 207) |
| Plaster / light / shade | (214, 210, 222) / (226, 222, 232) / (194, 190, 206) |
| Pilaster | (184, 180, 200) |
| Wainscot, rail, trims (ink outline) | (60, 64, 104) |
| Floor | (200, 192, 184), rules (128, 146, 196), margin (188, 74, 62) |
| Lit classroom glass (the only warm thing far away) | (236, 204, 160) |

## 3. Rules kept

- **Stage rules** (`location_art_test.gd`): every new piece is mesh-only, under `StageArt` or named `Stage*`, with a `BaseMaterial3D` from `stage_art/materials/`; no shaders. The continuation lies wholly north of z −9.2, the railing at z −9.1: no standing spot or sight line reaches either, so the camera rule holds without new occluders. The collider count (87), the 9 interactables, the spawns, exits and routes are unchanged.
- **Props:** the noticeboard, extinguisher and trolley are untouched (`corridor_props_test.gd`).
- **Portability:** depth and height fog are supported by both Forward+ and the Compatibility renderer's `fog_process()`; the project uses Forward+, where fog is per pixel, so the 96 m quads fade smoothly.
- **Budgets:** the stage textures stay under 100 KiB each (the floor is posterized onto its own palette plus fixed ink colours, so the thin rules keep their colour).

## 4. Known limits

- The haze is a single colour; with `BG_COLOR` there is no aerial perspective (that needs a sky). Fine for an empty look; a sky would be the next step if the far end should glow.
- The three warm walkway lamps (`WalkwayLight*`) are left as they were.
- Walking up to the railing, the player meets the end wall's invisible collider above it. It is the scene's end and the door is the exit, so this was kept rather than adding colliders.
