# Art Bible

> **English source of truth.** The matching Chinese reading copy is [ART_BIBLE.zh-CN.md](ART_BIBLE.zh-CN.md). Keep both files synchronized when this document changes.

## Visual thesis

**An expressive world with the emptiness of a stage, inhabited by psychologically vivid people.**

where-is-school is a literary 2.5D narrative exploration game. Its visual language sits between expressionist painting, graphic illustration, hand-drawn marks, theatrical scenography, and a deliberately authored 3D game space.

The direction has four connected parts:

- **People — expressionist:** characters carry emotional and psychological presence through posture, proportion, facial structure, color, and gesture.
- **Environment — graphic and hand-made:** spaces may use bold color planes, loose outlines, drawn marks, graffiti-like gestures, rough textures, and intentionally simplified geometry.
- **Outdoor space — absurd theatrical emptiness:** especially outside, spaces may feel like spare stage sets: broad areas of sky and ground, isolated objects, distant simplified structures, and an atmosphere of waiting or disorientation.
- **Dialogue UI — integrated composition:** portrait, text, and choices belong to one designed narrative image rather than separate standardized boxes.

The world may be incomplete, strange, or visually rough. The people within it should feel specific and alive.

## Artistic references

Use these as broad references for artistic principles and atmosphere:

- **Egon Schiele:** elongated bodies, distinctive proportions, exposed and uneasy posture, expressive line.
- **Edvard Munch:** emotional color, psychological distortion, and the relationship between a person and the space around them.
- **Expressionist painting and drawing:** subjective form, visible gesture, imperfect contours, and color used to express an inner state.
- **Graffiti and non-academic drawing:** direct marks, rough edges, informal energy, and personal visual character.
- **Waiting for Godot:** spare theatrical staging, an exposed outdoor setting, isolated objects, and absurdity produced through absence, waiting, and uncertainty.
- **Disco Elysium:** painterly character portraits and the contrast between a navigable game space and highly authored character imagery.

References are points of departure for mood, composition, and technique, not fixed templates.

## Core principles

1. **Expression over anatomical perfection.** Controlled distortion is welcome when it communicates character or emotion.
2. **Graphic clarity over physical simulation.** Build the image from shape, line, color, and composition before adding material complexity.
3. **Negative space is narrative.** Emptiness can express waiting, isolation, uncertainty, or being lost.
4. **Selectivity over clutter.** Important interactive objects should be legible and visually distinct; secondary scenery should remain quiet.
5. **Roughness with intention.** Irregular edges, visible brushwork, uneven color, and imperfect perspective are valid choices when they serve the image.
6. **Readable play space.** Artistic distortion must not obscure walkable surfaces, characters, interaction targets, exits, or immediate navigation.

## Environment direction

### Graphic environment language

Environments should feel drawn, painted, or assembled as images rather than physically reconstructed in exhaustive detail.

Useful devices include:

- broad, readable color planes;
- hand-drawn or irregular silhouettes;
- loose outlines and visible brush marks;
- selective graffiti-like marks;
- simplified props and architecture;
- rough transitions between color areas;
- deliberate perspective shifts and unusual spatial adjacency.

Graphic does not mean visually crowded. Do not cover every surface with marks or give every prop equal detail. The scene needs a clear visual hierarchy.

### Outdoor spaces: theatrical emptiness

Outdoor spaces are a major opportunity to establish the game's identity. The schoolyard, open grounds, paths, roadside gaps, and spaces between residential buildings may be composed like spare theatrical sets.

Think of an exposed stage prepared for a small number of people and objects:

- Let sky and ground occupy large portions of the composition.
- Use a simple horizon or a deliberately artificial boundary between ground and distance.
- Allow a tree, bench, lamp post, sign, fence segment, or distant building to stand alone.
- Keep distant architecture sparse, flattened, or backdrop-like.
- Allow unusual scale, spacing, and perspective when the image remains readable.
- Let a character appear small against an expansive empty area.
- Do not add scenery merely to fill the frame.

The result should carry a quiet absurdity: a place that seems ready for something to happen, yet continues to wait. The emptiness should feel intentional rather than unfinished.

This is a staging principle, not a requirement to turn the world into a literal theatre. Curtains, spotlights, audience seating, and conventional stage decorations are not default elements.

### Indoor spaces

Indoor spaces may contain more functional detail than outdoor scenes, but they should still be selective and graphic. A classroom can be identified by a small number of meaningful elements—desks, a blackboard, windows, a teacher's area, and a few story-relevant props—rather than a dense inventory of classroom clutter.

Spatial contradictions may appear in corridors, staircases, doors, and room connections. Keep the local space understandable even when its larger geography is impossible.

### Materials and surfaces

Favor simple materials, painted surfaces, broad color changes, hand-made textures, and selective roughness. Photographic PBR detail, pervasive dirt, rust, dampness, and heavy weathering are not required visual signatures.

A surface may be clean, plain, rough, or graphic. Choose its treatment according to the composition and narrative purpose.

## Character direction

### Character design

Characters should feel individually authored, psychologically legible, and human—not standardized game mannequins.

Useful choices include:

