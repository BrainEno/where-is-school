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
| Teacher's platform | Poured concrete from the biology-classroom experiment, without the floor's ruling (`platform_concrete.tres`, `shaders/concrete.gdshader`) | Physically raised 0.12 m, with a lower broad approach step |
| Board | `#243D3F` + chalk `#D6DCCE` | The wiped-not-quite front board, the old chalk newspaper on the back wall |
| Oxblood lacquer | `#6E3C36` | Board frame, the lectern's front band: the *authority* objects |
| Door grey / door white | `#7D8287` / `#E6E3D9` | The two door leaves (`door_gray`, `door_white`) in teal frames (`trim_teal`) |
| Blackout navy | `#1B2441` | The back window's floor-to-ceiling curtain (`curtain_blackout`) |
| Screen matte | `#EDE6CC` | The roll-down projection screen (`screen_matte`) |
| Apricot | `#E0A569` / pale `#EFCD97` | The impossible late light: the window view, its spill on the wall, its shapes on the floor |
| Honey wood | `#A98458` | The lectern's carcass, chalk tray; the student desk pigment anchors |
| Worn wood | `#998775` | Student chairs: deliberately quieter |
| Indigo canvas | `#274774` | The schoolbag: a cool woven accent against the warm desk and the first thing the player looks for |
| Cobalt | `#40568C` | The register's cover, readable but matte rather than glossy |

### Hierarchy rules

1. **Broad planes stay quiet.** Walls and floor have colourfulness ≤ 0.20
   (max − min of the mean sRGB colour).
2. **Every object the player is meant to look at separates from its backdrop** by at
   least 0.15, in value or in colourfulness: board against wall, schoolbag against the
   wood of the desk and chair, window against wall, set square and register against the desk top,
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
- **Painted absences (from the biology-classroom experiment):** two flat violet-ink marks,
  drawn unshaded so they do not answer the real light (`ink_shadow_*.tres`, textures from
  `paint_classroom_textures.py`). `WallNorth/InkShadowFigure` is a shadow nobody in the room
  casts: a tall, stooped figure with a set square raised, rising off the platform on the
  front wall beside the lectern. `Props/InkShadowSquare` is the set square's long shadow,
  from the platform's foot under the lectern across the floor to the front edge of your
  desk (B2). They are scenery: no collision, no interaction, and the figure fades with
  the wall it is painted on.

## Inspection texts → scene

