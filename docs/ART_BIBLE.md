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

### Classroom material baseline — 2026-11-12

This is a **classroom-local implementation baseline**, not a mandate to recolor other
locations or characters. ADR 0004's camera comparison and owner visual acceptance remain
open. Preserve the existing room geometry, collision, navigation, exits and story.

**Organize color before adding marks.** Warm ochre light meets blue-grey/violet shadow;
muted rose frames identify the teacher's area and doorway. The empty strip over the board
stays empty: the former red pseudo-writing banner, pins, material, image and generator
entry are removed. Do not replace it with another slogan, glyph strip or decorative decal.

| Role | Recommended sRGB anchors / range | Hierarchy |
|---|---|---|
| Upper plaster | `#CEC2BB`, warm `#E9D5AB`, cool `#9697A7` | Broad, low-contrast planes; quiet above the board |
| Wainscot / window frames | `#47656F`, `#364555`, `#667E82` | Blue-leaning, darker than plaster; do not merge with Q's green clothing |
| Floor | `#898486`, `#A79E91`, `#636C7D` | Quiet walkable ground with one violet-grey counterplane, no invented steps |
| Teacher's floor / lacquer | `#785148`, `#6E3C36` | Muted rose/umber, not a saturated red stripe |
| Board | `#243D3F`, shadow `#212A3A`, chalk `#D6DCCE` | Cool pigment underneath the existing erased heading, diagram and date ghosts |
| Wood | `#A98458`, light `#C8AF81`, cool `#6E725F` | Matte ochre against cool floor; chairs quieter than the bag |
| Window light / schoolbag | `#E0A569`–`#EFCD97`; bag `#BE963E` | Concentrate warm chroma here, not on every surface |
| Contour | near `#2E2933` | Warm-violet dark, never a pure-black cage |

**Material tiers.**

- Walls, floor, boards, lectern, door frames, paper and small functional props keep
  classroom-owned `StandardMaterial3D`: toon diffuse, specular disabled, roughness near
  1.0. Structural walls explicitly use opaque transparency, opaque-only depth draw and
  back-face culling. Their inward-facing paint quads remain 4 mm off solid box meshes;
  do not enable double-sided Alpha blending to disguise a normal or depth problem.
- The photographic student desk is the exception that benefits from a material shader.
  `student_wood.tres` reuses `assets/shaders/painterly/environment_surface.gdshader`
  **read-only**, with classroom-owned pigments, patch strength 0.24 and brush strength
  0.08. `ClassroomPresentation` replaces the source surface and removes the legacy wash
  overlay after the desk wrappers are ready; no photographic albedo, normal or ORM maps
  are sampled. Do not migrate characters, dialogue portraits or every prop to this shader.
- Window views stay unshaded painted images, bounded by dark frames. Glass alone may
  Alpha-blend for the crack/tape and reflection marks; keep the opaque view behind it.
  Clock-face and desk-mark cutouts are functional details, not permission for transparent
  structural surfaces.
- Camera obstruction relief is an explicit exception to opaque walls: a near wall may
  fade only while it obstructs the player/facing ray, then restore the **same** authored
  resources. There must be one fade owner per renderer, not multiplied instance and
  material opacity. Keep the camera, pointer visibility and outline tests together.

**Edges and brushwork.** Use the existing painted seams and irregular color boundaries
rather than distorting collision or raising floor edges. The classroom's optional
inverted-hull contour is **6 mm**, only on selected furniture/props; no wall/floor-wide
outline, character contour retrofit or full-screen oil filter. Remove a contour from a
thin/hard-normal mesh if it produces seams; never widen all lines to compensate. Broad
fields live at approximately 1–3 m scale, subordinate bristle marks at centimetre scale.
Keep marks sparse, fixed to the surface and mipmapped. Chalk, the cracked pane, repaired
set square, timetable and own-desk marks remain meaningful details; do not add generic
noise, grime, pseudo-writing or graffiti to fill quiet space.

