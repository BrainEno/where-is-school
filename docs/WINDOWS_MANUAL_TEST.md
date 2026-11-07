# Windows manual playtest checklist — playground slice

**Not a test result.** Run on Windows with the official Godot 4.7.2 Stable
standard build (not .NET), on a clean checkout/import. Record the commit, OS,
GPU/driver, resolution, scaling, language, control device, notes, and any
screenshots separately. Headless tests and Xvfb simulated input are not a
substitute for this checklist.

1. Open `project.godot`, import, run the main scene. Check WASD/arrows, E,
   Space/Enter, numbered choices, Tab backlog, L language toggle; mouse if used.
   Note any focus/input conflicts or unreadable Chinese glyphs at 1280×720 and
   1600×900.
2. Play the existing opening normally: wake, Q, schoolbag, expectation, bell,
   substitute N and dismissal; go through the walkway, street, stair, residential
   courtyard and observe the green animal. Check no earlier state or lines are
   lost. Do not infer a species or cause from the placeholder model.
3. Without teleporting, walk through the actual opening in the north residential
   block into the alley, across the estate gateway space and into the playground.
   Check collision, floor seams, prompts, camera occlusion, doorway orientation,
   framing, and whether the route is legible without quest arrows.
4. Explore the open yard freely. Visit the lane markings, practice ring, bench,
   and notice in different orders; cross the centre; revisit them; return to the
   estate, residential area and street, then back to the yard. Confirm no hidden
   quest lock, softlock, repeated arrival beat or unwanted end card.
5. At the bench and notice, inspect active ability choices. Before selection,
   check the named rating and difficulty; afterwards check the die, total,
   outcome and a distinct useful response on success/setback. Switch language
   while a result is visible: no reroll, duplicated note or lost line. Revisit to
   check once-only choices and the ability to leave without selecting one.
6. Observe passive reactions after reading the markings/ring. Check they are
   sparse, contextual, subjective and never display a die; repeat visits or
   closely spaced interactions should not produce a barrage. Record whether the
   voices feel biased/contradictory rather than an authoritative narrator.
7. Check the optional **Finish this build** prompt is clear before choosing it,
   and the end card appears only then. Try the camera, movement and interaction
   near every edge and prop; note comfort, pacing, contrast, text wrapping and
   performance on representative lower-end Windows hardware.

For each item record **pass / fail / not tested**, steps, expected vs actual,
logs and screenshot filenames. This document does not assert any item passed.
