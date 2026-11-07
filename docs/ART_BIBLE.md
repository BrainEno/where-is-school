# Art Bible

## Visual thesis

**Ordinary materials, slightly impossible spaces.**

The world should initially look like a place someone has actually used: scuffed concrete, institutional paint, metal doors, old desks, mop water, cables, laundry, tires, noticeboards, and cheap fluorescent fittings. Surrealism enters through scale, adjacency, missing architecture, repeated details, and impossible connections—not through fantasy ornament.

The direction may be described internally as *damp surrealism*. Treat that phrase as shorthand, not a rigid genre label.

## Visual principles

1. **Material specificity:** surfaces should show use, age, repair, moisture, dust, and neglect.
2. **Spatial restraint:** one wrong detail can be more effective than an entire room of impossible objects.
3. **Muted color, selective warmth:** most of the world is desaturated; the orange dusk is persistent but not comforting.
4. **Readable silhouettes:** walkable surfaces, doors, interactables, NPCs, and exits must remain legible.
5. **Painterly cohesion:** lighting, texture, props, and character portraits must feel like one authored world.
6. **No imitation:** do not reproduce the recognizable brushwork, compositions, UI, or character designs of a reference game.

## Palette guide

These are directional color anchors, not a strict per-pixel palette:

| Role | Color | Hex |
|---|---|---|
| Concrete gray | Weathered neutral | #777875 |
| Faded green | Institutional paint | #7B8177 |
| Rust red | Oxidized metal | #884B43 |
| Dirty blue | Old doors / containers | #526875 |
| Dusk orange | Distant warm light | #D18D59 |
| Paper | Aged paper / plaster | #C6BBA4 |
| Deep shadow | Neutral near-black | #2E3131 |

Do not force every scene to use every color. The palette should emerge from materials and light.

## Environment approach

- Use Blender to create blockouts and reusable 3D architectural modules.
- Start with simple collision and navigation geometry; visual detail must not obscure traversal.
- Use modular walls, floors, stair segments, doors, railings, classroom furniture, signs, cables, and containers where repetition is useful.
- Vary familiar modules through lighting, scale, occlusion, orientation, wear, and unusual adjacency rather than constantly introducing new asset families.
- Use dampness, puddles, water traces, and reflections sparingly enough that they retain meaning.
- Keep the horizon and distant spaces ambiguous, while local collision and interaction remain reliable.

## Character approach

- Readable body silhouettes and posture matter more than facial realism.
- Use economical 3D body animation for exploration.
- Dialogue portraits may be 2D illustrated assets with a small number of meaningful expression variants.
- Avoid expensive full facial rigs until the writing and conversation format prove they are necessary.
- NPCs should look like people who belong to a lived-in social world, not a cast of fantasy archetypes.

## Production workflow

1. Graybox scale and camera.
2. Establish navigation and interaction readability.
3. Test one material/lighting treatment in-engine.
4. Build a small modular prop set.
5. Create final or near-final art only after the location's player path is stable.
6. Keep source files and runtime exports organized; record provenance.

## Temporary and generated assets

- Graybox primitives are always acceptable.
- Generated images may be used privately for ideation, but they are not automatically approved production assets.
- Do not commit generated or downloaded assets without provenance and rights review.
- Do not use an image merely because it is visually impressive; it must fit the established material language and game readability.

## UI and typography

- UI should feel restrained, legible, and deliberate—not a direct imitation of another game's interface.
- Long Chinese dialogue requires comfortable line length, line spacing, font size controls, backlog, and clear speaker/choice hierarchy.
- Do not put decorative textures behind text if they compromise contrast.
- Support text speed and skip controls before content volume grows.

### The dialogue surface (implemented)

The dialogue reads as text laid on the world, not as a window over it. The band sits in
the lower left, fades into the scene along its top edge, and never takes more than about
two thirds of the width or height — the room remains the picture.

The hierarchy is fixed, and it is the whole design:

1. **the sentence** — the largest text on screen, at a measured line length and with
   generous line spacing, in the project's one CJK-capable font;
2. **the speaker's name** — an anchor, tracked slightly wider than body text, tinted by
   that character's accent;
3. **the role** — present, small, muted: the identity behind the name, not a label to
   read first;
4. **the narrative source** — a hairline and a 12 px label, in a muted version of the
   source colour. Seen, heard, remembered and imagined must be distinguishable at a
   glance and never announce themselves with badges, pills or saturated blocks;
5. **the options** — text on their own lines under a rule, numbered, flat until the
   pointer touches them, then a 2 px margin mark and a lifted line. No filled buttons,
   no iconography, no glow.

Portraits are planned and not drawn: the layout reserves the left margin and the space
above the band for one, and shows nothing there until real art exists. A placeholder
silhouette is not an acceptable substitute.

Name labels over grey-box people are a **development instrument**, not a game UI
element: small, tracked, paper-coloured, outlined, always facing the camera, hidden in
release builds.
