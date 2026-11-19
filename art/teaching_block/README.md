# The folded teaching wing

Production layout and art notes for the extension beyond the biology classroom’s white rear door. The rear door itself is still inspection-only; this stair is around the corner from it, not behind it.

| Place | Walkable floor | Route and bearing |
|---|---:|---|
| 02 — biology gallery | 0.00 m | Continue past the rear door towards the old gate, then take the west opening into a common stair hall. |
| 03 — existing upper gallery | +3.60 m | Take the iron-red branch west, turn north on a +1.80 m landing, then join the existing upper gallery at its former end. The old connections further along the gallery remain. |
| 01 — ground floor | −3.40 m | Take the blue branch south, turn west on a −1.70 m landing, and arrive at the 17.7 m directory gallery. The fire stair still leads separately to the yard. |
| Glass entrance | −3.40 m | Arrive from the street outside the glazed assembly. Walk across the actual opening to enter 01. The plate on the forecourt rail goes back to the street. The old 02 gate is still an exit, and its spawn remains valid. |
| Laboratory | Separate location | An amber inlay rounds the opaque return at the end of 01. The door beyond it is optional and returns to the same recess. |

The storey plaques refer to heights. Existing classroom plates remain room numbers, including the repeat plates in the old block; their numbers are not addresses in the routing system. The two stair branches share one navigation map with the corridor. They use the existing collidable ramps, separate visual treads, safety rails and walkable flat landings; no floor change is a teleport.

## Palette and staging

The fixed camera can read both turns; iron-red and petrol-blue rails distinguish their
stairs. The old perspective experiment's repeated bays and one overscale threshold inform
three different settings rather than three copies of the same corridor:

- **01 / municipal lobby:** a rose enamel wall holds a broken directory, not false doors.
  Across from it is a 6.2 m composition of petrol enamel, glass sidelights, split transoms
  and a 2.66 m opening. Ivory traces cross into the forecourt while amber turns toward
  the laboratory. The same assembly sits in the recessed school face on the street. The
  lintel follows the projecting cap so the existing camera fader can clear the view.
- **02 / public office after hours:** sage beams and ochre registration marks shrink down
  the run. The waiting register sits away from the original classroom threshold.
- **03 / blue-hour ledger:** indigo rails, lavender index marks, and an overscale timetable
  end that is visibly solid. Room numbers repeat without adding new travel links.

In the classroom bays the beam rebate is no longer flush with the depth of the wall face;
roof, return and stair trim use distinct mating edges. No depth bias or global change to
lighting, render settings or the follow camera is needed. The laboratory keeps its own
cold, clean instrumentation and the low annex beyond the bundle.

These are first-party generated Godot primitives and existing repository materials. They require no new textures, models, fonts, dependencies, or third-party assets. Source: `tools/build_teaching_block.py`, `tools/build_laboratory.py` and `scenes/environment/props/laboratory_entry_door.tscn`. `corridor.tscn` owns the real interaction, return marker and other existing exits. The laboratory stays an optional detour; there is no new flag or arrival dialogue.

## Reproduce

```sh
python3 tools/build_teaching_block.py --check
python3 tools/build_laboratory.py --check
godot --headless --path . --script res://tests/corridor_art_test.gd
godot --headless --path . --script res://tests/laboratory_visual_slice_test.gd
xvfb-run -a --server-args='-screen 0 1600x900x24' godot --path . --resolution 1600x900 \
  --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_locations.gd -- \
  label=teaching-wing teaching-wing
```

The `corridor (after)` job in Location art capture publishes eight teaching-wing shots
with the rest of its corridor frames. Full-size shots and the camera index are in the
job artifact; compact copies are published inline. To try it, leave through the grey front door after
class, pass the white door and take the stair hall on the same side. Try each branch
with movement controls and floor clicks. On 03, move to the side to pass a following Q.
On 01, follow the copper line around the corner into the laboratory and use its door to
return. Walk through the glass entrance in either direction and take the forecourt exit
to the street. Returning from the street should put you outside the door, not on 02.
