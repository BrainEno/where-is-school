# The dazed look after a hurt landing (`ConcussionView`)

> **状态：** 实验 · 只做美术，待所有者实机验收
> **最后核对：** 2026-11-21
> **负责人：** 实现 PR 作者

The owner's brief (round 7): after the prologue's fall from the classroom, if the
protagonist is hurt (摔坏了), the view gets a dazed filter. It must not be dizzying or
nauseating - it is an art style, not a symptom - and it may be postmodernist, freely.
Follow-up decision: strongest at the landing, then fading over about ten minutes of play.

Round 8 (the owner kept the look and asked for these changes):

- the Memphis marks (the squiggle along the bottom, the dot field, the ring) are gone;
- it leaves faster and the leaving is felt: about **four minutes**, quick at first (about
  half gone in the first minute), then slow;
- the pasted card is a **shard of broken mirror**, as if it had fallen with him;
- a **second fall** (jumping off the container roof, `RoofWayDown`) makes it heavier, and
  water from the **yard tap** clears it, a mouthful or a wash.

## What it looks like

The world as a **paste-up of itself** - a photomontage in the line of Höch and Rauschenberg,
with Memphis marks - drawn by `assets/shaders/injury/concussion_collage.gdshader`:

1. **Cuts.** Four straight, slightly torn cuts slice the frame into sheets. Each sheet is the
   same picture pasted a few pixels off its neighbours and printed in its own manner: as it
   is, as a pink/teal duotone, as halftone newsprint on cream, or as a two-plate riso print.
   The cuts have a paper edge and a drop shadow.
2. **A shard of mirror.** Near one side, a tilted pane with a thin bevelled rim holds an
   enlarged copy of the middle of the frame - the protagonist quoting himself - behind glass
   cracked from one point: nine radial cracks, broken rings, splinters each a little off,
   one splinter missing.
3. **The middle stays legible.** Every treatment is weaker towards the centre of the frame,
   so the protagonist, the path and the outline cue read as before. The cut lines, their
   shadows and the sheet offsets themselves fade out before the middle (`clear_middle`), so
   no seam or doubled edge ever crosses the protagonist.

As the look fades its pieces leave in order: the mirror shard, then the printing manners, and
last a faint misregistration of the sheets. Above 1 (`heavy`, after a second fall) the same
paste-up is pressed harder: wider offsets, stronger printing, more of the frame cut.

## Why it does not make anyone ill

- **Nothing moves.** The shader has no `TIME`: no wobble, pulse, drift, swirl or temporal
  grain (`tests/concussion_view_test.gd` refuses `TIME`). The camera is not touched.
- **Changes are never seen.** Strength falls over four minutes, far below what reads as
  motion. The only quick change is the tap's water, which the protagonist chose, eased over
  1.4 s. The paste-up is reshuffled once per room (`seed`), on entry, behind the black of
  the room change.

## When it is on

| Moment | What happens |
|---|---|
| Hurt landing, roof contact (`ContainerLanding.present`, hurt branch) | `ConcussionView.begin()` writes `concussion_seconds_left = 240`; the look arrives in 0.35 s, at full strength (1). |
| Braced drop (the passed balance check) | Nothing. |
| Jump off the container roof (`RoofWayDown.jump`, either landing) | `begin(from, true)` writes 300 (or keeps more): the 60 s above 240 are drawn heavier, 1 → 1.25. A braced lander who jumps starts the look here. |
| Play | The view counts down with the game clock and writes the whole seconds back to the flag. Strength falls as `exp(-2.4 × elapsed share)`, rescaled to end at 0: 0.50 three minutes before the end, 0.23 at two, 0.08 at one. |
| Yard tap, a mouthful (`pg_tap_use`, `drink`) | `clear()`: writes 0 (round 12: drinking makes the look go, as the wash does). Eased over 1.4 s. |
| Yard tap, a wash (`wash`) | `clear()`: the flag is 0 at once; the picture eases out over 1.4 s. |
| Pause menu, settings | The tree is paused; the look does not heal. |
| Save / Continue | The flag is saved like any other; Continue resumes the same look (without a second arrival). |
| 240 s of play later | The flag is 0; nothing is drawn or processed. |
| New game | The flags are cleared, and the look with them. |

## Where it sits

`scenes/main/main.tscn` → `ConcussionView` (CanvasLayer, group `world_filter`, layer **-2**)
with a full-screen `Sheet`. It is under the outline overlay (0) and the UI (1+), so cues and
dialogue are crisp on top, and under the yard's impact misprint (`RoofEncounter/WorldPrint`,
layer -1), which keeps its look from #196/#200 and prints the collage like it prints the rest
of the yard. The fade to black of a room change draws over it.

Renderer safety: a canvas item reading `hint_screen_texture`, which Forward+, Mobile and
Compatibility all provide; no depth read, no extra viewport, a constant-bound loop of four.

## Cost

One full-screen pass with three screen reads (four inside the quotation) while the look is
on; hidden and not processing when it is off. One flag write per second while it counts.

## Evidence

- `tests/concussion_view_test.gd` (CI): off by default; a world filter under the outline
  that ignores the mouse; the curve (fast first, then slow) and its inverse; a
  screen-reading canvas shader with no `TIME`; begin → arrival → countdown; the heavier
  second fall; a mouthful and a wash; paused does not heal; save → clear → load; the end; a
  new paste-up per room.
- `tests/classroom_anomaly_test.gd`: the real hurt landing starts the look; the braced drop
  does not.
- `tests/roof_way_down_test.gd`: the jump makes the look heavier and it keeps fading; the
  yard tap's water, drunk or washed, clears it.
- `.github/workflows/concussion-view-capture.yml`: the same test with `-- --capture` on
  Compatibility, Forward+ and Mobile: the yard and the alley, clear and at 300 (heavy) /
  240 / 180 / 60 s.
  A shader compile error fails the job.

## Open for the owner

- Duration (240 s), curve (`FADE_RATE` 2.4) and the heavier look (300 s, 1.25) are
  proposals.
- Whether the look should also touch the sound (it does not).
