# The folded teaching wing

Production layout and art notes for the extension beyond the biology classroom’s white rear door. The rear door itself is still inspection-only; this stair is around the corner from it, not behind it.

| Place | Walkable floor | Route and bearing |
|---|---:|---|
| 02 — biology gallery | 0.00 m | Continue past the rear door towards the old gate, then take the west opening into a common stair hall. |
| 03 — existing upper gallery | +3.60 m | Take the iron-red branch west, turn north on a +1.80 m landing, then join the existing upper gallery at its former end. The old connections further along the gallery remain. |
| 01 — ground floor | −3.40 m | Take the blue branch south, turn west on a −1.70 m landing, and arrive at the 17.7 m arcade. The fire stair still leads to the existing yard door, not to this arcade. |
| Laboratory | Separate location | The last arch is blind too. An amber inlay rounds the opaque return at the end of the arcade. The door beyond it is optional and returns to the same recess on 01. |

The storey plaques refer to heights. Existing classroom plates remain room numbers, including the repeat plates in the old block; their numbers are not addresses in the routing system. The two stair branches share one navigation map with the corridor. They use the existing collidable ramps, separate visual treads, safety rails and walkable flat landings; no floor change is a teleport.

## Palette and staging

Two branches peel out of the same hall instead of stacking directly on top of each other, leaving both turns legible from the fixed camera. Iron-red and petrol-blue rails distinguish the branches. The ground-floor north wall repeats a civic arcade in rose-grey plaster, but the radius, crown and cornice do not follow the same grid, and none of the arches is a door. A contrasting thin amber rule is continuous only around the actual folded end. There is no roof across the player or quest marker locating the room. The laboratory’s colder fixtures, running mixer, cable route and inexplicable low annex remain its own scene; only the double-sided threshold is shared.

These are first-party generated Godot primitives and existing repository materials. They require no new textures, models, fonts, dependencies, or third-party assets. Source: `tools/build_teaching_block.py`, `tools/build_laboratory.py` and `scenes/environment/props/laboratory_entry_door.tscn`. `corridor.tscn` owns the real interaction, return marker and other existing exits. The laboratory stays an optional detour; there is no new flag or arrival dialogue.

## Reproduce

```sh
python3 tools/build_teaching_block.py --check
python3 tools/build_laboratory.py --check
godot --headless --path . --script res://tests/corridor_art_test.gd
godot --headless --path . --script res://tests/laboratory_visual_slice_test.gd
xvfb-run -a --server-args='-screen 0 1600x900x24' godot --path . --resolution 1600x900 \
  --rendering-driver opengl3 --script res://tests/capture_locations.gd -- \
  label=teaching-wing teaching-wing
```

The `corridor (after)` job in Location art capture publishes the five teaching-wing shots with the rest of its corridor frames. To try it in-game, leave through the grey front door after class, pass the white door and take the stair hall on the same side of the gallery. Try each branch with movement controls and floor clicks. When turning back on 03 with Q following, move over to the side of the wide gallery and pass Q before heading down; a floor click straight through a solid actor is not a path around them. On 01, follow the inlay past the arches around the corner, enter the lab, then use the same door to return and climb back up.
