# The teaching block

The 16 m walkway and the inaccessible 96 m continuation from #243 are replaced by a two-floor building. The space is still called `corridor` in the location catalog, save files and story. The route gets strange because it is possible to walk around it, see the same room numbers twice, and come back at a different height, not because a painted façade gets longer.

## Walkable section

| Part | Layout |
|---|---|
| Floor 01 | The biology classroom door pair, props and gate are at the south end. The west gallery runs north for 37 m, then turns east along the yard. Both runs have classrooms on the left and glazed bays on the right when walking away from the gate. |
| Floor 02 | Set back west and north of 01, 3.6 m above it. The top of either stair opens into a gallery of five classrooms: three before the turn, two after it. There are five more bays on 01. |
| West stair | A straight flight near the biology room, crossing between the set-back floors. |
| North stair | Two flights, offset sideways by 4.5 m at the half landing. The opening at the top is not above the opening where the player set off. Both stairs work in both directions and form one continuous loop with the two galleries. |
| Fire stair | Descends from the lower east wing to the red fire door at yard height. Its recessed landing is also the return spawn. The same door has a push bar inside and a pull handle on the yard side. The original school gate stairs still lead to the street. |

The navigation mesh is baked from the same slabs, guards and sloped stair colliders the body walks on. Visible steps are individually drawn; the continuous slope keeps auto-walk from tripping at every riser. The two floors do not sit directly over each other in the camera's sightline. A shallow ceiling return, balustrades and divided window frames give the gallery depth without putting a full roof between the default camera and the player.

## Readable repetition

- Each bay has front and rear doors, with separate small glazed transoms, and a 1.98 m × 0.30 m slot between them. The slot starts 2 m above the hall. Use the normal **Interact** action facing it, or click the glass. Both paths stage a real physics hop; the observation is presented only after the eye has passed the opening and the body has landed. There is no new global jump action.
- The other classrooms are observations, not destinations: desks, a lectern and a rear wall are modelled behind each slot, but the biology classroom remains the only open, fully playable interior. `104` and `202` repeat in different bays. Room depths and floor lines vary slightly behind otherwise familiar pairs of doors.
- The right-hand glazing keeps the player inside but lets the camera and mouse see through. The court paint, hoops, shed and plinth share the playable yard’s source. Its concrete apron continues under the teaching block’s foundations, keeping the yard and the fire stair visually connected. This view adds no yard colliders, actors, nav or story triggers.
- Cool low light, small pools of amber and a muted ruled floor extend the biology-room palette. The fog begins beyond the follow camera's offset, and the height component stays below the fire stair. It separates depth planes; it no longer hides the end of a fake corridor.

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

## Build and check

- Edit `tools/build_teaching_block.py`, then run `python3 tools/build_teaching_block.py`. It writes `teaching_block.tscn` and `courtyard_view.tscn` in `scenes/locations/corridor/`. Use `--check` to detect stale output. `corridor.tscn` owns the environment, props, three exits and stable spawn/interaction IDs.
- Reuse `build_outdoor_locations.build_playground()` for the view's measurements and `build_playground_art.court_landmarks()` for its painted lines and rims. Rebuild the playground graybox and art pass first if changing those shared features. The old stage generator no longer rewrites `corridor.tscn`; its material/texture definitions keep the painted kit reproducible.
- `godot --headless --resolution 1600x900 --path . --script res://tests/corridor_art_test.gd` checks the floor plan, window/yard alignment, input on the stairs and both ways of peeking, a player-capsule sweep against the glass, a click through the same glass, the paired biology thresholds and a click on the locked rear door, and round trips through the three original exits. `corridor_props_test.gd` covers the original placements and routes. `location_art_test.gd` checks the visual-only exterior against the stage rules.
