# ADR 0004 — Art direction: environment route, camera projection, character shading

- **Status:** Proposed — **the owner has to sign this**. It is written as a draft with a
  recommendation for each of the three decisions, so the decision can be made by editing this
  file rather than by starting from a blank page.
- **Date:** 2026-11-12
- **Depends on:** ADR 0001 (engine and renderer)
- **Blocks:** #54 (the rendering pipeline is zero), #55's remaining half (animation into the
  game), the classroom vertical slice, and every later asset decision.

## Context

The audit that produced #54 measured the rendering side of the project and found it empty of
decisions rather than empty of effort:

- 0 `.gdshader` files. Every material is one of 20 flat colours.
- 386 `MeshInstance3D`, of which 347 are `BoxMesh`. Grey boxes are the level.
- The two character meshes have 0 tangents and almost no UV coverage (38/78 and 1/15), which
  means neither of them can carry a normal map, a detail texture or an atlas today.

That is a fine prototype, and it is not a look. Three decisions are load-bearing: everything
downstream — prop silhouettes, lighting rigs, UV work, the screenshot evidence set — inherits
them, and two of the three are cheap now and expensive later. The audit's ordering is the one
that matters here: **projection first**, because it decides what a silhouette even is.

The three decisions are recorded together because they are chosen together: a long lens and a
grey-box-plus-light environment route and a stylised character treatment are one coherent look,
and picking them from three separate menus is how projects end up with a photoreal corridor and
a cartoon protagonist.

## Decision 1 — Camera projection (decide first)

**Recommendation: perspective, 18° field of view, on the rig, with orthographic kept as a
one-line switch until the first vertical slice is judged.**

| | Orthographic | Perspective, 15–20° | Today |
| --- | --- | --- | --- |
| Reads as | a diorama / isometric board | a photograph from far away | a 3/4 view with visible distortion |
| Depth cues | only occlusion, scale and lighting | occlusion, scale, lighting and mild convergence | strong convergence; near walls distort |
| Props | need one good silhouette plane; the cheapest art route | need to read from a narrow cone; slightly more work | read differently depending on where you stand |
| Level layout | must be designed to read flat; walls hide less | tolerates the existing room proportions | walls constantly cover the player |
| Pointer aiming | uniform accuracy across the screen | accuracy falls towards the edges | worst at the edges |
| Change from today | large: re-frame every room | small: one number on the rig plus a further offset | — |

The recommendation is the long lens, for one reason that outranks taste: it is the version the
project can judge **this month**. `CameraRig` already owns the field of view and the offset, so
18° is one exported number, the capture job re-shoots the same frames, and the owner can put the
old and the new screenshot side by side and decide with their eyes instead of from a table. If
that comparison says the diorama reads better, orthographic is a `projection` switch on the same
rig plus a re-framing pass — and by then the rig exists, so it is a day, not a rewrite.

What the long lens costs, stated plainly: at 18° the camera has to sit much further from the
player than it does now (roughly three times the distance for the same coverage), so the level's
near walls are no longer the thing that ruins the view — the far wall and the ceiling of the
room become the constraint instead. Rooms will need checking against the framing, and the
occluder fader becomes less important, not more.

## Decision 2 — Environment route

**Recommendation: route B (grey box + a real light rig + a material pass) with route C (one
classroom taken to finished quality) as the pilot, and nothing else.**

- **Route A — art pass per room, in order.** Every room gets props, textures and lighting now.
  Rejected: seven locations, one artist, and the risk of throwing all of it away when Decision 1
  or 3 changes.
- **Route B — grey box, then light and materials only.** Keep the boxes, give them a palette, a
  sun, a bounce, fog and a colour grade. Cheapest possible step that makes the game *look like
  something*, and it is reversible.
- **Route C — one room, finished.** Take the classroom end to end: props modelled, materials
  authored, lighting designed, and it becomes the reference every other room is measured
  against.

B first, then C on the classroom, because B is what makes C's judgement possible: choosing
materials under no lighting is guessing. The classroom is the right pilot — it is the room the
opening fifteen minutes happen in, it already has the most authored props (desks, chairs, the
bag, the blackboard), and it is the one the screenshot evidence already covers.

## Decision 3 — Character shading

**Recommendation: stylised, three-tone ramp, no normal maps, authored palette; re-UV only what
the camera actually sees.**

The meshes have 0 tangents and no usable UVs, so anything that needs a normal map or a detail
texture is off the table without a modelling pass. That constraint points at the option that is
also the right look for a school story told at a distance: a ramp-shaded, flat-coloured
character whose readability comes from silhouette, palette and a rim light, not from surface
detail.

Two consequences worth writing down now:

- A `ShaderMaterial` with a 3-tone ramp is the first `.gdshader` in the project. That is
  Decision 3's real deliverable, and it is also what makes the grey boxes and the characters
  look like they belong to the same game.
- Faces are simplified on purpose (see `ART_BIBLE.md`): at the framing Decision 1 chooses, a
  face is a few pixels. Expression belongs to portraits (#61), not to the mesh.

## Consequences

- `CameraRig` is where Decision 1 lands. It exists now; its `fov`, `offset` and `projection` are
  the three numbers this ADR is about, and nothing else in the project may write them.
- The occluder fader stays, but Decision 1 changes how often it fires. It was fixed in the same
  change as the rig because a fade that never clears is worse in a long lens than in a steep one.
- The screenshot evidence set changes when Decision 1 changes. That is expected and it is the
  point: the capture job is how the decision gets looked at.
- Nothing in this ADR authorises buying, downloading or generating a texture library. Palette,
  ramp and lighting first.

## Revisit when

- The classroom vertical slice is judged and Decision 1 no longer reads well in motion.
- The art route starts costing more than one room per two weeks.
- A character needs facial close-ups outside portraits, which would retire Decision 3's premise.
