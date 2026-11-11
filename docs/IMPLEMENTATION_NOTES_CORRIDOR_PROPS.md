# Implementation notes — corridor models in the walkway

The first models from the #90 library to reach a playable location. The three
`assets/models/corridor/` files replace the grey boxes that stood for the walkway's
noticeboard, fire extinguisher and cleaning trolley. Nothing else in the corridor moved:
the walls, the doors, the bench boxes, the lights, the speaker and the interaction data
are as they were. One look-anchor moved, because it would otherwise have been inside the
new collider (§4).

## 1. What was added

| File | What it is |
|---|---|
| `scenes/environment/props/corridor_noticeboard.tscn` | wrapper: `StaticBody3D` (layer 1, mask 0), `Model` = `corridor_noticeboard.glb` at its own origin, one box collider |
| `scenes/environment/props/corridor_fire_extinguisher.tscn` | wrapper: same shape; `Model` at y = −0.050 so the lowest point is the wrapper's origin |
| `scenes/environment/props/corridor_cleaning_trolley.tscn` | wrapper: same shape; `Model` at y = −0.020 so the wheels touch the floor |
| `scenes/locations/corridor/corridor.tscn` | three instances (`CorridorNoticeboard`, `CorridorExtinguisher`, `CorridorTrolley`). Nine grey-box nodes, their nine meshes and four now-unused external resources are gone, including the `blackboard.tscn` reference that no node used |
| `tests/corridor_props_test.gd` | the placement test (§5), added to `godot-ci.yml` after `prop_placement` |

The models themselves are unchanged: no re-export, no new `.import` settings, no
material overrides. They keep their flat `WIS_*` colours. Re-dressing them into the
painterly palette is the separate round that `docs/MODEL_LIBRARY.md` §2.6 describes.

## 2. Wrappers: numbers from the files

Every collider is the world-space bounding box that `tools/model_library.py` reads from
the vertices, after the wrapper's `Model` offset. It is not a guess from the accessors.

| Wrapper | Model offset | Box size (m) | Box centre (m) | Why |
|---|---|---|---|---|
| noticeboard | 0 | 1.780 × 1.176 × 0.194 | (0, 1.450, −0.013) | The board's origin is on the floor under it (min y 0.862), so the wrapper keeps it there and is placed standing at the wall |
| extinguisher | y −0.050 | 0.417 × 0.808 × 0.284 | (0.0385, 0.404, 0.022) | The model's lowest point is 5.0 cm above its origin |
| trolley | y −0.020 | 0.946 × 1.432 × 0.699 | (0.083, 0.716, −0.0195) | The wheels are 2.0 cm above the origin; the mop handle sets the height and the mop the +X extent |

## 3. Placement

The walkway runs along Z. The building wall's face is at x = −2.1 (`WallBuilding`, 0.2 m
thick at −2.2). The parapet's face is at x = 2.03, and its rail's face is at 1.97 between
1.04 and 1.12 m. The fixed camera looks across the walkway from above the parapet towards
the wall.

| Instance | Position | Yaw | Result |
|---|---|---|---|
| `CorridorNoticeboard` | (−1.99, 0, −2.0) | +90° | Back (model z −0.110) on the wall face; frame from 0.862 to 2.038 m. The old cork board was centred at 1.66 m |
| `CorridorExtinguisher` | (−1.98, 0.30, 0.1) | +90° | Back (model z −0.120) on the wall face; plate from 0.30 to 1.11 m |
| `CorridorTrolley` | (1.59, 0, 3.6) | −90° | Footprint x 1.26–1.96, z 3.21–4.16; parked against the parapet, 1 cm short of the rail |

**Facing.** The library records two conventions in one set (`MODEL_LIBRARY.md` §2.5). All
three corridor models put their working face on **+Z**: the noticeboard's notices, the
extinguisher's gauge and label, and the trolley's front panel (its handle is on −Z). With
Godot's yaw, +90° turns +Z towards +X and −90° turns it towards −X:

- the board and the extinguisher are on the −X wall, so +90° turns their faces into the
  walkway and towards the camera;
- the trolley is on the +X parapet, so −90° turns its front panel into the walkway. Its
  handle faces the parapet, where a cleaner would park it. The camera, which looks from
  the parapet side, sees the top: bucket, rag and mop.

