# Classroom visual slice — sources and colour system

*中文版：[README.zh-CN.md](README.zh-CN.md)*

This folder holds the **source** of the classroom's painted look. Godot does not import it
(`.gdignore`), and `export_presets.cfg` already excludes `art/*` from the export.

- `paint_classroom_textures.py` paints every PNG under
  `assets/materials/classroom/textures/` and writes each one's `.import` sidecar.
  Requires Pillow 11.3.0 and NumPy 2.2.6, and repaints byte-identical files:
  `python3 art/classroom/paint_classroom_textures.py`. Verify without writing with
  `python3 art/classroom/paint_classroom_textures.py --check`.

Nothing in the room is a static background image. Every wall, the floor, the board and
the windows are still the 3D geometry the graybox had. The paint is applied to them as
textures, on quads that sit 4 mm in front of wall bodies and 3 mm above the floor. Those quads are
children of the bodies, so the camera occluder fades them along with their wall.

## Identity: what makes this room *this* classroom

The classroom is a 14 × 10 m space with a quiet cool-gray concrete floor, a low concrete
teacher's platform with a real step, and a boxed standing lectern. Twelve student desk/chair
assemblies sit in four columns by three rows, leaving broad cross-aisles and routes to the
board, doors and story props. Facing the board, both doors are in the right-hand (east)
wall (issue #159): the grey front door near the board is the corridor exit, the white rear
door never opens. The blackboard wall is one unbroken wall, with a roll-down projection
screen over the left half of the board and a projector under the ceiling. The front west
window is an ordinary window; the back one is a hole through the wall behind a
floor-to-ceiling blackout curtain. The space above
the board stays empty; the former red pseudo-writing banner and its generation code have been deleted. There is no screen-wide "oil paint" filter. Walls and functional props
keep `StandardMaterial3D` (toon diffuse, no specular). The student desks replace their
photographic PBR surface with the classroom-owned `student_wood.tres`, referencing the
existing environment pigment shader read-only. There is no photographic albedo/normal/ORM
under a transparent wash anymore; the model and shared wrapper are unchanged.

## Colour system (sRGB)

| Role | Colour | Used for |
|---|---|---|
| Ink | `#2E2933` | Selected prop contours (inverted-hull outline, 6 mm), wall seams, room corners, floor edge |
| Section | `#4F4754` | Wall tops and outer faces: the room reads as a cut-away model |
| Plaster | `#CEC2BB` / light `#E9D5AB` / shade `#9697A7` | Upper walls: broad vertical brush planes |
| Wainscot | `#47656F` / dark `#364555` | The band under 1.05 m, skirting, window frames |
| Floor | `#7E848C` base / cool mineral gray | Broken trowel strokes, light scuffs and soft concrete mottling; no plank grain |
| Teacher's platform | Cool concrete (`cement_stage.tres`) | Physically raised 0.12 m, with a lower broad approach step |
| Board | `#243D3F` + chalk `#D6DCCE` | The wiped-not-quite front board, the old chalk newspaper on the back wall |
| Oxblood lacquer | `#6E3C36` | Board frame, teacher's desk panels: the *authority* objects |
| Door grey / door white | `#7D8287` / `#E6E3D9` | The two door leaves (`door_gray`, `door_white`) in teal frames (`trim_teal`) |
| Blackout navy | `#1B2441` | The back window's floor-to-ceiling curtain (`curtain_blackout`) |
| Screen matte | `#EDE6CC` | The roll-down projection screen (`screen_matte`) |
| Apricot | `#E0A569` / pale `#EFCD97` | The impossible late light: the window view, its spill on the wall, its shapes on the floor |
| Honey wood | `#A98458` | Teacher's desk top, chalk tray; the student desk pigment anchors |
| Worn wood | `#998775` | Student chairs: deliberately quieter |
| Mustard canvas | `#BE963E` | The schoolbag: the first thing the player is sent to |
| Cobalt | `#40568C` | The register's cover, readable but matte rather than glossy |

### Hierarchy rules

1. **Broad planes stay quiet.** Walls and floor have colourfulness ≤ 0.20
   (max − min of the mean sRGB colour).
2. **Every object the player is meant to look at separates from its backdrop** by at
   least 0.15, in value or in colourfulness: board against wall, schoolbag against the
   chair it hangs on, window against wall, set square and register against the desk top,
   door frames and the white rear door against the east wall, the blackout curtain
   against the west wall, the rolled-down screen against the board.
3. **Repeated furniture does not compete.** The repeated chairs stay at least 0.15 less
   colourful than the schoolbag.
4. **Ink is for edges, not texture.** Lines go on contours, seams and the few graffiti
   marks. They do not cover walkable floor or interactables.

`tests/classroom_visual_slice_test.gd` measures all four rules on the shipped textures.

## Graphic marks, each with a reason

- **Front wall:** a cut-paper shadow behind the board, chalk dust wiped onto the wall, and
  a pencil height chart someone started by the door and gave up on.
- **Window wall:** apricot spill and a painted reveal around the front window. The back
  window is a real hole cut through the wall and its paint; nothing is painted round it.
- **East wall:** both doorways, and between them pale ghosts of notices that have been
  taken down, with their tape.
- **South wall:** an old chalk newspaper in coloured chalk (a leaf, a fish skeleton, a flower; nothing legible).
- **Blackboard wall:** one unbroken wall since issue #159; the doors moved to the east wall.
- **Front board:** heading and date-column ghosts under the eraser arcs, which match the
  inspection text (*LAST TERM — REVISION*, a date three weeks old). They are kept
  illegible on purpose, so the board needs no localisation.
- **Above the board:** deliberate negative space; no replacement text or glyph decoration.

## Inspection texts → scene

| Text says | Scene has |
|---|---|
| Board wiped, then not quite; chalk tray with one broken stick and a clip | `Board/Face` texture, `ChalkBrokenEnd`, `Clip`, chalk dust on the tray |
| Two panes, one cracked and taped; wet concrete, low wall, bins; late-afternoon light | `WindowGlass0` (crack + tape), `window_view.png` |
| (curtain lines) The front window is ordinary, washing pegged out on a line; the back window has its curtain drawn | `window_view.png`, window 0's third only (s 3.0–4.5 m) carries the washing; `Anomalies/BackCurtain` (`WindowCurtain`, procedural, `curtain_blackout`) hangs from its track 0.18 m off the west wall, 3.3 m wide, from 3.14 m down to the floor, over the opening at z 0.95–3.45 |
| (curtain lines) Behind the curtain: no glass, the wall's own thickness, then nothing | A real hole through `WallWest` (y 0.50–2.75): the shell and paint are cut into `SouthShell`/`SillShell`/`HeaderShell` and `PaintSouth`/`PaintSill`/`PaintHeader`; there is no glass, frame, view or backdrop behind it. `Anomalies/VoidOpening` is only a marker in the hole. The wall's collision stays whole |
| The second door never opens, unless special means are used | `WallEast/RearDoor` (`classroom_door.tscn`, white leaf), a plain inspection (`classroom_rear_door`); nothing opens and no staircase is placed in this room |
| Set square, forearm length, pale varnish, split corner taped with browned tape, taped corner faces the room | `set_square.tscn` now lies flat (0.55 × 0.42 m; the prism's size axes were swapped), `TapeRepair` in browned tape, ink ticks |
| Own desk: scratched-out name, half-peeled sticker, groove along the front edge | `Furniture/DeskB2/DeskMarks` decal |
| Teacher's desk: register in plastic, stapler, mug of chalk, chair pushed in at an angle, tidier | `Register` + label, `Stapler`, `Mug` with three sticks, `Papers`, the new `Chair` |
| Timetable: coffee ring, teacher's name lined out in biro | `TimetableSheet/Face` |
| Schoolbag: canvas, one strap | Mustard canvas, one `Strap`, a side pocket; it hangs on the back of your chair (`Furniture/DeskB2/Chair/Schoolbag`), not on the floor |

## Material and reuse contract

The full synchronized classroom chapter in `docs/ART_BIBLE.md` /
`docs/ART_BIBLE.zh-CN.md` records material tiers, palette ranges, contour eligibility,
brush density and reuse in later locations. Walls are authored opaque, back-face culled
and depth-writing; only temporary camera obstruction relief may fade them. Forward+
uses instance transparency alone, while Compatibility/Mobile need material-alpha copies.
Do not multiply both. `tests/classroom_wall_render_test.gd` compares actual pixels against
a single-alpha control; `tests/capture_classroom_art.gd` records the actual classroom. Both run on
Forward+ and Compatibility in `.github/workflows/classroom-art-evidence.yml`, each with its own
verdict (issue #150; see `docs/screenshots/classroom_art_review/README.md`, section 8).
Glass remains the deliberate surface-alpha exception.

The generator uses Godot 4.7.2's canonical 34-character UID encoding; check the sidecars
again after a real import to catch editor rewrites. Curated actual before/after frames,
pixel measurements, baseline-noise comparison and explicit platform limits are recorded
in `docs/screenshots/classroom_art_review/README.md`. Runtime evidence is not a substitute
for owner art review or target-GPU acceptance.

## Geometry and gameplay contract

The classroom shell is 14 × 10 m with a 3.2 m wall height. Every wall keeps one whole
collision box; openings are cut only in what is drawn. The north/blackboard wall is one
14 m wall. The east wall has two 1.2 × 2.2 m door openings centred at z −3.55 (front,
`WallEast/FrontDoor`, grey) and z +3.55 (rear, `WallEast/RearDoor`, white), both the
owner's door model dressed in classroom materials, with plaster behind them; its shell and
paint are cut into the long pier, two end piers and two lintels, each sampling its own
slice of `wall_east.png`. `classroom_door` retains its original ID, blocked inspection and
corridor destination, and now stands in front of the front door. The west wall is cut the
same way round the back window's hole. Two marker nodes, `WindowCurtainMount0` and
`WindowCurtainMount1`, mark the curtain attachment points (the second is the blackout
curtain's track). The projection screen (`WallNorth/ProjectorScreen`) is rolled up when
the room loads; `Interactables/ProjectorScreenPull` rolls it down and up again, and
nothing about it is saved. The schoolbag hangs on the back of the protagonist's chair
(`Furniture/DeskB2/Chair/Schoolbag`); the player wakes in that chair (`PlayerStart`), and
Q starts a little way down the aisle and walks to `QOpeningTalk`, at the player's left,
before the first line (the opening's Q beat, #160). The stage and its step are actual colliders: the 0.12 m rise stays below the
player's 0.25 m step-up and the navmesh's 0.25 m climb. The standing lectern on the stage
is separate from the retained inspection desk. Q/N states, inspection IDs, `Sun`,
`WorldEnvironment` and the classroom-to-corridor transition remain in place.

### The teacher's lectern (#172)

`Stage/Lectern` is an instance of `scenes/environment/props/teacher_lectern.tscn`, which
replaced the round top on a tapering column the owner rejected. It is a standing lectern of
the kind university classrooms use: a honey-wood carcass from the floor up (two sides, a
closed front panel towards the room with an oxblood band, a dark toe), two open shelves and
an apron on the teacher's side, and a reading board sloping towards the teacher with a
book lip, side galleries and a back rail, carrying a stack of lesson papers and the blue
register. Godot primitives and the room's own materials only.

| Measure | Value | Basis |
|---|---|---|
| Carcass | 0.80 W × 0.44 D m; board 0.90 × 0.52 m | CSULB's Freedom One lectern, 36.25 in W × 30 in D, a little shallower so the stage keeps a walk behind it |
| Reading surface | 0.96 m at the teacher's edge, 1.04 m at the room's (8.75° slope), above the stage | 36-42 in (0.91-1.07 m) lecterns (CSULB, MSU, UConn) for an adult of about 1.75 m, scaled to N's 1.65 m: 0.58 of N's height, just under the elbow |
| Collision | `Body` box 0.84 × 1.04 × 0.54 m | it now carves the navmesh and stops the player; the old lectern had no collider |

Two markers belong to the lectern, so nothing else carries its coordinates: `TeacherStand`
(0.54 m behind its centre, on the stage) and `WorkSurface` (the teacher's edge of the
board). `NEntryPath` now ends there: past the right side of the lectern (`BesideLectern`),
along behind it (`BehindLectern`), and a last short step to `AtFront`, which is the
`TeacherStand` spot - the step towards the room is the leg `NpcActor.walk_along` turns N
to, so N ends facing the students instead of the board. `classroom_visual_slice_test.gd`
pins `AtFront` to `TeacherStand` and checks N's height against the surface, that N does not
overlap the lectern, that its head and shoulders stay above it and that the walk does not
pass through it.

`tests/classroom_visual_slice_test.gd` retains the previous colour, texture, inspection,
wall-fade, camera and navigation checks, and now also asserts the expanded shell, all 12
seats, the two east-wall doors, the unbroken blackboard wall, the screen and projector,
physical step/platform, the standing lectern and N's place at it, curtain markers and all
three initial story positions. `tests/capture_classroom_art.gd` produces fourteen real
1600 × 900 images, including the architectural views, the screen rolled down, the back
window's opening and four of the lectern (front, side, teacher's side, game camera); it
rejects headless output. The `Classroom visual evidence` PR workflow renders the fourteen views
under Godot 4.7.2 Stable and publishes them as a downloadable CI artifact.
