# Postmodern offices and the Kafka archive (experimental, round 2)

> **Status:** experimental (2026-11-20). Owner art review pending.
> **Owner:** implementation PR author.
> **Source:** `tools/postmodern_office.py`, `tools/trial_archive.py`, `tools/dressing_geometry.py`, called from `tools/build_school_annexes.py` and `tools/build_school_rooms.py`.

The second round of the environment-art experiment. The first round is [EXAM_DREAM_ART.md](EXAM_DREAM_ART.md).
The owner asked for two things:

- the offices on 03, the floor above the classroom, get swivel chairs, desks and similar
  furniture in a **postmodern** style;
- the archive (01) should feel like the bureaucracy in Kafka's *The Trial*.

Like round 1, this pass is additive set dressing. It moves no exit, spawn, inspection or
outline target, and it adds no script, actor, sound or texture. Every piece is a primitive
box, cylinder or small generated mesh in a flat pigment.

## The 03 offices: postmodern

The pieces echo Memphis Group furniture and Michael Graves / Philip Johnson buildings. They
use hard pastel and primary fields (`POMO` in `postmodern_office.py`) over each room's
existing palette.

| Piece | How it is drawn |
|---|---|
| Swivel chair | A five-spoke star base on casters, a shrouded gas lift and a lofted cushion. The back is one of four shapes: a disc with a dot, a striped triangle, an arch with a keystone, or the principal's `throne`, which is taller than its occupant, with pilasters and a broken pediment around an oculus. |
| Memphis desk | A terrazzo top scattered with confetti chips. Every leg is a different solid: a cobalt drum, a pink drawer ziggurat and one leaning black rod. A lemon lobe overhangs one end. The `classical` variant stands on four fluted columns with gilded capitals and has a triglyph frieze on the visitor's side. |
| Carlton shelf | A totem room divider with arms splayed around a red spine on a Bacterio-patterned base. It holds a few books and a vase. |
| Pediment cabinet | A pink cabinet dressed as a skyscraper, with mint pilasters, a lemon cornice and a split gable around an oculus. |
| Column lamp, kettle, clock, rug | A fluted Doric floor lamp under a cone shade, a cone kettle with a red bird, a clock of primary shapes whose two hands point the same way, and a rug of black squiggles and dots. |

Where each piece goes:

- **Vacant workroom (`vacant_office`).** The old `EmptyDesk` and both chairs keep their
  footprints and colliders but are rebuilt as a Memphis desk and two swivel chairs. On the
  west side, an open-plan corner looks as if everybody left mid-afternoon. A hot desk stands
  on a squiggle rug with a kettle and files on it. One chair waits at the desk and another
  lies toppled on its side. Along the wall stand a Carlton shelf, a pediment cabinet, a lit
  column lamp, a clock and a frieze of diamonds.
- **Principal's office (`principal_office`).** `HeadDesk` becomes the classical desk, with
  a kettle beside the blotter. `ChairOfOffice` becomes the throne swivel chair. Two
  freestanding pink columns frame it against the false-window wall. The four waiting seats
  become pastel swivel chairs, still turned away. Also added: a Carlton shelf, two column
  lamps, a split-gable crown on the side case and a clock. The painted floor fields are left
  uncovered.
- **Staff office (`staff_office`).** The desk, both pedestals and the chair keep their exact
  collision boxes, which the office tests were measured against. On top of those boxes:
  - the desk gets a terrazzo top;
  - one pedestal becomes a fluted cobalt drum and the other a drawer ziggurat;
  - the chair becomes a gas-lift chair.
  
  A squiggle rug lies under the desk, below the painted sun patch. A column lamp, a bird
  kettle on the mail cabinet and a clock are added. The round-1 waiting room's four turned
  chairs are re-upholstered in pink, lemon, mint and cobalt with a square finial (the
  `look` argument of `dream_figures.swivel_chair`). They keep turning away on their lifts.
  Nothing added here has a collider.

## The archive: *The Trial*

`trial_archive.py` turns the archive into the court offices of the novel. It is an
attic-like registry where the files outgrow the room.

| Element | From the novel | How it is drawn |
|---|---|---|
| Dossier mountain | Law books and files everywhere in the court offices. | Bundles tied with string are stacked on the four map cases until they pass the top of the wall, leaning as they rise, with sheets sticking out. A library ladder leans into them. Lower towers stand on the floor. All of it is merged into one mesh per pigment. |
| Petitioners' bench | The accused waiting in the court corridor, getting up and bowing when K. passes. | A long bench on the west wall. Four seated petitioners hold petitions, two of them nodding. Their hats hang on hooks above. Every seat has the same number card, `17`. A latecomer stands bowed at the end. A notice reads `候审者请保持安静 / PETITIONERS WAIT HERE · NO TALKING`. A bare bulb hangs on a long flex. |
| The Law's gate | *Before the Law*: a doorkeeper, more gates behind him, and a radiance from the door; the gate "was made only for you". | Four frames, each nested inside the last, step up into the west wall and darken toward a small door. Light shows at its seams and keyhole and spills over the steps (unlit `law_glow`). A pediment carries `法 LAW` and rises above the wall. A brass plaque reads `此门只为你而设 / THIS GATE WAS MADE ONLY FOR YOU`. The doorkeeper stands beside it in a fur coat, fur hat and long thin beard, with fleas in his collar. The man from the country dozes on a stool facing the gate. |
| High desk | The examining magistrate on his podium. | A panelled desk on a plinth, its writing slope at 2.7 m. The magistrate sits on a tall stool, stamping mechanically (`stamp` motion). His head is above the wall. A register hangs over the front with a page marked `案 K.`. A brass plate reads `预审法官 / EXAMINING MAGISTRATE`. A clerk's ladder leans on the side. |
| Laundry | Washing hung up in the attic courtroom. | A sagging line runs from the west wall to the high desk. Shirts, a red dress and a sheet hang on it alongside pinned files. |
| Paper drifts, queue post | Petitions that are never answered. | Sheets and crumpled balls drift against the bench, the gate steps and the high desk. A ticket post by the door only ever issues `17`. A stamp carousel and a spike of slips sit on the index desk, clear of the ledger. |

The few colliders added stand against the west and north walls: the bench, the
doorkeeper, the country man's stool and the high desk. They are away from the door, the
index desk and the reading stance.

## Checks

- `python3 tools/build_school_annexes.py --check`, `python3 tools/build_school_rooms.py --check`
  and `python3 tools/build_teaching_block.py --check` own the generated bytes.
- `python3 tests/office_archive_dressing_test.py` (standard library, CI `godot-ci.yml`)
  checks three things:
  - the merged meshes face outward;
  - no collider in the three annex rooms comes within 0.55 m (the navigation agent's radius
    plus a margin) of the walk from the entry spawn to the reading stance;
  - the staff office's dressing adds no collider and keeps the four original collision
    boxes.
- `tests/school_expansion_test.gd`, `tests/school_rooms_test.gd`,
  `tests/location_art_test.gd` and `tests/dream_annex_test.gd` cover the same stances,
  inspections, routes and waiting-room pieces in the engine.
- The `Location art capture` workflow photographs `archive`, `vacant_office`,
  `principal_office` and `staff_office` for review.
