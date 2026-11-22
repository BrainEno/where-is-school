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
| 01 | The original `restroom` at the west end, clear of the amber line to the laboratory. | Archive and plan room stay by the directory. Projection moves behind the laboratory return: a dark light trap faces the bell register, only visible on its approach from the recess. Use the nick in the middle frame. Inside, a film strip loops on the wide screen and turns up again, late and pale, on the side wall. |
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

另外，01 **档案室**和**图纸室**仍靠楼层索引墙，可在试玩直接进入。常规版想找这些小房间，先试把手读局部痕迹，再去拨铰链侧的小铜片；不靠试铃、抬挡墙或其他房间触发。校准失手时可以照痕迹手调，不必反复掷骰。

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

## Build and check

- Edit `tools/build_teaching_block.py` (or `tools/build_dream_annex.py`), then run `python3 tools/build_teaching_block.py`. It writes `teaching_block.tscn`, `dream_annex.tscn` (with the stink stable's meshes in `stable_meshes/`), `courtyard_view.tscn` and `scenes/environment/props/teaching_block_entrance.tscn`. Use `--check` to detect stale output. `corridor.tscn` owns the environment, props, exits and spawn/interaction IDs.
- Reuse `build_outdoor_locations.build_playground()` for the view's measurements and `build_playground_art.court_landmarks()` for its painted lines and rims. Rebuild the playground graybox and art pass first if changing those shared features. The old stage generator no longer rewrites `corridor.tscn`; its material/texture definitions keep the painted kit reproducible.
- `godot --headless --resolution 1600x900 --path . --script res://tests/corridor_art_test.gd` checks the floor plan, window/yard alignment, input on the stairs and both ways of peeking, a player-capsule sweep and clear/blocked rays through the sash/pier, a real click through one 03 window, the paired biology thresholds and a click on the locked rear door, and the existing location round trips. It also enters by the new glass door on foot, clicks across the opening, reads the directory, and takes the forecourt exit. `corridor_props_test.gd` covers the original placements and routes. `location_art_test.gd` checks the visual-only exterior against the stage rules.

- `python3 tools/build_school_rooms.py --check` covers the staff office, the three restrooms, their shared fittings and all fitted leaves. `godot --headless --resolution 1600x900 --path . --script res://tests/school_rooms_test.gd` walks from 02 up to the office and down to the restroom, uses both input paths, checks the six inspections and restores in each room before taking the matching door back. See the [wing's art notes](../art/teaching_block/README.md) for matched captures.
- `python3 tools/build_school_annexes.py --check` covers six interiors, the shared CRT cabinet and the exits/returns generated into `corridor.tscn`. `tests/school_expansion_test.gd` exercises the public washrooms, local prerequisites, deterministic success and failure, manual correction, journal notes, re-entry and Continue. Its `-- --room-tour` leg starts at the actual 01 glass door, walks to the recess, uses the open doors and checks that they leave no alignment or save. No experiment under `scenes/dev` is required by a production room.
- `tests/school_facilities_test.gd` walks to both controls, observes their intermediate
  states, checks entry/Continue and walks back out. `Location art capture` also runs
  it under Xvfb, capturing three stages of each mechanism from the gameplay camera.
  `tests/fall_recovery_test.gd` walks into the street barrier and off an unguarded
  edge. `tests/occluder_seam_test.gd` alternates the sight ray over adjacent occluders.
