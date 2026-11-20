# The folded teaching wing

Production layout and art notes for the extension beyond the biology classroom’s white rear door. The rear door itself is still inspection-only; this stair is around the corner from it, not behind it.

| Place | Walkable floor | Route and bearing |
|---|---:|---|
| 02 — biology gallery | 0.00 m | Continue past the rear door towards the old gate, then take the west opening into a common stair hall. |
| 03 — existing upper gallery | +3.60 m | Take the iron-red branch west, turn north on a +1.80 m landing, then join the existing upper gallery at its former end. The old connections further along the gallery remain. |
| 01 — ground floor | −3.40 m | Take the blue branch south, turn west on a −1.70 m landing, and arrive at the 17.7 m directory gallery. The fire stair still leads separately to the yard. |
| Glass entrance | −3.40 m | Arrive from the street outside the glazed assembly. Walk across the actual opening to enter 01. The plate on the forecourt rail goes back to the street. The old 02 gate is still an exit, and its spawn remains valid. |
| Laboratory | Separate location | An amber inlay rounds the opaque return at the end of 01. The door beyond it is optional and returns to the same recess. |
| Restrooms | Separate locations | Mint threshold strips at the west end on 01 and at the east ends on 02 and 03. Each returns outside its own louvred door. |
| Staff office | Separate location | The amber index at the east end of 03. Return to the same indigo gallery. |
| Six registration rooms | Separate locations | Two on each storey. Look at the locked leaf, then use the adjacent patterned slide. See the thresholds and local reveal in [the corridor contract](../../docs/CORRIDOR_ART.md). |

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
- **03 / blue-hour ledger:** indigo rails, lavender index marks and a small
  ledger strip beside the new restroom. Repeated classroom numbers are still observations.
- **Office / clerical amber:** a muted green leaf, maple veneer, carbon slips and a warm desk pool.
  The bronze rules across the open ledger echo the hallway index, without making the duty sheet
  the origin of any other rota.
- **Restroom / failing glaze:** sour cream ceramics, flaking plaster, brown wash below pipes,
  pooled water and 62 small, batched flies around the wet fittings in each room. A recess with
  treads reads as a squat pan; the urinals have hollow pockets, visible feed pipes and a low screen.
  The film reference describes the degree of disrepair only, not a plate, mesh or texture source.
- **Orientation rooms / registration:** the torn outlines, wrong-way shadow, cut-paper layers,
  crosshatching and ruled graphics are built *inside* each room. #196 and #200 inform the grammar;
  the production scenes use the ordinary follow rig and no live mirror, screen texture or viewport.
  The small clue at each threshold repeats as a misalignment in the room's objects. The projection
  room has a hard-edged painted spill, while the computer room has a monochrome phosphor raster
  on the deep monitors, never a real OS logo or screen.

In the classroom bays the beam rebate is no longer flush with the depth of the wall face;
roof, return and stair trim use distinct mating edges. No depth bias or global change to
lighting, render settings or the follow camera is needed. The laboratory keeps its own
cold, clean instrumentation and the low annex beyond the bundle.

These are project-authored Godot primitives, fitted facets and procedural colour fields.
The only fonts and room tones are the existing ones. No downloads, external imagery or new
runtime dependency. `tools/build_school_rooms.py` owns the public interiors, washroom fitting
kit and two-sided leaves; `tools/build_school_annexes.py` owns the six registrations and
measured corridor route fragments. `tools/build_teaching_block.py` installs the hall faces.
The laboratory has its own builder. B does not appear in the office. The stills use the
same ordinary/focus camera and include the detached wide view only as context.

## Reproduce

```sh
python3 tools/build_teaching_block.py --check
python3 tools/build_laboratory.py --check
python3 tools/build_school_rooms.py --check
python3 tools/build_school_annexes.py --check
godot --headless --path . --script res://tests/corridor_art_test.gd
godot --headless --path . --script res://tests/laboratory_visual_slice_test.gd
godot --headless --resolution 1600x900 --path . --script res://tests/school_rooms_test.gd
godot --headless --path . --script res://tests/school_expansion_test.gd
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

The school-detail legs of Location art capture save matched corridor and laboratory views
on both revisions, including the right wall of 02 and 03, and current views of fitted rooms.
`wide` is marked separately. To reproduce the two standing views and the focused CRT visit:

```sh
xvfb-run -a --server-args='-screen 0 1600x900x24' godot --path . --resolution 1600x900 \
  --rendering-driver opengl3 --audio-driver Dummy --script res://tests/capture_locations.gd -- \
  label=school-review only=computer_room school-details school-focus
```
