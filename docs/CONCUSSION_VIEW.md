# The dazed look after a hurt landing (`ConcussionView`)

> **状态：** 实验 · 只做美术，待所有者实机验收
> **最后核对：** 2026-11-21
> **负责人：** 实现 PR 作者

The owner's brief (round 7): after the prologue's fall from the classroom, if the
protagonist is hurt (摔坏了), the view gets a dazed filter. It must not be dizzying or
nauseating - it is an art style, not a symptom - and it may be postmodernist, freely.
Follow-up decision: strongest at the landing, then fading over about ten minutes of play.

## What it looks like

The world as a **paste-up of itself** - a photomontage in the line of Höch and Rauschenberg,
with Memphis marks - drawn by `assets/shaders/injury/concussion_collage.gdshader`:

1. **Cuts.** Four straight, slightly torn cuts slice the frame into sheets. Each sheet is the
   same picture pasted a few pixels off its neighbours and printed in its own manner: as it
   is, as a pink/teal duotone, as halftone newsprint on cream, or as a two-plate riso print.
   The cuts have a paper edge and a drop shadow.
2. **A pasted quotation.** Near one side, a tilted, white-bordered cut-out holds an enlarged
   copy of the middle of the frame - the protagonist quoting himself - in newsprint.
3. **Memphis marks** in the margins: a squiggle, a dot field, a ring.
4. **The middle stays legible.** Every treatment is weaker towards the centre of the frame,
   so the protagonist, the path and the outline cue read as before. The cut lines, their
   shadows and the sheet offsets themselves fade out before the middle (`clear_middle`), so
   no seam or doubled edge ever crosses the protagonist.

As the look fades its pieces leave in order: the quotation (below ~0.32), the marks (~0.18),
the printing manners (~0.12), and last a faint misregistration of the sheets.

## Why it does not make anyone ill

- **Nothing moves.** The shader has no `TIME`: no wobble, pulse, drift, swirl or temporal
  grain (`tests/concussion_view_test.gd` refuses `TIME`). The camera is not touched.
- **Changes are never seen.** Strength falls over ten minutes, far below what reads as
  motion. The paste-up is reshuffled once per room (`seed`), on entry, behind the black of
  the room change.

## When it is on

| Moment | What happens |
|---|---|
| Hurt landing, roof contact (`ContainerLanding.present`, hurt branch) | `ConcussionView.begin()` writes `concussion_seconds_left = 600`; the look arrives in 0.35 s, at full strength. |
| Braced drop (the passed balance check) | Nothing. |
| Play | The view counts down with the game clock and writes the whole seconds back to the flag. Strength is `(left / 600) ^ 0.6`: about 0.66 at five minutes, 0.25 a minute before the end. |
| Pause menu, settings | The tree is paused; the look does not heal. |
| Save / Continue | The flag is saved like any other; Continue resumes the same look (without a second arrival). |
| 600 s of play later | The flag is 0; nothing is drawn or processed. |
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
  that ignores the mouse; the curve; a screen-reading canvas shader with no `TIME`; begin →
  arrival → countdown; paused does not heal; save → clear → load; the end; a new paste-up per
  room.
- `tests/classroom_anomaly_test.gd`: the real hurt landing starts the look; the braced drop
  does not.
- `.github/workflows/concussion-view-capture.yml`: the same test with `-- --capture` on
  Compatibility, Forward+ and Mobile: the yard and the alley, clear and at 600 / 300 / 60 s.
  A shader compile error fails the job.

## Open for the owner

- Duration (600 s) and curve (`FADE_CURVE` 0.6) are proposals.
- Whether the look should also touch the sound (it does not).
