# The teaching block

The 16 m walkway and the inaccessible 96 m continuation from #243 gave way to a walkable teaching block, now with three storeys. The space is still called `corridor` in the location catalog, save files and story. The route gets strange because it is possible to walk around it, see the same room numbers twice, and come back at a different height, not because a painted façade gets longer.

## Walkable section

| Part | Layout |
|---|---|
| Floor 01 | The entrance forecourt and directory gallery are at yard height. The amber rule turns into a recess to the optional laboratory. The mint plate at the west end marks the restroom, not the lab. The blue stair meets 02 through the rear junction. |
| Floor 02 | The biology classroom door pair, props and gate are at the south end. The west gallery runs north for 37 m, then turns east along the yard. Both runs have classrooms on the left and masonry with inset windows on the right when walking away from the gate. |
| Floor 03 | Set back west and north of 02, 3.6 m above it. The top of either stair opens into a gallery of five classroom bays: three before the turn, two after it. The staff-office leaf is set in the last bay near the east end. There are five more bays on 02; the red stair also meets this level from the rear junction. |
| West stair | A straight flight near the biology room, crossing between the set-back floors. |
| North stair | Two flights, offset sideways by 4.5 m at the half landing. The opening at the top is not above the opening where the player set off. Both stairs work in both directions and form one continuous loop with the two galleries. |
| Fire stair | Descends from the lower east wing to the red fire door at yard height. Its recessed landing is also the return spawn. The same door has a push bar inside and a pull handle on the yard side. The original school gate stairs still lead to the street. |

The navigation mesh is baked from the same slabs, guards and sloped stair colliders the body walks on. Visible steps are individually drawn; the continuous slope keeps auto-walk from tripping at every riser. The galleries do not sit directly over each other in the camera's sightline. A shallow ceiling return, balustrades and divided window frames give the gallery depth without putting a full roof between the default camera and the player.

## Readable repetition