**Why the extinguisher is on the wall rather than on the floor.** The library lists it
among the floor props, because its lowest point is 5 cm above its origin. Two things say
otherwise. The model carries its own `Mounting_plate`, and the corridor's shipped
inspection text describes the extinguisher as "on a bracket". Standing on the floor, the
plate would also cut 5 cm into the 0.14 m skirting. So the wrapper still puts the lowest
point at its origin, as the floor-prop convention does, and the instance lifts the whole
thing to 0.30 m. That is about where the old cylinder and bracket hung (0.35–0.90 m).
This is a placement decision, made without asking anyone: if the owner wants a
floor-standing extinguisher, it is a one-line change to `position.y` and to the test's
`base`.

## 4. Interaction anchors

The three interactables kept their ids, prompts and inspection / conversation data.

| Anchor | Change | Why |
|---|---|---|
| `NoticeboardInspect` | `support_paths = ["../../CorridorNoticeboard"]` | The prop is now a collider. Declaring it as support means the line-of-sight probe looks through it instead of treating the board as a wall in front of its own notice (pipeline §4) |
| `ExtinguisherInspect` | `support_paths = ["../../CorridorExtinguisher"]` | Same reason |
| `TrolleyInspect` | moved from (1.7, 0.8, 3.6) to (1.1, 0.8, 3.68); `support_paths = ["../../CorridorTrolley"]` | The old point is inside the new trolley collider (x 1.26–1.96). The new one is 16 cm in front of the front panel, centred on the trolley's length |

The trolley now collides. The old boxes did not, so the player could walk through
them. Its footprint erodes the navigation mesh to about x = 0.76 between z ≈ 2.7 and
4.7. That leaves about 2.4 m of walkway, from x = −1.6 to x = 0.76. The board and the
extinguisher stand off the wall by 0.19 m and 0.28 m, which is less than the 0.5 m
agent radius the wall already erodes, so the walkable area along the wall is the same as
before.

The companion obstacle test builds its walls across the walkway at z = 3.0 and z = 4.5,
with its gap at x = ±0.8. The trolley's eroded edge (x ≈ 0.76) is just inside the gap's
right-hand edge, so the gap Q is meant to walk through is still open.

## 5. Verified by `tests/corridor_props_test.gd`

- **Wrappers.** Each is a `StaticBody3D` on layer 1 / mask 0. Its `Model` instances the
  right `.glb`. It has exactly one box collider, which covers the instantiated model to
  within 1 cm. The model starts at the expected height: 0, or 0.862 for the board.
- **Instances.** Each appears once in `corridor.tscn`, instances its wrapper (not a bare
  `.glb`), sits at the declared position, has a pure yaw and no scale, and has its lowest
  point at the expected height (board 0.862, extinguisher 0.30, trolley 0).
- **Contact.** The board's and the extinguisher's backs are within 2 cm of x = −2.1. The
  trolley does not reach past the rail face (1.97) and stands no more than 5 cm short of
  it.
- **Facing.** The `Notice_ink_mark*`, `Gauge_face` and `Trolley_front_panel` meshes are
  found in the placed models. Each must be on the walkway side of its prop's centre.
- **No ghosts.** The nine retired grey-box nodes are absent.
- **Anchors.** Each anchor is outside its prop's collider, lists the prop in its support
  set, and has walkable ground within 1.2 m.
- **Routes.** With the colliders baked, the mesh still connects `FromClassroom` with the
  gate and the yard door, `FromSchoolyard` with the gate, and `FromStreet` with the
  classroom door.

Existing checks that also cover this change: `interaction_visibility_sweep`,
`navigation`, `companion_obstacle`, `companion_route` (activates the trolley),
`location_pressure` and the playthrough capture. The capture teleports to (0.5, 0, 3.6)
and points at the trolley's anchor, which is frame `13b_hover_trolley`.

## 6. Known limitations

- **Flat colours.** The models keep the library's flat `WIS_*` colours, which are not the
  painterly palette the classroom uses (`MODEL_LIBRARY.md` §2.6).
- **The corridor bench is still grey boxes** (`BenchSeat`, `BenchLegA`, `BenchLegB`). The
  #90 library has no corridor bench. `playground_bench` would be a design choice, not a
  swap.
- **The notices are geometry, not text.** The inspection text names fixtures, a fire drill
  notice and a photograph. The board's papers are blank shapes with ink marks. That is
  consistent, and no texture was added.
- **Authorship is confirmed; art review is not.** The owner confirmed on 2026-11-11 that
  they made the library models in Blender, and `docs/ASSET_PROVENANCE.md` records it. The
  row's review column still reads "Pending owner art review", as every authored asset's
  does.