- elongated or subtly irregular proportions;
- asymmetrical facial structures;
- distinctive silhouettes and clothing shapes;
- awkward, tense, withdrawn, or otherwise character-specific posture;
- expressive hands, shoulders, head angles, and weight distribution;
- unusual but controlled color relationships.

Avoid both exaggerated cute-cartoon proportions and conventional academic realism. Distortion should reveal something about the person rather than function as decoration.

### In-game 3D characters

The 3D model and the dialogue portrait have different jobs.

The in-game model establishes a character in the navigable space. Prioritize:

1. recognizable overall silhouette;
2. individual body proportions;
3. character-specific posture and movement;
4. readable clothing shape and color identity;
5. enough facial structure for recognition at the gameplay camera distance;
6. stable, economical animation.

Facial detail can remain simplified. Do not spend disproportionate effort on geometry that the 2.5D camera cannot reveal.

### Dialogue portraits

Dialogue portraits are a high-priority, independent 2D art asset—not a screenshot, enlarged render, or automatic projection of the 3D model.

The portrait direction is explicitly expressionist. It may use:

- visible, assertive brushwork;
- distorted or asymmetrical facial proportions;
- non-naturalistic skin and shadow colors;
- uneven contours and rough edges;
- bold, emotionally motivated color contrasts;
- simplified or abstracted portrait backgrounds;
- individual crops and compositions for different characters.

The portrait must remain recognizable as the character while expressing a psychological state. It may be more distorted, detailed, or emotionally direct than the corresponding 3D model.

Different characters should not look like variations of one portrait template. Let posture, crop, mark-making, color, and degree of distortion respond to each person's identity.

Begin with a small set of meaningful states rather than many barely distinguishable variants: for example, neutral, speaking, irritated, uncomfortable, surprised, or withdrawn. The final set should be determined by actual dialogue needs.

Keep editable source files and exported runtime images separately organized.

## Color direction

Color should communicate mood and visual hierarchy rather than obeying physical material accuracy.

- Environments may use a controlled range of neutral, muted, warm, or unexpectedly vivid color planes.
- Outdoor compositions may use broad sky and ground colors, with distant forms kept simple.
- The persistent warm dusk can remain a useful motif where it serves the scene, but it is not a mandatory filter for every location.
- Character portraits may use stronger contrast, unusual skin tones, non-naturalistic shadows, and emotionally charged background colors.
- Interactive objects may receive selective color emphasis to help recognition.

Do not force every scene or character into one fixed palette. Build local palettes that remain coherent with the overall visual language.

## UI direction: integrated narrative composition

The UI should be minimal, deliberate, and comfortable to read. The dialogue interface is not a conventional portrait frame placed beside a separate text box.

**Portrait, dialogue text, speaker identity, and choices should form one integrated composition.**

Possible treatments include:

- portraits entering from or extending beyond a screen edge;
- irregular crops and silhouettes;
- portrait color fields that connect visually with the dialogue area;
- text and portrait areas that overlap in composition without obstructing reading;
- different portrait scale or placement according to character and scene;
- layouts that give long passages more space when needed.

Integrated does not mean cramped or chaotic. Maintain consistent layout rules and clear hierarchy while allowing controlled variation.

### Readability requirements

Long Chinese dialogue is a hard requirement. Preserve:

- comfortable text width and line length;
- adequate font size and line spacing;
- strong text/background contrast;
- clear distinction between dialogue and player choices;
- speaker identity that remains easy to locate;
- stable wrapping and layout at supported resolutions;
- backlog, text-speed, and skip behavior.

When the portrait competes with the text, revise the composition. Do not solve the conflict by making the text too small or difficult to read.

### UI restraint

Avoid unnecessary decorative frames, elaborate panels, ornamental badges, excessive icons, glossy buttons, and heavy gradients. Use typography, spacing, color fields, simple lines, and carefully controlled irregular edges to create quality.

Other interfaces—backlog, inventory, inspection, settings, checks, and interaction prompts—should follow the same restrained graphic language.

## Camera and composition

The game retains a controlled 2.5D camera over 3D environments.

- Keep navigation, interaction targets, and spatial relationships readable.
- Use asymmetry, broad negative space, simplified depth, and deliberate color grouping.
- In outdoor scenes, let the scale of the empty space contrast with the player's small figure.
- Use impossible connections, altered scale, repetition, and spatial discontinuity to create surrealism.
- Do not sacrifice playable clarity for visual distortion.

## Production workflow

### Environment

1. Graybox the playable route, collision, and camera first.
2. Identify the few important interactive and narrative objects.
3. Compose the scene using ground, sky, distance, and negative space before adding props.
4. Establish major shapes and color planes.
5. Add selected hand-drawn marks, graffiti-like gestures, and surface texture.
6. Reduce or quiet secondary objects.
7. Test from the actual gameplay camera and verify navigation readability.

### 3D characters

1. Define the character's narrative function and personality.
2. Design a distinctive silhouette, proportions, and posture.
3. Build an economical 3D model.
4. Establish clothing and color identity.
5. Add only the facial detail visible and useful at gameplay distance.
6. Test scale, animation, and readability in the real scene.