- Each bay has front and rear doors, with separate small glazed transoms, and a 1.98 m × 0.30 m slot between them. The slot starts 2 m above the hall. Use the normal **Interact** action facing it, or click the glass. Both paths stage a real physics hop; the observation is presented only after the eye has passed the opening and the body has landed. There is no new global jump action.
- The other classrooms are observations, not destinations: desks, a lectern and a rear wall are modelled behind each slot, but the biology classroom remains the only fully playable **classroom**. `104` and `202` repeat in different bays. Room depths and floor lines vary slightly behind otherwise familiar pairs of doors.
- The right-hand wall is mostly masonry. On 02 and 03, a 1.06 m sill, 2.35 m lintel line and broad piers surround each divided sash (normally about 1.8 × 1.29 m). Masonry blocks ground and depth rays; only the clear aperture has a player-only barrier. The nearest bay can fade for the follow camera, not the whole elevation. The court paint, hoops, shed and plinth share the playable yard’s source. Its concrete apron continues under the teaching block’s foundations, keeping the yard and the fire stair visually connected. This view adds no yard colliders, actors, nav or story triggers.
- Rose and petrol enamel on 01, sage and ochre public-office trim on 02, and an indigo ledger wall on 03 make repeated rooms legible even when their numbers are unreliable. See [the wing's art notes](../art/teaching_block/README.md).
- The new 01 door opens physically through the south wall; there is no central collider. Sight and pick rays pass through the side panes, but the capsule does not. The street shares the same frame and returns to `FromTeachingEntrance` on the outside of the threshold; `FromStreet` and `school_gate` still exist for the original 02 landing and exit. The glass crossing inside `corridor` requires neither a load nor an interact press.

## The biology threshold

The two openings in bay 101 are the outside of `classroom/WallEast`, not a mirrored pair.
The grey front door near the blackboard is at classroom-local z −3.55 / hall z −5.10;
the white rear door is at classroom-local z +3.55 / hall z +2.00. Both use the same
respective packed door variant across the wall, including the setback, teal frame,
painted vision light and steel hardware. The hinges are on the classroom side (an
inward swing); the corridor shows the reverse fittings on the same latch edge. The
full wall still separates the loaded scenes, and the transition does not animate the leaf.

`FromClassroom` and `back_to_classroom` are at the front threshold; `FromCorridor` in the
classroom lands at the reverse face of that same door. Arrivals face into the walkable
space. The `classroom_door` exit still requires `class_dismissed`. Trying the white door
from either side only presents `classroom_rear_door`; it never changes location.

## Public doors and the six registration rooms

| Floor | Public end room | Optional rooms and the Orientation problem |
|---|---|---|
| 01 | The original `restroom` at the west end, clear of the amber line to the laboratory. | Archive: align punch marks, then see the index and its carbon copy disagree at room scale. Plan room: follow the short elbow to a real landing, then compare two scales of the same plan. Both doors face the camera beside the directory. |
| 02 | `restroom_02`, east of the fire-stair turn. | Projection room: use a nick to select one nested frame; the screen and its shadowed light return the other frames. Computer lab: match the raster to its edge; six deep CRTs, towers, keyboards and mice sit on three tables, and the wall's raster is one row off. Both doors are in the north wall before the left-hand classroom bays. |
| 03 | `restroom_03` at the east end, beyond the existing ungated `staff_office`. | Empty staff room: find the worn indentation instead of the ink; graphite pulls miss the solid desk and vacant chair. Principal's office: locate the offset pair instead of centre; the desk, painted amber/blue axis and false window shadow disagree. Look on the west run and after the north turn respectively. |

All three restrooms have two urinals, a recessed squat pan in the open cubicle, a closed
cubicle, basins and clustered flies. They share physical fittings but use different light
and grime fields. The palette, blocked latch and ordinary inspection text imply neglect,
not a supernatural effect. Nothing there requires a check, sets a destination or names a staff member.

At each experimental room, trying the handle while closed presents the door's marks and
records that they were seen. The separate brass slide offers one visible **Orientation**
check only after that inspection (DC 10 or 11). Failures leave the latch shut. After a
failure, the slide offers a manual alignment with room-specific choices; the mismatch
leaves it shut and the matching marks release it without another roll. The game persists
the `check:align_<room>:bearing` record and `annex.<room>.aligned` flag. Going inside
uses an ordinary `LocationExit` once released; the special surfaces and inspection are
only in the separately loaded room. None changes the objective or the story route.
Each return is unconditional and lands outside its own door. The original staff office
retains its rota, trays and hook, and remains unstaffed.

## Build and check

- Edit `tools/build_teaching_block.py`, then run `python3 tools/build_teaching_block.py`. It writes `teaching_block.tscn`, `courtyard_view.tscn` and `scenes/environment/props/teaching_block_entrance.tscn`. Use `--check` to detect stale output. `corridor.tscn` owns the environment, props, exits and spawn/interaction IDs.
- Reuse `build_outdoor_locations.build_playground()` for the view's measurements and `build_playground_art.court_landmarks()` for its painted lines and rims. Rebuild the playground graybox and art pass first if changing those shared features. The old stage generator no longer rewrites `corridor.tscn`; its material/texture definitions keep the painted kit reproducible.
- `godot --headless --resolution 1600x900 --path . --script res://tests/corridor_art_test.gd` checks the floor plan, window/yard alignment, input on the stairs and both ways of peeking, a player-capsule sweep and clear/blocked rays through the sash/pier, a real click through one 03 window, the paired biology thresholds and a click on the locked rear door, and the existing location round trips. It also enters by the new glass door on foot, clicks across the opening, reads the directory, and takes the forecourt exit. `corridor_props_test.gd` covers the original placements and routes. `location_art_test.gd` checks the visual-only exterior against the stage rules.

- `python3 tools/build_school_rooms.py --check` covers the staff office, the three restrooms, their shared fittings and all fitted leaves. `godot --headless --resolution 1600x900 --path . --script res://tests/school_rooms_test.gd` walks from 02 up to the office and down to the restroom, uses both input paths, checks the six inspections and restores in each room before taking the matching door back. See the [wing's art notes](../art/teaching_block/README.md) for matched captures.
- `python3 tools/build_school_annexes.py --check` covers six separate interiors and the measured exits/returns generated into `corridor.tscn`. `tests/school_expansion_test.gd` exercises the public washrooms, local prerequisites, deterministic success and failure, manual correction, journal notes, re-entry and Continue. No experiment under `scenes/dev` is required by a production room.