**Reuse in the next location.** First validate its walkable geometry and camera. Choose
local warm/cool anchors and one or two chromatic focal objects; retain at least 0.15
value/chroma separation for important object/backdrop pairs and keep broad-plane mean
chroma below 0.20. Copy material *presets* into the new location's own folder, reference
reviewed shaders read-only, and author its texture fields from its own composition.
Do not change this classroom palette or a global shader to restyle another location.
Re-run collision/navigation/interaction/story checks and photograph the actual game
camera plus obstruction-and-restoration views on Forward+ and Compatibility. Source,
rights and deterministic regeneration are recorded in `docs/ASSET_PROVENANCE.md` and
`art/classroom/README.md`; the capture command is `tests/capture_classroom_art.gd`.

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
## Postmodern spatial language and visual plurality

The game's visual direction is intentionally open to heterogeneous media and styles. The earlier expressionist, graphic, hand-made 2.5D language remains an important visual foundation, especially for character identity and the emotional tone of ordinary school spaces, but it is no longer a requirement that every location use one rendering method or one consistent 3D style.

A location may be:
- fully 3D, with deliberately authored geometry and materials;
- a 2D illustrated, painted, photographed, or collaged space;
- a hybrid of 3D geometry and 2D planes, cut-outs, drawings, labels, or image fragments;
- a space whose visual medium changes abruptly as the player moves or interacts;
- an intentionally crude, diagrammatic, theatrical, miniature, mirrored, or otherwise materially unusual construction.

Different locations may have radically different visual identities. Even within one location, a 2D image may intrude into a 3D environment, a flat backdrop may behave as a real doorway, or a familiar object may reveal a spatial impossibility. Do not force these elements to imitate one another to achieve surface-level consistency.

**The unifying identity is literary and experiential, not technical or stylistic.** Each visual discontinuity should feel authored: it should contribute to the game's themes of disorientation, memory, institutional absurdity, unreliable space, and the uncertain boundary between ordinary school life and dream logic. Heterogeneity is not permission for arbitrary visual noise.

### Rules for stylistic discontinuity

1. **Local rules may differ.** Each place may establish its own palette, rendering technique, scale, material logic, and spatial behavior.
2. **Contradiction is a design tool.** A familiar school object may open onto an impossible void, lead to an unrelated location, or reveal geometry that should not fit inside the building.
3. **Use contrast deliberately.** A sudden 2D/3D shift, photographic insert, crude drawing, or change in rendering should have a clear compositional or narrative purpose.
4. **Keep interaction legible.** The player must still understand what can be inspected, opened, crossed, or avoided. Visual ambiguity can be intentional; input ambiguity should not be.
5. **Do not explain every impossibility.** The world may present spatial contradictions without supplying a lore explanation. Let the player encounter and interpret them.
6. **Avoid a single surrealism filter.** Do not cover every location with distortion, noise, strange symbols, or horror effects. Ordinary spaces and quiet stretches are necessary for the impossible moments to matter.
7. **Preserve the human scale of the story.** The people remain psychologically specific even when the space around them becomes irrational.

### Surreal interactions as spatial events

An interaction may change more than an object's state: it may reveal that the apparent architecture was false. A curtain can conceal the absence of an exterior wall; a door can reveal a staircase suspended inside a classroom. Such events should be staged as discoveries, not as conventional fantasy portals with explanatory effects.

Prefer restrained transitions, strong composition, and a clear before/after state. The impossible object or opening should be visually readable from the gameplay camera. Any fall, traversal, or teleport-like transition must have deliberate player feedback, a reliable destination, and safe recovery behavior.

### Location studies and future visual possibilities

The following are approved creative directions for exploration, not claims about implemented content:

