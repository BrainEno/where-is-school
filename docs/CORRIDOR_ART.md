# The teaching block

The 16 m walkway and the inaccessible 96 m continuation from #243 gave way to a walkable teaching block, now with three storeys. The space is still called `corridor` in the location catalog, save files and story. The route gets strange because it is possible to walk around it, see the same room numbers twice, and come back at a different height, not because a painted façade gets longer.

## Walkable section

| Part | Layout |
|---|---|
| Floor 01 | The entrance forecourt and directory gallery are at yard height. The amber rule turns into a recess to the optional laboratory. The mint plate at the west end marks the restroom, not the lab. The blue stair meets 02 through the rear junction. |
| Floor 02 | The biology classroom door pair, props and gate are at the south end. The west gallery runs north for 37 m, then turns east along the yard. Both runs have classrooms on the left and glazed bays on the right when walking away from the gate. |
| Floor 03 | Set back west and north of 02, 3.6 m above it. The top of either stair opens into a gallery of five classroom bays: three before the turn, two after it. The staff-office leaf is set in the last bay near the east end. There are five more bays on 02; the red stair also meets this level from the rear junction. |
| West stair | A straight flight near the biology room, crossing between the set-back floors. |
| North stair | Two flights, offset sideways by 4.5 m at the half landing. The opening at the top is not above the opening where the player set off. Both stairs work in both directions and form one continuous loop with the two galleries. |
| Fire stair | Descends from the lower east wing to the red fire door at yard height. Its recessed landing is also the return spawn. The same door has a push bar inside and a pull handle on the yard side. The original school gate stairs still lead to the street. |

The navigation mesh is baked from the same slabs, guards and sloped stair colliders the body walks on. Visible steps are individually drawn; the continuous slope keeps auto-walk from tripping at every riser. The galleries do not sit directly over each other in the camera's sightline. A shallow ceiling return, balustrades and divided window frames give the gallery depth without putting a full roof between the default camera and the player.

## Readable repetition

- Each bay has front and rear doors, with separate small glazed transoms, and a 1.98 m × 0.30 m slot between them. The slot starts 2 m above the hall. Use the normal **Interact** action facing it, or click the glass. Both paths stage a real physics hop; the observation is presented only after the eye has passed the opening and the body has landed. There is no new global jump action.
- The other classrooms are observations, not destinations: desks, a lectern and a rear wall are modelled behind each slot, but the biology classroom remains the only fully playable **classroom**. `104` and `202` repeat in different bays. Room depths and floor lines vary slightly behind otherwise familiar pairs of doors.
- The right-hand glazing keeps the player inside but lets the camera and mouse see through. The court paint, hoops, shed and plinth share the playable yard’s source. Its concrete apron continues under the teaching block’s foundations, keeping the yard and the fire stair visually connected. This view adds no yard colliders, actors, nav or story triggers.
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

## Optional rooms at the ends

The 03 office is next to the solid Hour Register; the 01 restroom does not interrupt the
amber route around the laboratory screen. Each fitted leaf is instantiated on both sides.
The interactable is on the occupied side of the leaf; clicking it or facing it and pressing
Interact uses the existing fade-and-load transition. They are not holes into a second
floor baked under the corridor. Return spawns are `FromStaffOffice` and `FromRestroom`.

The duty-sheet master is independent of the playground board. There is no roll, new
objective, named staff assignment or appearance by B. The rest of the optional detail is
immediately observable: slips in the OUT tray, a bare key hook, a mirror clip, the closed
cubicle's latch and a tile repair. No observation prevents using a door. This implements
local game content from the repository brief, not a sequence transcribed from a manuscript.

## Build and check

- Edit `tools/build_teaching_block.py`, then run `python3 tools/build_teaching_block.py`. It writes `teaching_block.tscn`, `courtyard_view.tscn` and `scenes/environment/props/teaching_block_entrance.tscn`. Use `--check` to detect stale output. `corridor.tscn` owns the environment, props, exits and spawn/interaction IDs.
- Reuse `build_outdoor_locations.build_playground()` for the view's measurements and `build_playground_art.court_landmarks()` for its painted lines and rims. Rebuild the playground graybox and art pass first if changing those shared features. The old stage generator no longer rewrites `corridor.tscn`; its material/texture definitions keep the painted kit reproducible.
- `godot --headless --resolution 1600x900 --path . --script res://tests/corridor_art_test.gd` checks the floor plan, window/yard alignment, input on the stairs and both ways of peeking, a player-capsule sweep against the glass, a click through the same glass, the paired biology thresholds and a click on the locked rear door, and the existing location round trips. It also enters by the new glass door on foot, clicks across the opening, reads the directory, and takes the forecourt exit. `corridor_props_test.gd` covers the original placements and routes. `location_art_test.gd` checks the visual-only exterior against the stage rules.

- `python3 tools/build_school_rooms.py --check` covers the two room scenes and both shared leaves. `godot --headless --resolution 1600x900 --path . --script res://tests/school_rooms_test.gd` walks from 02 up to the office and down to the restroom, uses both input paths, checks the six inspections and restores in each room before taking the matching door back. See the [wing's art notes](../art/teaching_block/README.md) for matched captures.