| Text says | Scene has |
|---|---|
| Board wiped, then not quite; chalk tray with one broken stick and a clip | `Board/Face` texture, `ChalkBrokenEnd`, `Clip`, chalk dust on the tray |
| Two panes, one cracked and taped; wet concrete, low wall, bins; late-afternoon light | `WindowGlass0` (crack + tape), `window_view.png` |
| (curtain lines) The front window is ordinary, washing pegged out on a line; the back window has its curtain drawn | `window_view.png`, window 0's third only (s 3.0–4.5 m) carries the washing; `Anomalies/BackCurtain` (`WindowCurtain`, procedural, `curtain_blackout`) hangs from its track 0.18 m off the west wall, 3.3 m wide, from 3.14 m down to the floor, over the opening at z 0.95–3.45 |
| (curtain lines) Behind the blue curtain: the room ends, without a view or a window | The west wall, trim and skirting stop at the cut (y 0–3.2, z 0.95–3.45), exposing the near-black world background; there is no backdrop mesh or paper effect. The two solid wall sections match the shells. A third shape, only for the closed curtain, unregisters when it opens. `VoidStep` is a non-solid trigger past the lip that uses the same staged fall as choosing to step out. The front glass has no cloth in front of it. |
| The second door never opens, unless special means are used | `WallEast/RearDoor` (`classroom_rear_door.tscn`, white variant of `classroom_door.tscn`), a plain inspection (`classroom_rear_door`); nothing opens and no staircase is placed in this room |
| Set square, forearm length, pale varnish, split corner taped with browned tape, taped corner faces the room | `set_square.tscn` lies flat (0.55 × 0.42 m; the prism's size axes were swapped), `TapeRepair` in browned tape, ink ticks. It lies on the lectern's sloped top (`Props/SetSquare`, tilted with the reading surface, resting on the register), since the low teacher's desk was taken out |
| Own desk: scratched-out name, half-peeled sticker, groove along the front edge | `Furniture/DeskB2/DeskMarks` decal |
| Lectern (the `classroom_teacher_desk` inspection): much taller than the desks, a register in plastic, lesson notes, the set square | `Stage/Lectern` with `Body/Register`, `Body/LessonPapers` and the set square on top. The low teacher's desk (`teacher_desk.tscn`) is no longer placed in the classroom; the wrapper stays in the project |
| Timetable: coffee ring, teacher's name lined out in biro | `TimetableSheet/Face` |
| Schoolbag: dark blue canvas, two shoulder straps | Rounded, irregular sewn panels, two looped straps, a side pouch, and a flap over a real opening; mounted on the aisle-side desk hook (`Furniture/DeskB2/Schoolbag`) |

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
Glass remains the deliberate surface-alpha exception. The same jobs run
`tests/capture_classroom_clock.gd` (#173), which reads the time back off rendered frames of
the front-wall clock and fails unless it reads nine o'clock from every view; repainting the
dial (`assets/materials/classroom/clock_dial.tres`) or the hands' material keeps that check
honest (`docs/screenshots/README.md`, "The classroom clock").

The generator uses Godot 4.7.2's canonical 34-character UID encoding; check the sidecars
again after a real import to catch editor rewrites. Curated actual before/after frames,
pixel measurements, baseline-noise comparison and explicit platform limits are recorded
in `docs/screenshots/classroom_art_review/README.md`. Runtime evidence is not a substitute
for owner art review or target-GPU acceptance.

## Geometry and gameplay contract

The classroom shell is 14 × 10 m with a 3.2 m wall height. The north/blackboard wall is one
14 m wall. The west wall's solid shapes and visual shell both stop at the cut; the east wall
keeps its collision. The east wall has two 1.2 × 2.2 m door openings centred at z −3.55 (front,
`WallEast/FrontDoor`, grey) and z +3.55 (rear, `WallEast/RearDoor`, white), both the
owner's door model dressed in classroom materials, with plaster behind them; its shell and
paint are cut into the long pier, two end piers and two lintels, each sampling its own
slice of `wall_east.png`. `classroom_door` retains its original ID, blocked inspection and
corridor destination, and stands at the front door. The corridor uses the same grey and
white door variants at the matching thresholds. Only the front door changes location;
the white rear door is inspection-only on both sides. The two original curtain mount points
are kept as layout markers, but only `BackCurtain` is dressed. The projection screen
(`WallNorth/ProjectorScreen`) is rolled up when
the room loads; `Interactables/ProjectorScreenPull` rolls it down and up again, and
nothing about it is saved. The dark-blue schoolbag hangs from the protagonist's desk-side
hook (`Furniture/DeskB2/Schoolbag`), with its own hit area separate from the sliding chair.
Rebuild the sewn meshes and woven texture with
`python3 art/classroom/build_schoolbag.py` (`--check` verifies the shipped assets).
The player wakes in the chair (`PlayerStart`), and
Q starts a little way down the aisle and walks to `QOpeningTalk`, at the player's left,
before the first line (the opening's Q beat, #160). The stage and its step are actual colliders: the 0.12 m rise stays below the
player's 0.25 m step-up and the navmesh's 0.25 m climb. The standing lectern on the stage
is the only teacher's furniture: the low teacher's desk was taken out and its inspection
(`front_desk` / `classroom_teacher_desk`) now sits on the lectern (`Interactables/LecternInspect`). Q/N states, inspection IDs, `Sun`,
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
| Collision | `Body` box 0.84 × 0.96 × 0.54 m | it carves the navmesh and stops the player; the old lectern had no collider. Its top stops at the low edge of the sloped reading surface, so the box never stands above the set square lying there and the camera's line to it stays clear |

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
