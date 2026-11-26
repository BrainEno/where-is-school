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
| Fire stair | Descends from the lower east wing to the red fire door at yard height. Its recessed landing is also the return spawn. The same door has a push bar inside and a pull handle on the yard side. The original school gate stairs lead out to the front yard (`front_yard`), as the 01 glass entrance does; the street is past the school gate's side door there (round 16). |

The navigation mesh is baked from the same slabs, guards and sloped stair colliders the body walks on. Visible steps are individually drawn; the continuous slope keeps auto-walk from tripping at every riser. The galleries do not sit directly over each other in the camera's sightline. A shallow ceiling return, balustrades and divided window frames give the gallery depth without putting a full roof between the default camera and the player.

## Readable repetition

- Doorway arrivals declare their heading (`metadata/entry_facing`, see
  [ARCHITECTURE §5h](ARCHITECTURE.md#5h-entering-a-location-pre-flight-then-commit-implemented-contract)):
  entering from the front yard faces north into the glass (`FromTeachingEntrance`);
  coming up from the yard faces north up the fire landing (`FromSchoolyard`); the front
  yard's `FromCorridor` faces east toward the school gate, shared by the glass and the gate
  steps until those exits get their own markers; the yard's `FromCorridor` faces south, away
  from the red door.
- Each bay has front and rear doors, with separate small glazed transoms, and a 1.98 m × 0.30 m slot between them. The slot starts 2 m above the hall. Since round 24 only two slots are something to hop up to (`PEEK_BAYS`: `LowerWest2` beside the biology room on 02, `UpperWest1` at the top of the west stair on 03); the other seven are glazed and lit but are wall. At those two, use the normal **Interact** action facing the slot, or click the glass itself. Both paths stage a real physics hop; the observation is presented only after the eye has passed the opening and the body has landed. There is no new global jump action.
- The other classrooms are observations, not destinations: desks, a lectern and a rear wall are modelled behind each slot, but the biology classroom remains the only fully playable **classroom**. `104` and `202` repeat in different bays. Room depths and floor lines vary slightly behind otherwise familiar pairs of doors.
- The right-hand wall is mostly masonry. On 02 and 03, a 1.06 m sill, 2.35 m lintel line and broad piers surround each divided sash (normally about 1.8 × 1.29 m). Masonry blocks ground and depth rays; only the clear aperture has a player-only barrier. The nearest bay can fade for the follow camera, not the whole elevation. The court paint, hoops, shed and plinth share the playable yard’s source. Its concrete apron continues under the teaching block’s foundations, keeping the yard and the fire stair visually connected. This view adds no yard colliders, actors, nav or story triggers.
- Rose and petrol enamel on 01, sage and ochre public-office trim on 02, and an indigo ledger wall on 03 make repeated rooms legible even when their numbers are unreliable. See [the wing's art notes](../art/teaching_block/README.md).
- The new 01 door opens physically through the south wall; there is no central collider. Sight and pick rays pass through the side panes, but the capsule does not. Since round 16 the front yard (`front_yard`) owns the outside of the frame and its `front_yard_back_inside` returns to `FromTeachingEntrance` on the outside of the threshold; the street now sees only the school wall and its gate. `FromStreet` and `school_gate` still exist for the original 02 landing and exit, which also leads to the front yard. The glass crossing inside `corridor` requires neither a load nor an interact press.

## Yard and entrance study

The existing large glass entrance remains the main route. A small locked service gate
is an exterior wall dressing, not another exit. The stable yard shifts four metres west
of the restroom with a walkable lane back to the entrance, so the shed and toilet no
longer occupy the same apparent space. The rear playable yard and its window view use
the same shallow, locally generated earthen surface and sparse perimeter bars. Relief is
visual only: the original slab, gate openings and navigation remain unchanged. Its
source is `tools/build_yard_earth.py`; `--check` verifies the generated scene.

The 01 plan-room door is now east of the archive in a short branch behind the
directory wall; a closed classroom front separates the rooms visually. The old plan
portal is an open connection into the branch. A continuous playable yard on every
side of the building is not yet constructed. The original graybox collision and level
transitions remain in place. Visual and route testing in Godot is required.

## A wall to look at on 01

Outside the double glass doors, follow the wall towards the stable lane. The west
rose-plaster bay carries the [owner-supplied drawing](../art/teaching_block/graffiti/README.md)
as a thin layer of pigment, not a framed image. Rounded, thicker strokes feather into
fine overspray; pores in the matte, trowelled coat interrupt the paint as well as the
bare plaster. The other entrance bay keeps its existing finish. Click or tap it from the forecourt,
or face it within reach and use **Interact**. The camera holds on the whole drawing
for a few seconds and then gives control back. Its backdrop is the plaster itself:
only this close-up holds it opaque, while ordinary exploration can still fade the wall.
The indoor side stays blocked; this look adds no text, flag, destination or save.
`tests/wall_graffiti_test.gd` checks the exterior approach, camera framing and release
with both pointer and touch input.

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
| 01 | The original `restroom` at the west end, clear of the amber line to the laboratory. | The archive remains by the directory. A short east branch, entered through the former plan-room opening, puts a closed classroom before the relocated plan room. Projection moves behind the laboratory return: a dark light trap faces the bell register, only visible on its approach from the recess. Use the nick in the middle frame. Inside, a film strip loops on the wide screen and turns up again, late and pale, on the side wall. |
| 02 | `restroom_02`, east of the fire-stair turn. | The borrowed office is a single painted-over bay in the east window run; look for the lower of two print corners. The computer room is much further on, between 104 and 105, just past the yard stair on the opposite side. The grille repeats the broken raster mark; six CRTs and a room-size copy disagree by one row. |
| 03 | The original staff-office route and east-end `restroom_03` stay put. The latter has an offset enamel edge and no gate. | Principal's office remains after the north turn: two halves of its moulding don't make a point. Match the offset pins. The throne, floor axis and painted depth behind them put the room's centre in different places. |

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
At the two east-wall inserts (projection and borrowed office), the leaf and lintel
fade together under the follow camera so the slide stays visible when facing it.
Each return is unconditional and lands outside its own door. The original staff office
retains its rota, trays and hook, and remains unstaffed.

## Computer room: remembered technology

The computer room already has six CRT stations, a boot sequence and games. The
PR #318 art direction for the *whole room* is addressed separately: muted lilac
plaster and a cool floor surround the warm beige hardware, while a shallow dusk
landscape and colour bars on the west wall echo a late-2000s screen without
copying a commercial logo or image. A restrained pink bounce light joins the
existing room light. The north-wall raster, floor registration and playable CRT
remain the focal interaction and retain their original geometry. The landscape
is visual dressing only: no new collision, clues, teacher, dialogue or story state.
The remaining narrative and update-popup ideas in the supplement are not implied
to be implemented. Owner visual review in the actual camera is still needed.

## 开发试玩：从真实玻璃门开始

用 Godot `.godot-version` 打开工程。在编辑器打开 `scenes/dev/school_room_tour.tscn`，按 **F6（运行当前场景）**。也可以从项目根目录执行：

```bash
godot --path . res://scenes/dev/school_room_tour.tscn
```

屏幕左上角出现 `ROOM ART TOUR / NO STORY SAVE`，人物站在 **01 的双 01 玻璃门外**。走进大门，用 **E 面向把手**或**点把手**进房；进去后也用原门返回。试玩不读写剧情存档，只放开本次六个校准入口；门上的拨片仍可看，但试玩不用拨。正常运行（F5）和发行包没有这个入口，仍用原有校准规则；教师办公室和三个厕所本来就直通。试玩的暂停页不会显示现有剧情存档，也没有「新游戏」或「保存退出」。如果绕到操场，试玩不触发剧情结束页，仍可走原路回来。退出试玩可直接关闭窗口或停止当前场景。

| 房间 | 沿走廊怎么找 | 到了先看哪里 |
|---|---|---|
| 01 投影室 | 进玻璃门，面向楼层索引墙向左走到旧厕所以内的琥珀色折线。绕过挡墙，朝实验室走；**试铃翻牌的对面**，右手边是一扇有胶片孔的暗门。不是正对你的实验室门。 | 走到放映小车旁，等几秒看银幕的纸片移动；左墙有一张不同步的淡影。地上的光带绕开了错向的座椅。 |
| 02 借用的办公室 | 在 01 索引墙这一侧往蓝楼梯方向走，上两段到 02 后门一带。沿生物教室所在的长走廊往深处走、不上扶梯；走到 102 那段，找**对面窗带中突然封死的一跨**，留意门前两道错开的直角。 | 走到桌旁再回看墙脚：像复写纸顺墙折到了地上，桌椅实物却没压在自己的印痕上。 |
| 02 电脑课室 | 从那段走廊继续到底右拐。经过 104 和**向下通操场的支梯**，不要下楼；支梯对面略往前，104 与 105 之间有一扇少一截横格的青绿设备门。 | 比较 CRT 小屏与整面墙的大光栅，少掉的一行接到了地上的折线。 |
| 03 校长室 | 回到 02 生物教室附近的短楼梯（逆向扶梯布景），踏实走上 03。沿长廊走到底右拐，找 **204 和 205 之间**两半金边没对上的高门。 | 看访客椅朝哪里，再沿地面长线走：长线、桌子和墙上的假进深各认一个中心。 |
| 03 教师办公室 | 在校长室所在的横廊继续往 205 那头走，过 205 后看左侧的长条铁丝玻璃，帘角下面留了一片红纸。 | 看两窗之间垂下来的值班表，再看地上换了顺序的栏线；桌上值班册、传件盘和钥匙架仍能分别检视。 |
| 03 末端厕所 | 出教师办公室继续向同一侧走到端墙。沿转过角的断格瓷片，找带两块斜瓷片的小门。 | 进去还有一小段没对齐的瓷格，水池、门闩和地漏仍可近看；这不是办公室的暗门。 |

另外，01 **档案室**仍靠楼层索引墙；**图纸室**移到索引墙后方的东侧短廊，经过一扇不开放的教室门后到达。两者都可在试玩直接进入。常规版想找这些小房间，先试把手读局部痕迹，再去拨铰链侧的小铜片；不靠试铃、抬挡墙或其他房间触发。校准失手时可以照痕迹手调，不必反复掷骰。

## Exam dream layer (experimental)

`DreamAnnex` overlays an exam dream without moving the block's walls, exits or spawns.
The 02 -> 03 west stair becomes a metro escalator whose steps run down. Just through the
01 glass door on the right, three women in staff uniforms stamp in exact step. A click on
a clerk uses a brief close-up; 02's former booth space is clear. 03 becomes an exam floor
with paper room numbers, a painted seating plan, hard colour fields, turned chairs,
cliques and a troublemaker. The staff office becomes the waiting room. Behind 01, the
forecourt's west side now opens onto a walkable stable yard, with a two-storey dream
house whose only door is at its south-west corner. Rules, element map and checks are in
[EXAM_DREAM_ART.md](EXAM_DREAM_ART.md).

## Service controls and the edge of the set

- **North offset stair between 02 and 03:** the dark panel in the north balustrade has a
  small brass plunger. It raises a whole shutter 2.62 m and exposes a suspended
  half-flight with another 02 plate. This is a section of impossible building, not
  another exit: the real balustrade stays solid, and both ordinary flights stay open. The
  switch is separate from the dream layer’s escalator on the west flight.
- **01, around the laboratory return:** follow the existing amber line around the
  screen, then look along the west side wall. The test bell turns three register
  plates. The third hesitates until the bell cuts out, then shows a blank reverse.
  The assembly uses the teaching-block kit and the existing bell sample, trimmed by
  the scene's audio envelope. There is no new exterior texture or voice asset.

Both controls are optional and work by the normal mouse/touch/facing interaction.
They hold the ordinary staged beat and an authored camera shot; their finished poses
and observed notebook entries survive leaving and Continue. Reusing a finished
control offers an inspection rather than playing the movement again. No objective,
room gate, or existing exit is conditional on either control.

The repeated bay pilasters, skirts and room returns are set off the adjacent faces;
window-wall corners butt together, and the fire-door canopy and tread no longer
share planes with their neighbors. A short restoration grace in the camera fade
keeps adjacent cutaways from pulsing when the sight ray alternates across a seam.
The south end of the street has a visible works barrier where its physical road
ends. Leaving the playable floor elsewhere has a same-location fallback (see
[the placement contract](ARCHITECTURE.md#5h-entering-a-location-pre-flight-then-commit-implemented-contract)).

## Round 23: the walk-out, five different stairs, iron doors

The owner found leaving 01 for the front yard (前操场) strange - the glass entrance's apron
ended at a railing with a STREET plate on it, a balcony over the void that you had to "use"
to leave - and asked for a ground floor and doors with more character, and above all for
stairs that each look different and are not found the moment you walk in. The imagery is
the owner's novel: schools tangled into residential compounds, always grey, classrooms high
up winding stairs, fitness equipment, iron doors that are only doors, and stairs that change.

- **The walk-out.** The apron's south side is open (`guard_edges` no longer rails it). Two
  0.12 m steps (`WALKOUT_STEP`, each under the body's 0.25 m step) go down to a dirt
  forecourt at `FORECOURT_Y` in the front yard's own `yard_dirt` and trodden `yard_path`,
  between the front yard's low railings, to two brick gateposts with a 前操场 plate. The
  `EntranceToStreet` exit (in `corridor.tscn`) stands between them; `GateStop` closes the
  opening to the capsule just past it, where the soil is only seen. A waist twister (扭腰器)
  and one faint orange street lamp stand inside the rails. `GroundWingApron` now stops at
  the apron's line so it no longer covers the lower soil.
- **`flight()` styles.** `guard` is `panel` (the old balustrade), `bars` (painted iron
  balusters under a round handrail), `bare` (no handrail drawn; the sides stay closed to
  the capsule) or `wall` (a stairwell whose sides fade for the camera like other walls);
  `treads="ramp"` shaves the steps into one slope with their ghosts left on it.
  `guard_edges(..., bare=True)` draws only a kerb.
- **Blue 01 stair:** a grey concrete stairwell. At 01 it sits behind grey jambs and a raised
  roller shutter at the gallery's end (`StairwellJambNorth/South`, `StairwellLintel`), so
  nothing of it shows from the glass entrance. Its right-angle turn is piled with two bikes,
  two skateboards and roller skates (`RearStair/TurnPile`); the last flight is shaved into
  a ramp under a thin, wrinkled, wet carpet with one dim bulb on a cord (`WetCarpet`).
- **Red 03 stair:** no handrail and nearly equal bare cement steps; tyres stacked in the
  landing's corner (with a collider) and a rolled carpet along its edge.
- **North dogleg:** green iron balusters, and a pull-up bar on the half landing. The false
  half-flight behind the screen is also blocked - tyres, a rolled carpet, rubbish bags.
- **Yard stair:** walled and sunk, and flooded at the bottom (`Flood`, translucent), with big
  spiky plants in the water and on a tread, and a straight ladder up the landing wall.
- **West stair:** stays the dream annex's escalator.
- **01 ground floor:** freshly mopped cement (translucent `WetPatch*` smears at distinct
  heights) and the duty students' mop and bucket of murky water; classroom 103 behind an
  iron grille with a padlock; two iron doors in the east wing (`IronDoorWest` "↓",
  `IronDoorNorth` "01") that answer a knock with nothing (`corridor_iron_door_west/north`).

`corridor_art_test` now walks down the walk-out to `FORECOURT_GATE` before taking the exit;
`location_art_test` counts 36 corridor interactables; the `teaching_stairs` leg of
`Location art capture` frames all of the above (11 frames, after only).

## Round 24: a small ring for looking, fewer windows, a step out of the way

The owner found looks and people far too easy to select by accident - the selectable area
was much larger than the thing - and asked for Disco Elysium's cue: a small green ring on
the thing itself, and a look only when the click lands on it. While walking the hall the
protagonist kept hopping at the high windows, so not every window should be a target. The
stairs' full outline stays, but leaving the teaching block a stray touch on the stairs must
not send the player straight back in.

- **The ring.** Every interactable that is not a way out (`LocationExit`) is now marked by
  a 24 px green ring with a pale dot at the middle of what its outline used to trace, and
  is no longer outlined; doors, gates and stairs keep the outline. Details:
  [ARCHITECTURE.md](ARCHITECTURE.md), "Marker or outline".
- **Precise pointing.** A marked object is found by the pointer on its own pick boxes, or
  within 0.18 m of its anchor - not anywhere in its proximity sphere, which for the high
  windows was 1.15 m around a point in front of the glass. That sphere was what turned a
  click on the floor beside a window into a hop at it. Exits keep the sphere.
- **Windows.** Seven of the nine `high_window_*` peeks are gone (`PEEK_BAYS` in
  `tools/build_teaching_block.py`); `high_window_lowerwest2` and `high_window_upperwest1`
  remain, with the `corridor_high_window` text unchanged. `classroom_glass` and
  `corridor_wait` (the window sill) are ordinary looks, now marked and precise.
- **Out of the door, off the step.** Going out to the schoolyard (`to_schoolyard`), the
  player used to stand 1.6 m from the red fire door, inside the 1.6 m sphere of the way
  back (`pg_to_corridor`, outlining the door and its step), so the first stray click walked
  them back in. The yard's `FromCorridor` marker now has `metadata/entry_walk = 1.6`: after
  the fade-in the protagonist walks 1.6 m out into the yard on their own, then control
  comes back. `corridor_art_test` checks the walk and walks back to the door before using
  it; `companion_route_test` expects the player anywhere along that walk.
- **Down the gate steps, on toward the gate.** The stairs the owner meant are the three
  steps at the classroom end of 02 ("Go down towards the gate", `school_gate`), which lead
  out to the front yard's dirt (`front_yard`). Its `FromCorridor` marker, shared with the
  01 glass entrance, now walks 2.5 m east toward the school gate after the fade-in, so the
  glass door back in is behind the player. `corridor_art_test` checks it after the gate steps.
- **The estate stair, the same idea outside the school.** Back from the flats
  (`res_back_to_street`) the player used to stand on the street's stair landing, on the
  flight that is itself the way up (`street_to_residential`). `street/FromResidential` now
  faces down the stairs and walks 5.8 m, down all twelve steps to 0.9 m past the foot
  (`StagedActorMotion.walk_down_to`, which lets gravity bring the feet down each tread).
  `return_route_test` goes back down once and checks where the walk ends.

## Round 26: the rail gaps closed, the school wall, and the north grove

Phase 2 of the owner's campus plan ([MAP_PLAN.md](MAP_PLAN.md)): the teaching block now
stands inside the school wall (围墙), and a new walkable location - the north grove
(北面枯树小道), a mirrored L of dead trees between iron railings (铁栏杆) and the wall -
joins the dirt yard to the court. Both yards stay as they were.

- **The rail gaps closed.** The porch's two side rails (`PorchRailNorth/South`) run on
  past the steps' foot (greybox centre x -9.05, 3.0 m long, the drawn post pair respaced
  to 0.483/1.45 m), and two short rails (`PorchRailNorthGap/SouthGap`, 0.46 m, drawn as
  bar pairs turned along z) close the ~0.5 m gaps east of the landing - nothing has to
  walk there, but the keyboard could drop 0.6 m off the flight's flanks.
- **The school wall runs north.** In `front_yard.tscn` (hand-ported, the art pass is not
  rerun there): `SchoolWallNorthExt` carries the east wall from the yard rail to the
  grounds' north-east corner, `SchoolWallNorth` runs west at z -20.7 (the same line the
  grove's wall uses), both with coping, and three of the grove's dead trees stand behind
  the north railing (`DeadTree7..9`). A mouth tree (`GroveHintTree`, its crown box on the
  grove's fade layer 1024) marks the strip beside the gate's north pier, and
  `front_yard_to_grove` (`ToNorthGrove`, "Into the dead trees by the wall") stands in the
  opening. `FromGrove` is the return spawn, facing west, `entry_walk = 2.4`.
- **The north grove is its own location.** `scenes/locations/north_grove/north_grove.tscn`,
  built by `tools/build_outdoor_locations.py` (`build_north_grove()`, safe to regenerate)
  and dressed by the stage pass (`NORTH_GROVE`): the east wall along x 3.6 with the strip's
  mouth opening (z 0.0 to 1.4, a dark inset drawn in it), the north wall at z -20.7, the
  block's north face at the west end, two railing runs with three posts (the mesh runs
  along local x, so the west run takes it turned), and fifteen dead trees whose trunks
  leave weave gaps for the 0.5 m agent. `FromFrontYard` (2.8, 0, -0.5) walks north 2.6 m;
  `FromPlayground` (-23.8, 0, -18.85) walks west 2.6 m. The exits: `north_grove_to_front_yard`
  in the mouth (outlining the inset), `north_grove_to_playground` at the wall's west end
  (outlining the last post). The court reaches the strip through `playground_to_grove`
  (x 18.6, the margin east of the container, a mesh-only trunk and rail stub drawn there).
- **Stage-pass caution.** `build_stage_art.py front_yard` must NOT be rerun: the committed
  front_yard carries hand-authored stage pieces the pass would strip. The grove and the
  street/residential/alley stay regenerable.

## Round 25: two big glass doors, a porch, a side door to the lane

The owner found the way out to the front yard (前操场) confusing: the 01 glass entrance led
onto a small walled forecourt with gateposts, and 02 had its own three steps "towards the
gate". What they wanted: down the blue stair to 01, a big two-leaf glass door facing east,
a click on it, and the protagonist standing outside on a flight of steps above the dirt
yard, walking down onto it by themselves. This round is phase 1 of three agreed with the
owner (phase 2: the school wall and the narrow, iron-railed grove of dead trees that links
the dirt yard to the court; phase 3: the sports equipment moved south, a gym and the
distant buildings); see [MAP_PLAN.md](MAP_PLAN.md).

- **The doors.** `teaching_entrance()` hangs two shut leaves in the opening: each a 1.30 m
  wide, 2.64 m tall collider (`Left/LeafBody`, `Right/LeafBody`, on the leaf's body, so the
  capsule, the navigation bake and a click ray all stop there), drawn as a hinge stile, a
  meeting stile, a top rail, a kick plate (`LeafHinge`, `LeafMeet`, `LeafTop`, `LeafKick`),
  a pane and a frosted band; the pulls sit at the meeting stiles. The `EntranceToStreet` exit
  (`teaching_entrance_to_street`, "Go out to the front yard") now stands just inside them at
  (-17.65, -2.5, 14.3) and outlines the eight leaf meshes; the 01 arrival
  `FromTeachingEntrance` is inside too, at (-17.65, -3.4, 12.6), facing into the block.
- **Gone:** the walk-out forecourt, its steps, gateposts, railing, twister and lamp
  (`FORECOURT_*`, `WALKOUT_*`, `walkout()`, `yard_railing()`); the apron outside the doors
  is only drawn now, closed by two low rails (`ApronRailWest/East`) and a step at its
  foot (`porch()`). On 02 the three gate steps and their frame (`Step0..2`,
  `ExitFrame*`, `SchoolGateExit`, `school_gate`) are gone, and `GateEnd` is a full wall.
- **The porch outside (front yard).** `_front_porch()` in `tools/build_outdoor_locations.py`
  (hand-ported into the art-passed `front_yard.tscn`): a 0.6 m high concrete landing (x
  -11 to -8.65, z 12.5 to 19.1) in front of the glass doors, three 0.15 m steps of 0.35 m
  run east down to the dirt at x -7.6 (`PorchStep_0..2`, with pale nosings and one
  `PorchRamp` under them for the capsule), and iron rails along both sides of the landing
  (`PorchRailNorth/South`, camera occluders). The door, the mat and the entrance's end
  return stand on the landing. `FromCorridor` is on the landing at (-9.8, 0.6, 15.8),
  facing east, with `entry_walk = 3.0`: after the fade-in the protagonist walks down the
  steps to 0.8 m past their foot. `BackInside` (`front_yard_back_inside`) is clicked on the
  same leaves from the landing.
- **The side door to the stable lane.** With the glass doors only a click, the stink stable
  and the graffiti were left without a walk; the owner chose a plain door. `lane_door()`
  opens the gallery's south wall at x -22.65 to -20.95 (1.7 m wide so the 0.5 m navigation agent fits through, 2.2 m high, an iron-green leaf swung
  flat against the gallery wall, a steel threshold over `LaneDoorSill`), straight into the
  lane. The sprayed wall (`EntranceWallWest`) faces the lane, so the graffiti is looked at
  from there. The lane's barrier and the stable yard are unchanged.

`corridor_art_test` now goes down the blue stair to the doors and out, climbs the porch,
comes back in, checks that the leaves are shut to the capsule and that nothing bakes
outside them, and leaves again by clicking the doors; `dream_annex_test` routes to the lane
door instead of the forecourt; `wall_graffiti_test` stands in the lane; `opening_flow`,
`n_presence` and the playthrough capture leave by the glass doors; `location_art_test`
counts 35 corridor interactables and 70 front-yard shapes. The `teaching_stairs` and
`front_yard` capture legs add the doors, the lane door and the porch.

## Round 27: the equipment room, the gym's shell, and the rows lined up south

Phase 3 begins ([MAP_PLAN.md](MAP_PLAN.md)): the sketch's 器材室 becomes the front yard's
equipment room in the yard's north-east corner beside the grove's mouth, the 体育馆 rises
beyond the school wall's north-east corner - where the block's future north door will
face - and the distant rows line up south past the rail.

- **The equipment room (器材室).** In `build_outdoor_locations.build_front_yard`: a teal
  room body with an ivory plinth on the dirt (x 8.4..12.6, z -7.6..-4.2), an iron door on
  its east face under a concrete lintel, and the yard's stored gear beside it: two
  backboards stacked flat, two poles, and the ball cart. `EquipmentRoomLook`
  (`front_yard_equipment_room`, "Look at the equipment room") picks by the door; the
  room's own text is the owner's to write (`data/inspections/*/front_yard.json`, a TODO
  placeholder).
- **The gym (体育馆).** A shell beyond the wall: a 14 × 9 m body 8.6 m tall with its own
  plinth, its south face carrying a window band and two shut steel doors (stage pass, as
  children of the body so they fade with it). Nothing clickable, nothing walkable: the
  interior is a later room. The block's north door that will face it stays future work.
- **The rows south.** The stage pass adds `RowFlatsSouth` and `RowTowerSouth` beyond the
  south rail, facing the yard, so the campus reads as lined up on both sides now.
- **The block's north door (北门).** A two-leaf glass door in the lower east glazing's
  first bay, at the inner corner where the east wing turns north: the bay is carved out
  of `EastGlazing` (`NORTH_DOOR_BAY` in `tools/build_teaching_block.py`, so every later
  bay boundary stays put) and the same assembly (`teaching_block_north_door.tscn`)
  stands in the front yard's block face at its north-east corner, opening north onto the
  dirt toward the gym. Outside it is a fenced concrete pocket over the void north of the
  yard's ground: four steel rails on three sides and a person-wide opening south. A
  click lands the player in the pocket and walks them out onto the dirt
  (`front_yard/FromBlockNorth`); from the yard the same door is the way back in
  (`corridor/FromBlockNorth`). The corridor-side bay carving shifts the east glazing's
  bay numbers down by one (`Bay0_0` becomes the door bay); the corridor_wait window and
  the glass-collision test follow theirs.

`location_art_test` counts the front yard at 124 shapes and 8 interactables; the wall's
three capped piers carry a second, mesh-less collider each, as wide as its stage-pass
coping, so a sight line through a coping fades the pier the way a sight line through the
side door's lintel crosses that lintel. The street scene shares the wall and catches up:
its stage pass had been crashing since the playground rebuild dropped the route stamps it
prints (`route_mark` and `route_arrow` are back in `build_playground_art.py`), so three
grove trees it could not yet draw return over the wall. The `front_yard` capture leg adds
the equipment-room stance, the gym view, the north-door stance and the north-door view
(expect=18), and the corridor's stills gain the door from inside (expect=5).

## Round 28: inside the gym

Phase 3 closes ([MAP_PLAN.md](MAP_PLAN.md)): the sketch's 体育馆 is a room now. The shell
r27 left beyond the school wall's north-east corner gains a hall, and the wall's north run
carries its door where the grove's east leg ends.

- **The door in the school wall (体育馆的门).** In `build_outdoor_locations`: the wall's
  north run splits in two (`SchoolWallNorthWest`, `SchoolWallNorthEast`) round a gap at
  x 1.0..2.6, and a metal leaf (`SchoolWallNorthDoor`) fills the gap full height - solid,
  clickable, the way in. The grove's side builds the same wall again in its own scene
  (`GroveWallNorthWest`/`GroveWallNorthEast`/`GroveWallDoor`), and the stage pass frames
  the leaf on both faces (jambs, head, a dark inset in the grove's view; a coping cap on
  the yard's). The gym's shell and plinth return in the grove's painted distance
  (`GymShellFar`, `GymPlinthFar`, plus the terrace strip between wall and shell), dressed
  with the same window band, steel doors and plinth edge the yard paints - the strip's
  north end now reads as a way through, over the wall.
- **The hall.** `build_gym()` builds the room inside the committed shell: 14 × 9 m on the
  1.2 m plinth (the floor is the plinth top, so the yard's painted steel doors sit at
  walking height), floor on `GymFloor`, walls as camera occluders, ceiling at the shell's
  8.6 m top. The south face carries the door bay (x 5.7..7.3, split round it, head
  filled) with the steel double leaves shut and clickable - the way out
  (`gym_to_grove`, a click lands the player on the grove's east leg walking south). The
  way in lands just inside the doors and walks north up the court's mid line
  (`gym/FromGrove`).
- **The room's kit.** Four bleacher tiers (`BLEACHER_*` in `tools/build_outdoor_locations.py`)
  rise north on the north wall's foot, a full-width run; a stage platform (舞台) stands
  against the west wall, mid court; the stacked mats (垫子) and the ball cage (球架)
  fill the east corner; the scoreboard (记分牌) hangs off the east wall. The stage pass
  paints the court's lines (the border and the mid line, the playground's `court_line`
  kit), the bleacher seats' boards, the stage's boards, the doors' frame, the window
  band glowing on the south face's inside, and the scoreboard's slate face with its pale
  dashes. Three looks ship with the round's TODO placeholder (the scoreboard, the mats,
  the ball cage; `data/inspections/*/gym.json`) - the gym's own texts are the owner's.

`location_art_test` pins the front yard at 125 shapes and 8 interactables (the wall's
split), the grove at 72 shapes and 4 (the split, the leaf, the far shell's three, and
the way in's sphere and four pick boxes - a pick per MeshInstance3D under the outlined
leaf, the stage frame included), and the gym at 38 shapes and 4 (nineteen bodies, then
a sphere per interactable and a pick per mesh under each outlined node: the scoreboard
look outlines board, slate and six dashes (9), the mats two stacks (3), the cage (2),
the way out two leaves with a jamb each (5)). The `front_yard` capture
leg adds the gym-door stance and view (expect=20); the grove's leg adds its door stance,
door view and over-the-wall view (expect=4); the gym's own leg (three stances, five
views, expect=8) is new.

## Round 29: the changing room and the running track

The sketch's remaining yard labels: the 更衣室 by the equipment room, and the 操场跑道
ring on the dirt (docs/MAP_PLAN.md §5, phase 3; the 消防门 and the 东门 were rounds 25-27,
and the sketch carries no library).

- **The changing room (更衣室).** In `build_outdoor_locations.build_front_yard`: the
  equipment room's twin directly south of it (x 8.4..12.6, z -4.2..-0.8) - teal room on
  an ivory plinth, a shut iron leaf on the south face under a concrete lintel, and the
  stage pass frames the leaf (two jambs and a head, as the equipment room's).
  `ChangingRoomLook` (`front_yard_changing_room`, "Look at the changing room") picks by
  the leaf; the room's own text is the owner's to write
  (`data/inspections/*/front_yard.json`, a TODO placeholder).
- **The running track (操场跑道).** The stage pass paints the chalk ring on the dirt
  east of the block: three concentric lanes as one 9 x 15 m flat decal
  (`track_oval.png`, drawn on transparency by `paint_stage_textures.track_oval`), centred
  at (7.0, 12.0) - a clear of the side door's path, the retractable gate and the fence's
  tree at x 10.2. Paint on the ground: no collider, the ground's own body answers every
  sight line that crosses it.

`location_art_test` counts the front yard at 131 shapes and 9 interactables (the
changing room's four bodies, the look's sphere and pick box). The `front_yard` capture
leg adds the changing-room stance and the track view (expect=22).

## Round 32: the props get their parts

The owner asked for the playground, the corridor, and "bikes on the teaching block's
stairs" deepened - the bikes already existed (round 23's pile at the blue stair's turn),
so the round gave every one of these props the parts that make it read at a glance:

- **The climbing frame** (the yellow bars east of the court) grew what a climbing frame
  is recognised by, on the art layer: four braces leaning from the bar's ends to the
  ground, two rope-hung rings to grab, and a foot plate under every post. Every one of
  them is thin in x and z on purpose: the follow camera hangs a fixed offset up and
  north-east of the player, and the slice's camera sweep fails any art mesh wider than
  half a metre that a standing spot's sight line can cross - the sleeved rail and the
  window rows that were tried first all fell inside it, and the yard tree's sphere crown
  did too (the graybox box-on-a-stick tree predates the sweep and stays as it is). The
  estate walls keep only the one fitting that is narrow enough to be grazed, not
  blocking: the east block's drainpipe, its brackets and its shoe. The graybox bars,
  bodies and colliders are untouched.
- **Every bicycle grew its drive**: a chainring disc on the drive side, two pedals on
  their crank arms' ends, grips on the bar - and the parked one at the turn a wire
  basket. The pile keeps what came off the bikes: a pump where it rolled and a satchel
  slumped against the pile's edge.
- **A blue bike chained to the lane-door pier** beside the glass entrance, its chain a
  run of links to a ring bolted to the pier - the thing the player walks past every
  morning.
- **Two extinguishers** in the teaching block's primitive language (plate, red body,
  brass valve, hose): one on the ground floor beside the north iron door, one on the
  stairwell wall above the bike pile. No text on their plates, so no font subset grows.
- **The r26 grove-mouth stubs finally got their paint**: `GroveStubTree/Rail` had been in
  the playground's graybox since round 26 with no art material, which had silently
  blocked every later rerun of the art pass ("graybox meshes without an art material").
  They are trunk and ink now, and the pass runs again.
- The preview raster learned `SphereMesh` (bounding-box ellipsoid), which the new crowns
  needed.

New capture legs: the playground details gain the frame's rings and braces (expect=5),
the teaching stairs gain the porch bike (expect=13).

## Round 31: the doors behave, and the street stops being boxes

Two threads:

- **The doors' people audit.** Every exit that refuses the player was read against its
  text and its cast: the classroom door is the only one whose blocked text says someone
  is watching, and it is the only one with a watcher - Q, through the framing, following
  and release machinery of `ExitWatch` (#174). The corridor's six plates are a physics
  puzzle whose text promises nobody, and nobody stands there; the porch and the site are
  TODO texts with no people promised. The cast that does exist - Q and N's classroom
  seats and entry choreography, B's stage gate, the roof collector's search route - all
  behave. Nothing to fix.
- **The street's rough models refined.** The two flat blocks were brick boxes with glass
  stuck on: every window now has a frame - two jambs, a head, a proud sill - and the west
  face grows air-conditioners, a drainpipe with brackets and a shoe, parapets on both
  blocks, and block B a water tank on legs and a roof vent. The shopfront grew a glazed
  door in its own frame with a threshold, guide rails for the shutter, a sign that
  projects on two arms, a lamp over the door, a valance under the awning and a stack of
  crates by the shutter; the wall gained its coping and a lamp at the crossing. All mesh
  -only except the two crates the player could walk into: the street is at 102 shapes.

## Round 30: the bubble follows the pointer, the walk-through audit, and the street's details

Three threads in one round:

- **The talk bubble follows the pointer** (the closed pull request #426, taken over and
  fixed): a person's talk mark is a screen-space speech bubble beside the pointer now, its
  tail on the pointer while the pointer is on the person's screen box and on the point
  above their head when it is not; it mirrors before it would cross the right edge. The
  look ring keeps the green for objects; `Palette.LOOK_GREEN` is the one green. The parse
  error that broke opening the project is the fix the round is named for here: the bubble
  had defined `get_anchor()` on a `Control`, whose own `get_anchor(Side) -> float` a
  signature may not shadow - it is `tail_anchor()` now.
- **The walk-through audit.** Every exit's prompt matches its destination (all fourteen
  keys re-read against their scenes), the exit graph is closed (every exit pairs with a
  spawn back), and every spawn walks away from the door it came through. Two fixes: the
  grove's gym arrival had been facing north - into the door it just left - and now walks
  south down the east leg; the yard's street arrival had been dropped still, facing north
  along the wall, and now faces west onto the dirt with the round-26 entry walk. The maze
  stays in the art and the hidden mouths (the grove's inset, the wall's door), not in
  blocked paths.
- **The street's details.** Mesh-only dressing east of the road: a second lamp post, the
  zebra crossing at the ditch slabs (twelve pale stripes), a manhole, three bollards on
  the kerb line, a bench by the shop, and the shopfront's blank sign under an awning with
  a poster beside the shutter and one on the flats. Nine bodies (lamp, bollards, bench,
  awning, sign) put the street at 100 shapes; the paint adds none. The `street_details`
  capture leg (two stances, three views, expect=5) is new.

## Build and check

- Edit `tools/build_teaching_block.py` (or `tools/build_dream_annex.py`), then run `python3 tools/build_teaching_block.py`. It writes `teaching_block.tscn`, `dream_annex.tscn` (with the stink stable's meshes in `stable_meshes/`), `courtyard_view.tscn` and `scenes/environment/props/teaching_block_entrance.tscn`. Use `--check` to detect stale output. `corridor.tscn` owns the environment, props, exits and spawn/interaction IDs.
- Reuse `build_outdoor_locations.build_playground()` for the view's measurements and `build_playground_art.court_landmarks()` for its painted lines and rims. Rebuild the playground graybox and art pass first if changing those shared features. The old stage generator no longer rewrites `corridor.tscn`; its material/texture definitions keep the painted kit reproducible.
- `godot --headless --resolution 1600x900 --path . --script res://tests/corridor_art_test.gd` checks the floor plan, window/yard alignment, input on the stairs and both ways of peeking, a player-capsule sweep and clear/blocked rays through the sash/pier, a real click through one 03 window, the paired biology thresholds and a click on the locked rear door, and the existing location round trips. It also comes in from the front yard's porch, checks the shut glass doors, reads the directory, and leaves by clicking the doors. `corridor_props_test.gd` covers the original placements and routes. `location_art_test.gd` checks the visual-only exterior against the stage rules.

- `python3 tools/build_school_rooms.py --check` covers the staff office, the three restrooms, their shared fittings and all fitted leaves. `godot --headless --resolution 1600x900 --path . --script res://tests/school_rooms_test.gd` walks from 02 up to the office and down to the restroom, uses both input paths, checks the six inspections and restores in each room before taking the matching door back. See the [wing's art notes](../art/teaching_block/README.md) for matched captures.
- `python3 tools/build_school_annexes.py --check` covers six interiors, the shared CRT cabinet and the exits/returns generated into `corridor.tscn`. `tests/school_expansion_test.gd` exercises the public washrooms, local prerequisites, deterministic success and failure, manual correction, journal notes, re-entry and Continue. Its `-- --room-tour` leg starts at the actual 01 glass door, walks to the recess, uses the open doors and checks that they leave no alignment or save. No experiment under `scenes/dev` is required by a production room.
- `tests/school_facilities_test.gd` walks to both controls, observes their intermediate
  states, checks entry/Continue and walks back out. `Location art capture` also runs
  it under Xvfb, capturing three stages of each mechanism from the gameplay camera.
  `tests/fall_recovery_test.gd` walks into the street barrier and off an unguarded
  edge. `tests/occluder_seam_test.gd` alternates the sight ray over adjacent occluders.