- **Biology classroom — the curtained window:** One of the two windows continues to show the ordinary exterior detail of laundry hanging outside. The other is covered by a curtain. When the player chooses to pull it aside, there is no exterior view or building facade beyond it—only open absence. The protagonist falls from the classroom's apparent height and arrives in the schoolyard. The reveal should be quiet and matter-of-fact rather than a conventional jump scare.
- **Biology classroom — the impossible rear door:** The front door remains the ordinary exit. Opening the second, rear door reveals a staircase suspended in the classroom, descending from the ceiling/roof and hanging unsupported through the space above or in front of the teacher's lectern. It should feel architecturally impossible, not like a normal staircase with hidden supports. Its eventual traversal or narrative function can be decided separately. *Current build (issue #159): both doors are in the east wall; the white rear door never opens ("unless special means are used") and no staircase is placed in the classroom.*
- **Mirror-lined crawlspace or pipe:** A narrow passage that the protagonist can crawl through, with mirrored inner walls producing repeated, fragmented, or apparently endless reflections. Reflection behavior may be optically impossible; it need not obey a fully realistic mirror simulation if a designed visual solution communicates the idea better.
- **The schoolyard's impossible animals:** Animals such as a crocodile or lion may appear in an otherwise familiar schoolyard. Their presence should be treated with the same calm, matter-of-fact absurdity as the architecture, not automatically as a combat encounter or horror threat.
- **Future laboratory and other locations:** Each new location may introduce a distinct medium, spatial rule, or visual grammar. A laboratory need not resemble the classroom; a tunnel, corridor, playground, or interior may each have a separate visual treatment.

These are a growing catalogue of motifs, not a checklist to implement all at once. New ideas should be added as location studies with a short statement of their emotional purpose, visual medium, interaction, and relationship to the surrounding space.

### Production and acceptance guidance for heterogeneous scenes

- Decide the intended medium and spatial rule during concept/graybox work, not after a conventional 3D scene has already been fully dressed.
- A scene may combine Blender/Godot 3D assets with 2D textures, sprites, planes, hand-authored illustrations, photographs, or composited images. Record source files and provenance for every external or generated asset.
- Use the simplest technical method that achieves the intended image. Do not build a physically accurate mirror system, procedural portal, or complex geometry when a controlled visual illusion is more reliable.
- Validate the scene in the actual game camera and interaction flow. Test visual transitions, collision, fall destinations, traversal, and player recovery.
- Keep important interactive affordances readable even when their consequences are impossible.
- Do not retrofit every existing location to the new direction. Let the visual plurality emerge location by location, where it serves the experience.
- Performance, accessibility, asset licensing, and maintainability remain requirements regardless of style.

**Updated visual principle:** The world may change its medium, scale, and physical laws from one place to another. The work should still feel like one literary experience because its spaces share a sensibility of estrangement, restraint, and human vulnerability.

## Procedural geometry, vertex masks, and shader-authored surfaces

This is an approved **production technique to explore**, not a requirement to replace Blender or hand-authored assets. Its purpose is to let a small team create distinctive, editable geometry and rich surface character without depending on a large library of image textures, UV layouts, or purchased materials.

### Parametric mesh generation

A small project-owned mesh generator may create selected props, architectural details, organic forms, and non-deforming character accessories directly as Godot `ArrayMesh` resources.

Useful starting operations include:

- **Lathe / rotational profiles:** define a 2D radius-height profile and revolve it around an axis to create turned wood, handles, columns, bottles, chair legs, laboratory glassware, and deliberately distorted organic forms.
- **Loft / swept profiles:** define a sequence of cross-sections along a curve or path, then interpolate position, scale, and optional twist to create cables, pipes, rails, mouldings, roots, tendrils, and irregular architectural connections.
- **Extrusion and bevelled profiles:** create boards, frames, trim, signs, simple furniture parts, and graphic architectural planes from readable 2D outlines.
- **Controlled deformation:** allow profile offsets, asymmetry, taper, waviness, and seeded variation where they support the scene's authored visual language.

