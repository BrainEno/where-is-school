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

The classroom's look comes from the room itself: a teal wainscot, a muted rose teacher's
zone on the floor, muted rose board/door frames, violet-grey shadow planes, and ochre
light coming in where it should not. The space above the board stays empty; the former
red pseudo-writing banner and its generation code have been deleted. There is no screen-wide "oil paint" filter. Walls and functional props
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
| Floor | `#898486` | Plank strokes; the aisles are worn paler |
| Teacher's zone | `#785148` | Ragged painted plane under the front desk and board |
| Board | `#243D3F` + chalk `#D6DCCE` | The wiped-not-quite front board, the old chalk newspaper on the back wall |
| Oxblood lacquer | `#6E3C36` | Board frame, teacher's desk panels, door frame: the *authority* objects |
| Apricot | `#E0A569` / pale `#EFCD97` | The impossible late light: the window view, its spill on the wall, its shapes on the floor |
| Honey wood | `#A98458` | Teacher's desk top, chalk tray; the student desk pigment anchors |
| Worn wood | `#998775` | Student chairs: deliberately quieter |
| Mustard canvas | `#BE963E` | The schoolbag: the first thing the player is sent to |
| Cobalt | `#40568C` | The register's cover, readable but matte rather than glossy |

### Hierarchy rules

1. **Broad planes stay quiet.** Walls and floor have colourfulness ≤ 0.20
   (max − min of the mean sRGB colour).
2. **Every object the player is meant to look at separates from its backdrop** by at
   least 0.15, in value or in colourfulness: board against wall, schoolbag against floor,
   window against wall, set square and register against the desk top, door frame against
   the back wall.
3. **Repeated furniture does not compete.** The repeated chairs stay at least 0.15 less
   colourful than the schoolbag.
4. **Ink is for edges, not texture.** Lines go on contours, seams and the few graffiti
   marks. They do not cover walkable floor or interactables.

`tests/classroom_visual_slice_test.gd` measures all four rules on the shipped textures.

## Graphic marks, each with a reason

- **Front wall:** a cut-paper shadow behind the board, chalk dust wiped onto the wall, and
  a pencil height chart someone started by the door and gave up on.
- **Window wall:** apricot spill around both windows, a painted reveal, and chalk tallies
  under the back window.
- **East wall:** pale ghosts of notices that have been taken down, with their tape, and a
  small chalk door that leads nowhere.
- **Back wall:** a sketchy second door frame drawn around the real one, and an old chalk
  newspaper in coloured chalk (a leaf, a fish skeleton, a flower; nothing legible).
- **Front board:** heading and date-column ghosts under the eraser arcs, which match the
  inspection text (*LAST TERM — REVISION*, a date three weeks old). They are kept
  illegible on purpose, so the board needs no localisation.
- **Above the board:** deliberate negative space; no replacement text or glyph decoration.

## Inspection texts → scene

| Text says | Scene has |
|---|---|
| Board wiped, then not quite; chalk tray with one broken stick and a clip | `Board/Face` texture, `ChalkBrokenEnd`, `Clip`, chalk dust on the tray |
| Two panes, one cracked and taped; wet concrete, low wall, bins; late-afternoon light | `WindowGlass0` (crack + tape), `window_view.png` |
| Set square, forearm length, pale varnish, split corner taped with browned tape, taped corner faces the room | `set_square.tscn` now lies flat (0.55 × 0.42 m; the prism's size axes were swapped), `TapeRepair` in browned tape, ink ticks |
| Own desk: scratched-out name, half-peeled sticker, groove along the front edge | `Furniture/DeskB2/DeskMarks` decal |
| Teacher's desk: register in plastic, stapler, mug of chalk, chair pushed in at an angle, tidier | `Register` + label, `Stapler`, `Mug` with three sticks, `Papers`, the new `Chair` |
| Timetable: coffee ring, teacher's name lined out in biro | `TimetableSheet/Face` |
| Schoolbag: canvas, one strap | Mustard canvas, one `Strap`, a side pocket |

## Material and reuse contract

The full synchronized classroom chapter in `docs/ART_BIBLE.md` /
`docs/ART_BIBLE.zh-CN.md` records material tiers, palette ranges, contour eligibility,
brush density and reuse in later locations. Walls are authored opaque, back-face culled
and depth-writing; only temporary camera obstruction relief may fade them. Forward+
uses instance transparency alone, while Compatibility/Mobile need material-alpha copies.
Do not multiply both. `tests/classroom_wall_render_test.gd` compares actual pixels against
a single-alpha control; `tests/capture_classroom_art.gd` records the actual classroom.
Glass remains the deliberate surface-alpha exception.

The generator uses Godot 4.7.2's canonical 34-character UID encoding; check the sidecars
again after a real import to catch editor rewrites. Curated actual before/after frames,
pixel measurements, baseline-noise comparison and explicit platform limits are recorded
in `docs/screenshots/classroom_art_review/README.md`. Runtime evidence is not a substitute
for owner art review or target-GPU acceptance.

## What did not change

Room size, walls, door gap, desk grid, spawn points, every interactable and its
position, and the `Sun` / `WorldEnvironment` nodes stay in place. Their local light colors and
energies are tuned for warm/cool painted planes rather than overexposed PBR highlights. No new
colliders were added, so the runtime navigation bake sees exactly the same solids.