### 2D dialogue portraits

1. Define the character's approved visual facts and unresolved details.
2. Explore a small number of expressionist portrait directions.
3. Establish the face, crop, gesture, palette, and mark-making independently of the 3D model.
4. Create the primary portrait before producing a large expression set.
5. Test it in a dialogue composition with realistic Chinese text.
6. Retain the editable source and record asset provenance.

### UI

1. Establish the integrated portrait/text/choice composition.
2. Test with long Chinese dialogue rather than placeholder one-liners.
3. Check different portrait shapes and character identities.
4. Verify keyboard, mouse, backlog, choice, and language-switch behavior.
5. Test supported resolutions and safe areas.

## Technical and asset constraints

- Engine: Godot 4.7.2 Stable, standard build.
- 3D source files: Blender.
- Runtime 3D interchange: glTF 2.0 / GLB unless a documented need requires otherwise.
- Dialogue portraits: independent 2D assets with editable source files.
- Keep source files separate from optimized runtime exports.
- Record creator/tool, source, license, applicable terms, and human editing/approval in docs/ASSET_PROVENANCE.md.
- Generated or downloaded assets are not automatically approved for commercial use or repository inclusion.
- Test assets in the actual Godot scene, not only in the authoring application.
- Keep rendering and asset complexity within the project's performance budget.

## Visual acceptance checklist

**Environment**
- Does it have a clear graphic, hand-made visual language?
- Is the scene composed rather than cluttered?
- Are important interactive objects easy to identify?
- Does an outdoor scene use emptiness deliberately, with a stage-set sense of absurdity or waiting where appropriate?
- Can the player still understand the playable space?

**3D character**
- Is the silhouette distinctive?
- Do proportion and posture express the character?
- Is the model readable from the actual gameplay camera?

**Dialogue portrait**
- Is the portrait unmistakably an independent expressionist artwork?
- Does it convey a specific psychological presence?
- Is the character recognizable?
- Does it have its own composition and mark-making rather than looking like a model render?

**Dialogue UI**
- Do portrait, text, and choices read as one composition?
- Is long Chinese text comfortable to read?
- Does the layout remain minimal and consistent while allowing controlled variation?

## Final principle

**The world may be incomplete; the people in it must feel alive.**

An outdoor space can be almost empty and still carry a strong presence. A single tree, bench, fence, or distant building may give the scene all the structure it needs. A character can be awkwardly proportioned, visibly distorted, and emotionally exposed without becoming a cartoon.

The visual identity of where-is-school comes from the tension between an expressive, graphic world; the absurd quiet of an exposed stage; and people whose faces and gestures carry more feeling than the spaces around them.


## Current dialogue presentation (implemented baseline)

The current runtime dialogue surface was redesigned and tested in PR #29, and restyled with the first approved portraits on 2026-11-12. This section records the implementation that exists today; it is a production baseline, not a replacement for the integrated portrait direction defined above.

- The dialogue is presented as a text-led band in the lower-left area, fading into the scene along its upper edge. It is sized from the current content and leaves the environment visible.
- **Reading voice (owner's direction, 2026-11-12: "like Disco Elysium's dialogue box").** The band's ground is a dark, nearly opaque ink. The sentence, the speaker name, the title and the choices are set in a serif, Noto Serif SC (`assets/fonts/NotoSerifSC-Regular.otf`), warm off-white on the dark. The rest of the interface keeps Noto Sans SC.
- The sentence is the largest element: 25 px at the standard text size (it was 22 px), with measured line length and generous line spacing. Text is never shrunk to fit.
- The speaker name anchors the composition: tracked capitals in the character's accent color. The role remains small and muted.
- Narrative source (observed, reported, recalled, or imagined) is communicated through a restrained hairline and small label rather than a badge, pill, or saturated block.
- Choices appear as numbered text lines under a rule, set in a warm vermilion that lights to a pale apricot under the pointer or the controller cursor, with a thin margin mark. Avoid filled buttons, decorative iconography, and glow.
- **Portraits.** The protagonist, Q and N have approved painted portraits (`assets/ui/portraits/`, sources in `art/portraits/`). Each one stands on the bottom edge of the screen and enters from the right. All three use the right side so the text band stays where it is when speakers alternate. The two edges facing the picture, the top and the side towards the text, dissolve into the scene, and the screen-border edge stays hard. There is no frame, border or glow. A portrait is never under a word or an option, never takes a click, and never narrows the text. B and the inner voices have no portrait, and nothing is shown in its place.
- The protagonist's portrait also accompanies the protagonist's inspection narration, because those lines carry the protagonist as speaker. This is the current behaviour, not a confirmed decision; see the PR that introduced it.

Keep evolving the reading surface toward the integrated portrait/text composition defined in this Art Bible as more portraits arrive. Preserve the successful properties of the current implementation: text-first hierarchy when needed, Chinese long-form readability, responsive sizing, clear choices, keyboard/mouse behavior, and narrative-source distinction.

Development nameplates over graybox characters are debugging aids, not final game UI. They remain a development-only feature and should not be treated as part of the character portrait system.