The generator should expose a small set of meaningful parameters rather than become a general-purpose modelling package. It must produce predictable topology, valid normals, sensible winding, optional tangents when required, and deliberate end caps. Use a fixed seed for any variation so the same parameters regenerate the same asset.

Prefer **editor-time generation** for authored props and static environment pieces: save the resulting mesh/resource or scene so the shipped game does not need to rebuild it every launch. Runtime generation is reserved for a real gameplay need, not merely because it is possible.

Generated meshes must remain compatible with Godot's scene, collision, navigation, and interaction workflows. Keep render geometry separate from simplified collision geometry. Never let decorative subdivisions or shader displacement change the walkable surface or interaction target unexpectedly.

### Vertex colour as a material mask

For suitable meshes, vertex colour can carry semantic material masks instead of relying on a painted texture or UV atlas. Treat RGBA as four authored channels with documented meanings for that asset family—for example:

- **R:** primary material or pigment region;
- **G:** secondary material, clothing panel, or painted overlay;
- **B:** wear, edge emphasis, or a secondary procedural treatment;
- **A:** optional special mask, transition, or effect control.

These meanings are conventions, not a universal project-wide channel contract. Document the channel mapping beside each generator or material preset. A shader can read the interpolated vertex colour and combine it with object/local coordinates, triplanar projections, analytic patterns, and restrained procedural noise to produce pigment variation, brush-like marks, bands, mottling, edge treatment, or material transitions without a conventional UV texture.

**Important limitation:** vertex colours are interpolated between vertices. They are excellent for broad regions and smoothly blended masks, but cannot create a crisp, detailed boundary on a low-resolution mesh by themselves. Add geometry where a boundary needs to be sharp, increase local vertex density selectively, or use a procedural shader mask based on coordinates. Do not subdivide every mesh indiscriminately.

No-UV does not mean no design. Choose coordinate space deliberately:

- object/local coordinates keep a pattern attached to a moving or rotated object;
- world coordinates can make marks cross adjacent surfaces, but may look as if the material slides when an object moves;
- triplanar projection avoids hand-authored UVs on irregular forms, but must be checked at corners and changes of scale;
- mesh UVs remain appropriate when a specific hand-painted image, decal layout, or authored graphic is important.

The shader should establish a few legible material layers, not cover every surface in generic noise. Keep the existing painterly shader library as reviewed, read-only building blocks where appropriate; location-owned materials should own their palette and parameters. Do not globally migrate all classroom materials or characters to one procedural shader.

### Character and environment applications

Good first candidates include:

- **Environment:** cables and cable bundles in the laboratory, pipes, rails, roots, tree limbs, turned furniture parts, sculptural door handles, irregular frames, and selected architectural transitions.
- **Props:** glassware silhouettes, bottles, jars, tool handles, paper/wooden objects, and small repeated components where a generated profile is faster to iterate than manual modelling.
- **Characters:** selected non-deforming details such as stylised hair clumps, buttons, seams, accessories, and deliberately graphic clothing overlays—only where the existing model topology and rig allow it.

Do not use a first mesh-generator experiment to replace the protagonist's or an NPC's complete Blender model, skeleton, skinning, facial rig, or authored animation. Character silhouette, posture, expression, and stable deformation remain more important than procedural complexity. Keep the dialogue portraits as independent 2D artworks.

### Prototype and acceptance sequence

1. Build one small editor-time lathe generator and one loft generator; do not build a universal node-based modelling suite.
2. Test them on a low-risk prop and on the laboratory cable system before applying them to a hero character.
3. Add vertex-colour mask output and one deliberately restrained shader preset.
4. Compare the result in the actual game camera, under the location's real lighting, at normal gameplay distance.
5. Check seams, normals, winding, underside visibility, material transitions, collision, navigation, interaction picking, and both Forward+ and Compatibility renderers.
6. Record generator parameters, fixed seeds, shader version, source ownership, and regeneration steps. Generated assets still need provenance and rights records where any external source is involved.

