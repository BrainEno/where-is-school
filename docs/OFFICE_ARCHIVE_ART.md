# Postmodern offices and the registry archive (experimental, round 2)

> **Status:** experimental (2026-11-20; archive revised 2026-11-21). Owner art review pending.
> **Owner:** implementation PR author.
> **Source:** `tools/postmodern_office.py`, `tools/registry_archive.py`, `tools/dressing_geometry.py`, called from `tools/build_school_annexes.py` and `tools/build_school_rooms.py`.

The second round of the environment-art experiment. The first round is [EXAM_DREAM_ART.md](EXAM_DREAM_ART.md).
The owner asked for two things:

- the offices on 03, the floor above the classroom, get swivel chairs, desks and similar
  furniture in a **postmodern** style;
- the archive (01) should feel like the bureaucracy in Kafka's *The Trial*;
- revision (2026-11-21): the archive is not about a court. It holds student files,
  school rules and inspection dossiers. Avoid explicit words and let the pieces work as
  metaphor, with postmodern expressiveness.

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

## The archive: files, rules, inspections

`registry_archive.py` dresses the archive as a registry that has outgrown the room. The
first version borrowed the court offices of Kafka's *The Trial* literally (a magistrate,
the doorkeeper, `法`, `案 K.`). The revision keeps the bureaucratic weight but removes
the court. Nothing in the room is named: the only text left is clause numbers, a
section sign, the number `17` and the ticket post.

| Element | Metaphor | How it is drawn |
|---|---|---|
| File mountain | Student files that outlive the students. | Bundles tied with string are stacked on the four map cases until they pass the top of the wall, leaning as they rise. Some carry a blank passport photo; a few carry a pastel tab (pink, mint, lemon, cobalt). A library ladder leans into them. Lower towers stand on the floor. By the inspection desk, the stacks are red-banded inspection dossiers. |
| Continuous form | The permanent record follows you out. | A green-barred fan-fold printout with grey tractor-feed margins unrolls from a roll at the foot of the files. It snakes across the floor, over the floor rules, and ends at the door. It is floor-level and has no collider. |
| Rule gate | The rules as a gate you can only wait in front of. | Four frames, each nested inside the last, step up into the west wall and darken toward a small door. Each lintel carries a deeper clause number: `1`, `1.1`, `1.1.1`, `1.1.1.1`. A pediment carries `§`. Light shows at the seams and keyhole and spills over the steps (unlit `seam_glow`). Beside the gate, a blank student card sits in a brass frame: a photo with no face and lines with no name. |
| Uniform stand | Authority with nobody inside. | A school uniform on a coat stand guards the gate: a jacket, a red duty armband, a whistle on a lanyard and trousers, with an empty collar. It keeps the first version's guard footprint and collider. |
| Waiting student, bench | Waiting as the default state. | One student sits nodding on a stool before the gate, satchel at the feet. On the west wall, four students wait on a long bench, holding files or with papers beside them; two nod. Satchels hang on hooks above. Every seat has the same number card, `17`, and a latecomer stands bowed at the end. Above them, a notice board is layered with pinned forms. Their lines are illegible; the forms are ticked and crossed in red or blue. A bare bulb hangs on a long flex. |
| Inspection desk | Being checked from above, by no one. | A panelled desk on a plinth, its writing slope at 2.7 m. The tall stool behind it is empty. An oversized stamp keeps stamping on a red pad by itself (`stamp` motion). A checklist hangs over the front: nine boxes, all ticked in red except one. The nameplate is blank. A magnifying lens on a long jointed arm leans out over the room toward the door. A clerk's ladder leans on the side. |
| Drying line | School life pegged out to dry. | A sagging line runs from the west wall to the inspection desk. Pegged to it are uniform shirts, a uniform jacket with an armband, report cards (a grade grid with nothing written, one red mark), files with photos and a timetable grid with a few pastel periods. |
| Paper drifts, queue post | Forms that are never answered. | Sheets and crumpled balls drift against the bench, the gate steps and the desk. A ticket post by the door only ever issues `17`. A stamp carousel and a spike of slips sit on the index desk, clear of the ledger. |

The few colliders stand where the first version's stood, against the west and north
walls: the bench, the uniform stand, the student's stool and the inspection desk. They
are away from the door, the index desk and the reading stance.

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