The success criterion is not maximum procedural detail. It is a repeatable way to create a few memorable forms and surface treatments that would otherwise require unavailable textures or excessive manual asset work.

## Procedural sound design

The project may use synthesis to create original sound effects without a sample library. This is already an established technique in the interaction system: `scripts/audio/cue_audio.gd` builds four deterministic, quiet cue buffers at startup and plays them through reusable `AudioStreamPlayer` voices. Preserve that design as the baseline rather than introducing a second audio architecture unnecessarily.

### Choose the stream type for the job

- **Short, fixed sound effects:** prefer generating sample data into an `AudioStreamWAV` buffer once, then reusing it. This suits clicks, knocks, soft impacts, small UI sounds, short mechanical movements, and other repeatable cues. It avoids generating the same samples every time the sound plays.
- **Continuous or changing procedural sound:** consider `AudioStreamGenerator` when samples genuinely need to be produced while audio is playing—for example, evolving electrical hums, unstable fluorescent lights, distant machinery, a changing resonant drone, or a sound whose pitch/timbre follows a live gameplay parameter.
- **Designed music, long ambience, or complex authored performances:** do not assume procedural synthesis is automatically better. A properly licensed recorded or composed asset may be more expressive, easier to mix, and cheaper to maintain.

`AudioStreamGenerator` is a playback buffer interface, not a complete sound-design system. Its producer must keep the playback buffer supplied at a controlled rate. Avoid allocating large arrays, doing expensive scene work, or generating unbounded noise in a per-frame gameplay callback. Keep synthesis bounded, deterministic where repeatability matters, and isolated from gameplay state.

### A small synthesis vocabulary

Build sounds from a few controllable ingredients:

- sine and other simple oscillators for tonal bodies;
- harmonics and inharmonic partials for metal, glass, wood, and mechanical character;
- filtered or shaped noise for air, friction, static, paper, and impact texture;
- short attack/decay envelopes to avoid clicks and keep events concise;
- pitch bends, amplitude modulation, and restrained frequency modulation for movement and instability;
- resonant filters, short delays, and carefully limited reverb where the sound needs a sense of space.

The point is not to make every sound electronic. A short wooden knock can be built from a low transient, a few inharmonic resonances, and a fast decay; a glass object can use brighter partials and a longer, quieter tail. The synthesis should communicate the material and action, not advertise the algorithm.

### Audio design rules

- Keep effects subordinate to dialogue and important environmental sounds; use deliberate headroom and avoid clipping.
- Use attack/release envelopes or equivalent smoothing to prevent clicks at buffer boundaries.
- Clamp or otherwise control output levels; test peaks and perceived loudness, not just numeric amplitude.
- Rate-limit sounds that can be triggered rapidly by pointer movement or repeated overlap.
- Reuse streams and voices; do not create a new player and a new buffer for every interaction.
- Keep sound generation separate from the code that decides what happened. Gameplay sends a semantic cue; the audio layer decides how that cue sounds.
- Respect the existing Master, Music, and SFX volume controls and mute behavior. Do not add an autoload for a small local sound generator unless several independent scenes genuinely need a shared lifecycle.
- Prefer deterministic seeds for authored procedural sounds so tests, captures, and repeated events remain comparable.
- Test on actual Windows speakers/headphones at the intended mix level. Headless tests can verify stream format, duration, peak, determinism, rate limiting, and routing, but cannot replace listening.

### First useful sound experiments

- A small set of classroom and laboratory object interactions: paper, wood, glass, metal, switches, drawers, and cables.
- Low-level room tones that can subtly change with the space, rather than a constant generic horror drone.
- A fluorescent light or electrical device whose hum changes slightly when approached or inspected.
- A cable/pipe resonance that supports the laboratory's visual trail without turning it into a loud puzzle indicator.
- Restrained scene-transition and spatial-event sounds that make impossible changes feel physical but not magical.

Each sound should have a clear gameplay or narrative reason to exist. Silence remains a valid and often preferable sound-design choice.
