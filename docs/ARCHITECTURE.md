# Runtime Architecture

This document defines boundaries, not an excuse to build every planned subsystem immediately. Implement a subsystem when a playable requirement needs it; keep its ownership clear as it grows.

## 1. Top-level structure

~~~text
project.godot
scenes/
  main/                 # project entry scene and high-level composition
  actors/player/        # player scene and reusable actor scenes
  locations/            # authored location scenes, not procedural world data
  environment/           # reusable architecture and prop scenes
  ui/                   # menus, HUD, dialogue, journal
  cutscenes/             # authored in-engine sequences
scripts/
  autoload/              # very few application-wide state services
  actors/                # movement and actor behavior
  interaction/           # interaction contracts and targeting
  dialogue/              # dialogue runtime and adapters
  rpg/                   # inner voices and the one dice core
  world/                 # world state and spatial rule behavior
  save/                  # serialization and migration
  ui/                    # UI-specific presentation logic
data/
  dialogue/              # narrative content, not hard-coded in gameplay scripts
  inspections/           # object descriptions, per language
  abilities/             # inner-voice values, passive rules, and their text
  characters/
  items/
  locations/
assets/
  characters/
  environment/
  materials/
  audio/
  fonts/
addons/                   # editor-only tooling; nothing here ships (see 5i)
tests/
docs/
~~~

Directories are created when a real asset or implementation lands; do not add large collections of empty placeholders.

## 2. Dependency direction

Keep dependencies moving from presentation toward application/domain logic:

- **Scenes** compose nodes and resources. A scene should not own the entire narrative or save implementation.
- **Actor scripts** own local movement, animation requests, and actor state.
- **Interaction** identifies a target and requests an action; it should not decide how dialogue UI is drawn.
- **Dialogue runtime** advances a content graph and emits presentation events. It should not directly manipulate arbitrary level nodes.
- **UI** renders state and sends player intent. It should not become the authoritative story-state store.
- **World state** owns named story/world flags and offers small APIs.
- **Save system (future)** serializes explicit data snapshots. It must not serialize arbitrary live Nodes or scene-tree references.

Use signals at clear boundaries. Do not create a global event bus by default; first consider a direct reference, a signal on the owning node, or a narrowly scoped controller.

## 3. Autoload policy

The project contains **five** autoloads, and this list is the only place that number is
written down.

| Autoload | Script | What it owns |
|---|---|---|
| `GameState` | `scripts/autoload/game_state.gd` | runtime story flags and snapshot/restore of those flags |
| `NarrativeState` | `scripts/autoload/narrative_state.gd` | append-only narrative knowledge entries (observed / reported / recalled / imagined), de-duplicated by id, with snapshot/restore |
| `Loc` | `scripts/i18n/loc.gd` | the current locale, the locale tables, and the `locale_changed` signal (see §5b) |
| `CueAudio` | `scripts/audio/cue_audio.gd` | the four synthesised interaction cues, built once at startup (see §5e) |
| `Music` | `scripts/autoload/music_player.gd` | the one background-music player, on its own `Music` bus, for the whole session (see §5m) |

- **GameState** is not a dumping ground for quests, dialogue UI, scene transitions,
  audio, inventory, settings, or save-file I/O.
- **NarrativeState** exists because knowledge categories are used by dialogue,
  inspection, and presentation independently of gameplay flags; see
  `docs/adr/0002-dialogue-and-narrative-state.md`.
- **Loc** is an autoload because two unrelated scenes (the HUD and the dialogue panel)
  have to agree on the language within a frame, and because the settings that pick it
  are read before any scene exists. It loads every language's table at startup; see §5k.
- **CueAudio** is an autoload because the pointer, the props and the interactions all
  make the same four sounds and must therefore be the same four buffers; it owns no
  nodes beyond its four players.
- **Music** is an autoload because the background music must *not* belong to a room: a
  player inside a location restarts with the location, so every doorway would restart the
  take, and a player per room would overlap for a frame during a transition. It owns one
  `AudioStreamPlayer` and one stream, and it refuses to restart what is already playing.

Earlier revisions of this section said "two autoloads" and did not mention `Loc` or
`CueAudio`. That was wrong, not a plan: both had shipped in earlier rounds. `Music` is the
first autoload added since, and this list moved with it in the same change rather than
afterwards.

Add another autoload only when:
1. multiple independent scenes genuinely need the same service;
2. ownership and lifecycle cannot be expressed cleanly by a scene-level node;
3. the API is small and documented;
4. tests can validate it independently.

A future save manager should call explicit serializers and use a versioned save schema. It should not be merged into GameState.

## 4. Scene ownership

- The main scene composes the active location and persistent application-level nodes.
- Location scenes own their local geometry, navigation affordances, lighting, and location-specific interactive props.
- Reusable architecture/prop scenes belong under scenes/environment/.
- The player scene owns its controller and nothing about the camera. A `CameraRig` sibling in
  the main scene owns the camera, its offset, its field of view and its roll, and follows the
  player's position once per physics frame (ADR 0004 decides what that framing looks like).
  The player keeps `set_camera_roll`/`settle_camera_roll` as thin entry points because the
  sequence director already speaks that vocabulary.
- UI scenes should be replaceable without rewriting narrative data.

Avoid hard-coded NodePaths that reach across unrelated scene ownership. Prefer exported Node references, signals, groups used for a documented purpose, or explicit service APIs.

## 5. Narrative data contract

Dialogue content must be separate from gameplay scripts. The current milestone
implements a project-owned layer (see ADR 0002) that satisfies the requirements
below.

> **Recorded conflict.** Earlier revisions of this section described the Dialogic 2
> integration spike as an open decision and asked for it to be run before choosing.
> The implementation went ahead with the in-project layer, and ADR 0002 records that
> choice. The spike has not been run and is no longer planned; ADR 0002 stands. The
> paragraph below is kept as the checklist that decision had to satisfy.

Before adopting a dialogue addon or format, validate that it supports:
- long Chinese text and readable typography;
- named speakers and portrait identifiers;
- choices and conditional choices;
- story flags and explicit state changes;
- history/backlog and accessibility controls;
- interruption by environmental events;
- deterministic serialization of the current conversation state, if mid-conversation saves are required.

**What happened instead.** The checklist above was met by the in-project layer
described in §5b and ADR 0002; no dialogue addon is installed or pinned. The bounded
Dialogic 2 spike was never run and is no longer planned, so it is not a pending task:
the requirements it was meant to test are the ones the shipped layer is held to by the
content and runtime tests. The paragraphs that asked for the spike are kept only as the
checklist it had to satisfy. If a later decision reopens the question, it starts as a
new ADR, not as an implicit migration.

## 5b. Where text lives (implemented contract)

Every line the game says is data, in two languages, loaded by chapter:

- `data/dialogue/<locale>/<chapter>.json` — conversations (ids, speakers, text,
  `next`, choices, effects, conditions, narrative source);
- `data/inspections/<locale>/<chapter>.json` — object descriptions, their prompt,
  the first-read and repeat text, the optional recollection, the knowledge entry
  they record and the effects they apply once;
- `data/locale/<locale>.json` — the short strings the interface generates
  (prompts, objective labels, source badges, end card).

`DialogueGraph`/`DialogueLibrary` parse and validate the dialogue,
`InspectionLibrary` the descriptions, and `L10n` (static) plus `Loc` (autoload,
persisted in `user://settings.cfg`) the interface strings. Both language trees must
have identical structure; `DialogueParity` compares them node by node and reports
any dropped node, choice or effect. Authors edit JSON, not GDScript; the schema and
the editing rules are in `data/dialogue_schema/README.md`. Since Phase 6a.1 they can also
edit it from inside the editor, both languages at once, through the dock described in
§5i — which is a convenience over the same files, not a second format.

Nothing in `scripts/` may hold narrative text. The only literals left in scenes
(`prompt_text`, `end_card_title`) are fallbacks used when content is missing, and
the dialogue controller prefers the localized key or the inspection's own prompt.

The display language can change at any time: `Loc.locale_changed` makes the
dialogue controller rebind the open conversation to the same node id in the other
language, re-resolve the prompt, redraw the backlog and re-translate the objective.
No scene reload, no lost state.

A rebind is a **re-render, not a new event**. The runtime re-emits the node it is
standing on; the controller marks that window (`_republishing`) and neither applies
effects, records knowledge, rolls a check, nor appends anything. History is stored by
identity, never by text (see §5g), which is what makes repeated `en → zh-CN → en →
zh-CN` switching idempotent — the case issue #18 reported.

The validator is only worth what it proves, so its walk follows the runtime's edges
and nothing else: a `choices` node reaches only its options' targets (the runtime
blocks `advance()` while an option is on screen), a `check` node reaches only its
`success`/`failure` targets, and only an ordinary node falls through to the next node
in file order. A line parked after a hub with no edge of its own is therefore reported
as unreachable — which is what issue #20 was: the walk added a sequence edge the
runtime never takes, and dead lines passed CI. When no option is available or a
skipped `check` node has no branch of its own, the presentation ends instead of
advancing somewhere the schema says is unreachable, so "unreachable" in an error
message means unreachable in play.

## 5c. Inner voices and checks (implemented contract)

The ability system is deliberately small and lives in three places, each with one
job:

- `scripts/rpg/check_resolver.gd` — the only code that throws a die. Pure maths
  (`2d6 + value + modifier >= difficulty`, provisional), an injected session seed, and a result
  dictionary. It knows nothing about content, UI or flags.
- `scripts/rpg/inner_abilities.gd` — reads `data/abilities/abilities.json`
  (values, speakers, passive rules) and `data/abilities/<locale>.json` (names and
  descriptions), validates them strictly, and reports every problem with a file
  path, an ability id and a speaker id.
- `scripts/world/inner_voice_director.gd` — decides *when* a passive voice may
  speak: event triggers, `once` per rule, a per-voice session cap, no two
  unprompted lines in a row, and silence while an authored beat, a conversation or
  the end card owns the frame.
- `scripts/dialogue/character_directory.gd` — the presentation side of every
  speaker. Ordinary characters come from a short explicit list; inner voices come
  from the registry (see below).

A check itself is dialogue data, not a script: a node carries a `check` block with
an ability id, a difficulty, `kind` (`visible`/`hidden`) and two branch targets.
`DialogueGraph` validates the block, `DialogueRuntime` resolves it when the node is
entered, emits `check_resolved`, records the result under
`check:<conversation>:<node>` and continues to the branch. `DialogueController`
shows visible results in `CheckOverlay` and shows nothing for hidden ones.

Invariants that later work must keep:

1. exactly one dice implementation; both modes call it;
2. the RNG is injectable and seedable, so tests never depend on luck;
3. a resolved check is recorded and replayed, so re-entering cannot reroll it;
4. a failed check may never be the only route past a required beat;
5. no gameplay script may contain a roll, a difficulty, or an ability name.

### Several voices, kept apart without being rewritten

The registry is a *list* of voices; how many entries it holds is content, not code.
This milestone ships one (`orientation`) and the owner has decided the cast will
grow, so the plumbing was separated from the prose in a dedicated pass. Three
identities are never allowed to merge:

| What | Where it lives | What must be true |
| --- | --- | --- |
| `ability_id` | key of the `abilities` object | unique; the id a `check` block names |
| `speaker_id` | `speaker` field of that ability | unique across voices and ordinary characters; the only link to a profile |
| `value`, `max_passive` | that ability's fields | read per voice; one voice's number or count can never be read, spent or overwritten by another |

**Finding a voice's profile is a lookup, not a scan.** A voice's presentation lives
at `data/characters/<speaker_id>.tres`, and the directory loads exactly the speaker
ids the registry declares. There is no directory scan (which would only work in an
editor checkout, not in a packed build) and no second list of voices to keep in
sync — `CharacterDirectory.ORDINARY_CHARACTER_PATHS` stays explicit for people
only. `DialogueController._ready()` therefore loads the registry *before* the
directory. A missing profile, a profile whose `character_id` disagrees with the
speaker it is loaded for, or a speaker id that collides with an ordinary character
is a start-up error naming both ids and the file. There is deliberately **no
fallback**: a voice that speaks with another voice's name and colour is worse than
one that does not appear.

**Active checks were already per-ability**; what this pass pins down is that nothing
leaks between them. A check node names its `ability_id`, the runtime reads that
voice's `value`, and the result is recorded under `check:<conversation>:<node>`, so
two voices in one conversation keep two independent records and neither re-rolls.
Visible and hidden checks still share one `CheckResolver`.

**Passive lines resolve late, in file order.** Several voices may be able to answer
one event, so the director queues the *event* and only picks the voice when the
frame is free: `InnerAbilities.get_rules_for()` returns the rules that match in
`data/abilities/abilities.json` order and the first one still allowed to fire wins.
File order is the priority rule — deterministic, testable, and editable by moving a
line in the file — so two voices can never race for one event. Resolving at fire
time also fixes a state loss: a rule that was capped when the event happened but is
free by the time the frame clears is still considered, and the event is never
dropped in favour of a rule that could not speak. `once` stays per rule, the session
cap stays per voice, one event may wait at a time, and one unprompted line still
cannot chain into another.

ADR 0003 records the reasoning, the formula, the frequency policy and the open
design questions. It is a **proposal**: exactly one voice ships in this milestone
(`orientation`), and every number in it is provisional. The cast itself — how many
voices, what they are called, what they are worth — is the owner's decision and is
not decided by anything in `data/` today.

## 5d. The companion, and why it is not in a location

`scripts/world/companion_controller.gd` lives on the main scene, next to the player,
not inside `LocationRoot`. `LocationHost` frees everything under a location on every
transition, so a companion authored there would vanish at the first door. The
controller instead listens to `LocationHost.location_entered`, places Q behind the
player after a swap, and hides itself in any location that already has an authored
actor with the same `npc_id` — which is how two Qs are made impossible rather than
merely unlikely. It owns no dialogue: the "ask along" interaction is an ordinary
`Interactable` with a `conversation_route`, so the same director that plays every
other conversation plays that one.

## 5e. Targeting: pointer, facing, and the cue

`InteractionController` resolves one target per physics frame from two inputs:

- a screen-space ray from the camera through the pointer, restricted to the
  interaction layer, with the same reach and line-of-sight rules as facing;
- the facing/distance score that existed before.

The pointer wins when it hits something, a new pointer pick has to hold for one frame
before it replaces a different target, and facing takes over immediately when the
pointer hits nothing. `_set_current()` is the only place that assigns the target and
the only place that moves the highlight, so the cue and the E key cannot describe
different objects. `Interactable` builds its cue mesh in code, so no prop needs a
scene edit to become hoverable.

## 5f. Navigation, click-to-move, and automatic interaction

Three objects, three jobs. None of them may grow into the others.

**`LocationNavigation` (`scripts/world/location_navigation.gd`) — the data.**
A `NavigationRegion3D` that is a direct child of each location root and bakes its mesh
from *that location's own* static colliders in `_ready()` (deferred by a frame, because
siblings are still entering the tree while it runs). Runtime baking is a deliberate
choice over checked-in meshes: several locations are generated by
`tools/build_outdoor_locations.py`, so a stored mesh would go stale the first time a
box moved and nothing would notice. The bake is configured with the agent radius
(0.4 m, wider than the 0.35 m capsule so the body does not grind along walls), a
0.3 m climb equal to the body's own `max_step_height` so kerbs and thresholds are
ramps for both of them, and the navigation map's own cell dimensions — a mesh whose
`cell_size` disagrees with the map is silently refused by the server, which looks
exactly like a mesh with no polygons. The geometry is collected by the component
itself (every `StaticBody3D` under the location root, at any depth, on the world
layer) rather than by the engine's source-geometry parser: a room's desks and chairs
are instanced props two or three nodes down, and furniture that is silently left out
bakes a floor plate that paths run straight through. `get_polygon_count()` and
`is_routable()` are the honest health checks — a baked mesh, and a map that can
answer a route from it — and `tests/navigation_test.gd` fails a location that bakes
nothing or whose polygons never reach the map.

The bake also measures itself, once per bake rather than per frame:
`get_bake_usec()` and `get_collect_usec()` time the whole bake and the geometry
collection inside it, `get_geometry_face_count()` is the number of collision faces
parsed and `get_polygon_count()` the number of walkable polygons produced, and
`get_bake_error()` names the reason a bake failed. A debug build prints one line per
bake; a release build prints none. The point is that "this door hitches" is a number
(the bake, and the load that precedes it) rather than a feeling.

**`PlayerController` — the only movement.** It has one `_apply_movement()` that writes
velocity, applies gravity, calls `move_and_slide()` and turns the visual; manual input
and path following both feed it a direction. A walk is started with
`request_path_to(point)`, which refuses (returns false) when control is locked, when
the map has no geometry, when the point is more than 0.75 m off the mesh horizontally
or more than 1.5 m off it vertically, or when `map_get_path()` produces no route. The
route that comes back is kept and walked in order: each physics frame the body steers
at the next corner, dropping any corner it has arrived at (`waypoint_radius`, 0.35 m).
The body follows the route itself rather than asking the `NavigationAgent3D` for a next
position, because the agent's own path index is updated on the server's step and lags
the body: with a long physics step the character could rock between two corners it had
already passed, indefinitely. Arrival is measured against `arrival_radius`, and a stall
watchdog (`stall_timeout`, 2 s without progress) ends a walk that is pressed against
geometry instead of letting it push forever. There is no second
movement system, and no code path sets `global_position` to fake progress.

**`PointerNavigator` — the intent.** It listens on `_unhandled_input`, so a click a
`Control` consumed — a dialogue option, the backlog, any overlay — never reaches the
world. One click resolves to exactly one of three outcomes:

1. an interactable under the cursor (picked with the same ray the hover uses, but
   without the reach limit, because a click may legitimately name something across the
   room) becomes the target: find a spot inside its radius that is on the mesh, has a
   real route and keeps line of sight, walk there, then **re-validate** — still valid,
   still enabled, still in reach — and call
   `InteractionController.request_activation()`, the same call E makes. Activation
   happens at most once, and the pending target is dropped on arrival, on failure, on
   cancellation, and on any location change;
2. otherwise, walkable ground under the cursor is a destination: the ray only tests
   the world layer with bodies (never areas), the surface normal must face up, and the
   hit point must be within `max_snap_distance` of the navigation mesh;
3. everything else is refused: the ring contracts in the refusal colour and the
   character stays where they are. No walk, no dialogue, nothing to dismiss.

**The cues the mouse draws** (`scripts/interaction/world_cue.gd`,
`hover_cue.gd`, `destination_cue.gd`, `outline_overlay.gd`). Three decisions hold them
together:

- **One palette, one pen.** `WorldCue` owns the colours (bone = where you clicked, amber =
  the thing you clicked or can use, a duller rose = refused), the outline colour, the pen
  widths and one cached unshaded alpha-only material per role. A cue is a mark, not a
  light: unshaded, no depth write, back faces drawn, so it reads on any surface without
  being lit by the room or punching a hole in what is behind it. Every mesh is built in
  code (`SurfaceTool`), so no prop, scene or camera distance needs new art.
- **The object is outlined, not circled.** The owner asked for the usable object to be
  shown the way Disco Elysium shows it: its own contour, traced. `HoverCue` asks the
  interactable for `get_outline_meshes()` (the nodes named in `outline_paths`, plus any mesh
  parented under the interactable) and hands them to `OutlineOverlay`, a `CanvasLayer` in
  `scenes/main/main.tscn` (layer 0, under every UI layer). The overlay renders a silhouette
  mask into a `SubViewport` from a camera that copies the player's camera every frame, and
  runs `assets/shaders/interaction/highlight_outline.gdshader` over it: a 2 px warm line just
  outside the silhouette (scaled with the window height), a dark rim outside that, and a
  faint wash over the object. The mask viewport renders only while something is outlined.
  One object is outlined at a time; a new owner replaces the old one at once, and a late
  fade from the old owner is ignored, so a hand-over never dims the new outline. An
  interactable with no mesh to trace (an exit that is only an opening) falls back to a small
  amber diamond above its anchor. An inverted hull was rejected because it tears open at box
  corners; the `BaseMaterial3D` stencil outline because it needs a material change on every
  surface.
- **The outline is depth-aware: it traces what the player can see of the object.** An
  object behind a wall has no outline, and one half behind a post is outlined only along its
  visible part (and along the post's edge where the post cuts it). The mask is depth-tested,
  in three steps inside the one mask render: (1) the mask camera draws the whole scene
  (the player's camera's layers plus `MASK_LAYER`), unshaded and with its far plane just past
  the farthest highlighted mesh, so its depth buffer holds everything in front of the
  object; (2) a full-screen quad on `MASK_LAYER` paints the colour black without testing or
  writing depth; (3) each highlighted mesh gets a twin - an internal child drawing the same
  mesh (same skeleton and skin) on `MASK_LAYER` only, with a key material - which draws
  white in the transparent pass with the ordinary depth test, so it lands only where the
  mesh is the nearest surface. The mask's red channel is the visible
  silhouette, and the ink shader reads that channel. Both mask shaders are built in
  `outline_overlay.gd` and collapse themselves for any camera without `MASK_LAYER` in
  `CAMERA_VISIBLE_LAYERS`; the overlay clears that bit from the player's camera, so the
  frame the player sees is unchanged. The mesh's own materials and overlay (the classroom
  desks' shared ink overlay) are never touched; releasing frees the twins and gives every
  mesh back exactly the layers it had.
  - *Why a second scene pass rather than the frame's depth.* The outline is composited in
    2D over the tonemapped frame so its colours are exact; a canvas shader cannot read the 3D
    depth buffer, and a 3D full-screen quad that could (`hint_depth_texture`) would be
    tonemapped and glowed with the room. The mask pass costs a second, unlit, shadowless draw
    of what lies between the camera and the object, only while an outline is shown.
  - *Compatibility renderer.* Everything used (overlay materials, `CAMERA_VISIBLE_LAYERS`,
    `POSITION`, render priority, depth test in the transparent pass) exists in Godot's
    Compatibility renderer, and `tests/interaction_outline_occlusion_test.gd` proves the
    behaviour there on rendered pixels: CI runs it under Xvfb with `--rendering-driver
    opengl3`, checks an open, a fully hidden and a half-hidden box plus switching, release
    during a fade and a moving camera, and uploads the frames as the
    `outline-occlusion-evidence` artifact.
  - *Known limits.* Only surfaces that write depth hide the outline. A wall the occlusion
    fader has turned see-through (`transparency` 0.82, drawn in the transparent pass) does
    not, which matches what the player sees through it; nor does other alpha-blended
    geometry. The key is pulled 2 mm + 1 mm per metre towards the camera so it never loses
    the depth test to its own surface; something closer than that in front of the object
    does not hide it. The environment's inverted-hull ink lines (`environment_outline.gdshader`)
    do not write depth, so they never hide an outline. A twin copies the mesh, skeleton,
    skin, LOD bias and visibility range, not blend-shape weights (no outlined mesh uses
    them).
- **The pointer finds the object where the outline is.** An interactable's own shape is a
  sphere around its anchor, and the anchor of a door or a notice is a point in front of it.
  As a pointer target that sphere was off to one side of the thing on screen: the door's
  cue lit while the cursor was on the floor beside it. `Interactable._build_pick_shapes`
  adds a box (the mesh's bounds, grown by 5 cm, at least 12 cm thick) for each outline mesh
  to the same area, deferred until the room has its final transforms and measured again
  whenever the visibility of the interactable or of an outlined branch changes (the
  companion is hidden until Q joins, and a hidden branch gets no box). Meshes longer than
  12 m and paint on the floor (thinner than 5 cm, lying more than 0.25 m under the anchor)
  get no box, so a click on the court still walks. Proximity is unchanged:
  `InteractionController` still ranks facing candidates by their anchor, and only those
  whose anchor sphere the sensor sphere overlaps (`_sensor_reaches_anchor`).
- **Motion is the interface, then stillness.** The ground mark lands (contracts from 1.9x
  onto its radius in 0.2 s, the dot popping in after it), sends one thin echo outwards
  (to 2.6x over 0.5 s), and then holds still for the rest of the walk: a mark that moves
  while the character walks is a mark the player watches instead of the destination. The
  outline fades in over 0.12 s and out over 0.16 s instead of switching between frames. The
  refused cue is the exception that proves the rule: its ring *contracts* with no dot and no
  echo, because an outward motion is a promise of a walk.
- **The cue is laid on the world, not on a plane.** The navigator passes the ground normal
  under the click (one short ray, only on a click) and the cue's basis puts its +Y on that
  normal, so a kerb, a ramp or a tilted floor plate gets a ring that lies flat on it. A
  click on an object walks to an approach spot that `PointerNavigator` puts on the floor
  (not at the anchor's chest height), and a refused click is marked on the ground under
  the point that was clicked, so neither mark floats in the air beside a door.
- **The cue is heard as well as seen.** `scripts/audio/cue_audio.gd` (the `CueAudio`
  autoload) owns four synthesised buffers — bone, amber, refusal and the hover tick — and the
  role that decides the colour decides the sound: the navigator calls `_announce(role)`
  before it draws, and the interaction controller's highlight makes the hover tick. The
  buffers are computed at startup, not shipped: no file per sound, no import sidecar, no
  licence. Levels live in the same file as the tones (−20 … −30 dB, under the room tone), and
  only the hover tick is rate-limited, because it is the only one the pointer can machine-gun.
  A headless run without autoloads looks the node up by path, finds nothing, and stays silent
  rather than failing.
- **Nothing here decides anything.** The navigator decides what a click meant and tells the
  cue; the cue knows no targets, routes or walks. The object's own highlight stays with
  `InteractionController` — exactly one interactable is ever lit, which is what makes "E
  uses what the cue shows" true — so a walk towards a clicked prop is drawn in the *target*
  colour at the spot the walk ends on, never by lighting the prop itself.

**The rules that keep these apart** (each one has a test):
`tests/navigation_test.gd` — per-location bake and spawn coverage, spawn→exit
reachability, arrival and post-arrival stillness, refusal of off-mesh points, an
isolated island that must not be climbed, a wall that must be walked around, manual
cancellation, destination replacement, and cancellation across a location swap.
`tests/automatic_interaction_test.gd` — click-to-talk from across the room,
immediate activation in reach, an inspectable prop, an exit (through the director, so
the transition and the story routing are the normal ones), a target disabled or freed
mid-walk, E still working, and ground clicks never activating anything.
`tests/dialogue_pointer_test.gd` — one option per click, no fall-through to the world,
digits, hover styling, layer order, and a language switch that re-renders the options.
`tests/street_prompt_test.gd` — the street's own prompt key, and the story's door
rewrite touching only the classroom door.
`tests/interaction_cue_test.gd` — the two cues as objects rather than as pixels: the ground
mark is a thin ring and a dot of about 0.3 m that lands, echoes once and then holds still;
a role decides the colour; it is laid on the ground normal it was given; a refusal contracts
and ends itself; a dismissed cue hides. The outline marks the object's own meshes and gives
them back their layers, hands over between objects without the old fade erasing the new
outline, is released when a highlighted prop is freed, falls back to the diamond when there
is nothing to trace, and a ray at an outlined mesh finds the object.
`tests/interaction_outline_content_test.gd` — the same on shipped content: every
interactable in the classroom, corridor, street, residential area, alley and schoolyard, and
the companion's, resolves meshes to trace and has a pick box for each one that should have
one; the overlay sits under every other `CanvasLayer`; nothing authored uses layer 20.

`tests/interaction_audio_test.gd` — the same cues in the ears: four distinct 16-bit mono
buffers, their peak levels, that an unknown kind plays nothing, that muting counts nothing,
that twelve hover ticks in one frame produce one sound and the next interval produces another,
and that `Interactable` and `PointerNavigator` ask for the sound that matches what they draw.

The same workflow compiles `tests/capture_playthrough.gd` with `--check-only`. No test loads
that script — only the window capture does — and a parse error in it once hid for weeks
behind a workflow that read the previous run's log: `get_tree()` does not exist inside a
`SceneTree`, and `await get_tree().physics_frame` therefore stopped the whole file from
loading. See `docs/IMPLEMENTATION_NOTES_NAVIGATION.md` §4 for the other two guards that came
out of the same failure.

## 5g. The reading surface: dialogue panel, history, name labels

The dialogue is a **reading surface at the edge of the world**, not a chat window.
The room is the picture; the panel is the text laid over its lower edge.

### Hierarchy and layout (`scenes/ui/dialogue_panel.tscn`)

```
DialoguePanel (Control, lower-left band, mouse passes through)
└── Wash            vertical ink gradient, fades the band's top edge into the scene
└── Frame           subtle PanelContainer, no border, no glow
    └── Content     VBox
        ├── SourceRule     2 px hairline tinted by narrative source
        ├── HeaderRow      SpeakerLabel (26, tracked) · RoleLabel (13, muted)
        │                  · Spacer · SourceBadge (12, tracked, muted)
        ├── TitleLabel     16, only for recollections
        ├── BodyLabel      RichTextLabel, 22, line separation 10, the largest thing here
        ├── ChoiceRule     1 px rule separating prose from options
        ├── ChoicesContainer
        └── HintLabel      12, right aligned
```

Rules the layout keeps, and why:

1. **The band never becomes the screen.** Width is 60% of the viewport, clamped to
   620-1040 px; height is measured from the content and capped at 62% of the viewport.
   A long paragraph scrolls inside the body instead of growing the panel.
2. **Type is fixed.** 22 px body, 20 px options, 26 px speaker name at every
   resolution. The panel adapts to the text; the text never shrinks to fit the panel.
3. **The name is the anchor, the role is secondary.** The speaker name carries the
   character's accent colour; the role is smaller and muted; the source is a hairline
   plus a 12 px tracked label. `observed`/`reported`/`recalled`/`imagined` stay
   distinguishable, but nothing shouts.
4. **Options are text, not buttons.** Flat, left aligned, numbered, one per line; hover
   raises the line and draws a 2 px margin mark. They keep
   `mouse_filter = MOUSE_FILTER_STOP` and `focus_mode = FOCUS_NONE` so a left click
   selects exactly one option and never leaks to the world, and the 1-9 keys go through
   the same `choice_selected(index)` signal. Everything else in the band is
   `MOUSE_FILTER_IGNORE` and the band root is `MOUSE_FILTER_STOP`, so a click on the
   reading surface itself continues the line (`_gui_input` → `_request_advance()`), a
   click while a choice is open does nothing, and a click outside the band is swallowed
   instead of continuing the line from the other side of the screen.
5. **No portraits yet.** The layout leaves the left margin and the free space above the
   band for a future portrait; nothing renders one. (Portrait art is not in the
   repository and must not be faked with a placeholder silhouette.)
6. The panel is measured, not tuned: `_settle_layout()` runs in two passes, first
   applying the width the text will wrap at, then measuring what that produced.
   `tests/dialogue_layout_test.gd` asserts the result at 1280x720, 1600x900 and
   1920x1080 with long English, long Chinese, three paragraphs of recollection, four
   long options, an over-long name and role, and an inner voice.

The panel's public surface is unchanged by any of this: `advance_requested`,
`choice_selected(index)`, `backlog_requested`, `show_line`, `set_choices`,
`refresh_static_text`, `redraw_current_line`. Presentation changes; the controller and
the runtime do not.

### History by identity (`scripts/dialogue/dialogue_history.gd`)

`BacklogPanel` stores **descriptors**, not screen rows: identity, the conversation or
inspection it came from, the speaker, the narrative source, and the last rendered text
as a fallback. Rows are rebuilt from descriptors by a resolver the controller supplies
(`_render_entry`), which recomposes a conversation line with
`DialogueRuntime.compose_line()` — the same static function the live runtime uses — or
an inspection line from its id and variant.

Identities come from content ids only:

| source | identity |
|---|---|
| conversation line | `conv:<conversation_id>/<node_id>` |
| inspection | `inspection:<inspection_id>/<variant>`, variant `first`, `repeat` or `recall` |

Consequences:

- a language switch replaces the newest row when its identity matches and appends
  nothing (issue #18);
- two different events are never merged, even when their text is identical, because
  only an explicit republish touches the newest row and text is never compared;
- `first`, `repeat` and `recall` stay three distinct entries, in reading order;
- descriptors are stored with `effects`, `record` and `set_flag` removed, so a rebuild
  physically cannot re-apply an effect, re-record knowledge or flip a flag;
- `DialogueController._history` is the narrative record and
  `BacklogPanel.get_entry_identities()` must always agree with it.

### Character name labels (`scripts/actors/character_nameplate.gd`)

Grey-box people have no faces, so each actor scene carries a `CharacterNameplate`
(a `Label3D` named `Nameplate`):

- the name is resolved from `CharacterProfile` + `data/locale/*.json` (`name.<id>`),
  never typed into a script, and re-resolved on `locale_changed`;
- `billboard` on, depth test on, `fixed_size` off, so it faces the camera and is
  occluded by geometry rather than drawn through walls;
- no collision, area or body: it cannot be walked into, cannot block the mouse ray and
  cannot widen an interaction radius. `tests/nameplate_test.gd` asserts the subtree
  contains no physics nodes;
- it is a child of the actor, so it follows the actor, disappears when the actor is
  hidden, and cannot be left behind or duplicated by a scene change;
- `ui/nameplates/show_development_nameplates` overrides visibility; with no override
  the labels follow `OS.is_debug_build()` — on while developing, off in a release
  export;
- a character who is not in a scene gets no label; B is not in the start scene and no
  actor was created to hold one.

## 5h. Entering a location: pre-flight, then commit (implemented contract)

A location change is the one operation that can destroy the room the player is standing
in, so `LocationHost.load_location(scene_path, spawn_id, player, expected_location_id)`
is written as a transaction and `tests/location_transition_test.gd` holds it to that.

**Stage 1 — pre-flight, while nothing outside the function changes.** In order: the path
is non-empty; `ResourceLoader.exists()`; the resource loads as a `PackedScene`; it
instantiates; the root uses the `LocationRoot` script; `location_id` is not empty; when
the caller passed `expected_location_id` (an exit's `destination_id`), it equals the
id the scene declares; the player exists and can be placed; the requested spawn marker
exists. Any failure returns false with an error naming the scene, the location id, the
requested spawn and the markers the scene does have — and the instance is freed right
there, so nothing is left for a later frame to clean up.

**Stage 2 — commit.** Only now is the new scene added, the player teleported onto the
marker, `_current`/`_current_path` replaced, the old scene removed and freed, and
`location_entered` emitted. The player's arrival is *checked* (`PLACEMENT_TOLERANCE`
0.05 m); a body that refused the transform rolls the whole commit back: the new scene
leaves the tree and is freed, the old scene stays current, and the call returns false.

**Spawn ids.** An empty `spawn_id` means "the location's default": the first
`spawn_point` marker in tree order, which is how the classroom opens. A **named** id
must match a marker exactly. There is no fallback — `LocationRoot.get_spawn()` returns
`null` and reports the id, the location_id, the scene path and the available markers.
A typo therefore fails the transition instead of quietly putting the player somewhere
else (issue #19).

**What a failure leaves behind.** The old scene remains loaded and current,
`_current_path` is unchanged, the player keeps their position and facing,
`CURRENT_LOCATION` still describes the room they are in, `location_entered` is not
emitted, and the return value is false. `LocationFlow._transition_to()` fades back in
and hands control back; nothing downstream (Q's placement, the objective line, the
arrival beat) runs off a transition that did not happen.

**What a transition costs, and how it is known.** `LocationHost` times its own
transaction in debug builds and keeps the last 16 transitions in `transition_history`:
resource load, instantiation, entering the tree (which is where the deferred bake runs),
placing the player, committing the swap, the total, the node count of the room that was
entered, and how many location scenes were alive at the swap — two is correct while the
swap is in flight, more than two is a leak. The timing wraps the transaction instead of
living inside it, so a *failed* transition is measured too, and a rollback still leaves the
old room current. Release builds print nothing. `tests/location_pressure_test.gd` enters all
six locations, asserts the numbers are real, and asserts that three round trips leave the
node count and the orphan count where they started.

**The story flag follows the verified scene.** `CURRENT_LOCATION` is written from the id
of the location that was actually entered — after it was checked against the exit's
claim — not from the exit's `destination_id` on its own. The exit and the scene can no
longer disagree about which room the player is in.

**Spawn markers carry position, not heading.** Every marker that ships is position-only,
so arrival keeps the heading the player already had; the mechanism is real (a marker
with a rotation does set the arrival facing, and the test pins that on a fixture), and
authoring a rotation on a marker is what changes it. Which marker an exit names is
checked by the test above: the marker must exist, must be the one the player lands on,
must be walkable ground, and for a return trip must sit by the exit that leads back.

## 5i. Editing text: the narrative editor (editor only, implemented contract)

Writing one line in two languages by hand means opening two files, finding the same node
twice and hoping the structures still match. `addons/narrative_editor/` is a Godot
EditorPlugin that does it in one place, and this section is about the boundary rather than
the buttons.

**It is a tool, not a feature.** The plugin is registered in `project.godot` under
`[editor_plugins]`, and that is the only way it is ever loaded. There is no autoload, no
`class_name`, no preload from `scripts/`, `scenes/` or `tests/`, and `export_presets.cfg`
excludes `addons/*` while `tools/verify_build.py` fails the release check if anything under
`res://addons/` is packed. A player's build therefore cannot contain it, and no runtime
behaviour can depend on it.

**Text is the only thing it can write.** `core/narrative_store.gd` exposes a setter per
text field — dialogue node text, choice text, six inspection fields, an inner voice's name
and description — and no setter for anything else. The dock can only ask for the fields the
store built, and the store refuses an address that is not one of those even when called
directly, so node ids, speakers, branches, conditions, effects, checks, `once` flags and
ability numbers are read-only twice over.

**A save is staged, checked and minimal.** Edits are recorded as spans inside the original
text (`core/narrative_json_text.gd`), so a save rewrites the strings that changed and
nothing else: key order, indentation, unknown fields and the trailing newline survive, and
the diff is the line the author edited. Before anything is written, both languages are
re-parsed, compared structurally (`core/narrative_parity.gd` — ids, order, branches,
effects, conditions, checks, `once`, speakers must match; only player-visible text may
differ), checked against the field rules, and run through the loader the game itself uses
(`DialogueGraph`, or `InnerAbilities` on a temporary registry). Then
`core/narrative_file_writer.gd` writes both files to temporary siblings, moves the current
ones aside, moves the new ones in and only then deletes the backups. A failure restores the
language that was already written, names the file that refused, and reports a failed save;
there is no state where one language is saved and the tool says it worked.

**The chapter list is the directory.** `core/narrative_paths.gd` reads the chapter files
instead of keeping a second copy of `DialogueLibrary.CHAPTERS` /
`InspectionLibrary.CHAPTERS`; those constants are then cross-checked against the tree and a
disagreement is reported in the dock, because the runtime iterates the constants and a
chapter that only exists on disk would never load.

**What holds it.** `tests/narrative_editor_test.gd` drives the real data layer against a
`user://` copy of the shipped chapters: load, locate, edit, save, fail to save, and rewrite
every content file byte for byte. The dock itself is a `Control` that needs a window, so its
evidence is `tests/capture_editor_dock.gd`, which photographs it under Xvfb in CI. The
editor-only surface — the plugin class, the bottom panel — is covered by the manual
checklist in that test's section of the pull request, because no CI runner opens an editor.

## 5j. The ground mark and the outline (implemented contract)

This round replaced both pointer cues after the owner rejected them: the floor-click mark
read as a scribble, and the object cue was a large ring on the floor next to the object
rather than the object itself. The owner's reference was Disco Elysium's highlighting.

**The ground mark: a ring and a dot.** `DestinationCue`
(`scripts/interaction/destination_cue.gd`) has three parts, `Ring`, `Dot` and `Echo`
(`get_parts()`), built by `WorldCue.destination_ring_mesh()`, `destination_dot_mesh()` and
`destination_echo_mesh()`: a ring of radius `MARK_RADIUS` 0.15 m drawn with a 0.022 m pen
(`MARK_RING_WIDTH`), a 0.024 m dot (`MARK_DOT_RADIUS`), and a 0.012 m echo ring. The footprint
is about 0.32 m across (`mark_footprint_radius()` reads it back from the mesh), and
`tests/interaction_cue_test.gd` fails it outside 0.12-0.2 m radius or above 0.035 m2 of ink.

**It lands, echoes once, and holds.** The ring arrives at 1.9x and contracts onto its radius
in 0.2 s (`LAND_SECONDS`, `LAND_SCALE_FROM`), the dot pops in 0.06 s later, and one echo
leaves from where the ring landed, growing to 2.6x while it fades over 0.5 s. After that
nothing moves until the walk ends or another click replaces it. Dismissal is a 0.14 s fade.

**The three roles survive, and so do their sounds.** `show_destination()`,
`show_target()` and `show_refused()` set `get_role()` to `destination`, `target` or
`refused`; each role keeps its colour (bone / amber / rose), and `PointerNavigator` plays the
matching `CueAudio` kind from the same call that draws it. A refusal draws the ring only, no
dot and no echo, contracting to 0.4x while it fades over 0.32 s, and ends itself.

**It lies on the ground.** The floor hit supplies the normal; `WorldCue.ground_basis()`
builds the basis and the mark is offset 0.02 m along it. A click on an object is marked at
the approach spot on the floor, and a refused click on a wall at the floor under the point
that was clicked (`PointerNavigator._ground_point_under`), never at the anchor's height.

**The outline.** See section 5f: `HoverCue` traces the meshes `Interactable.outline_paths`
names through `OutlineOverlay`, and the same meshes give the interactable its pick boxes.
`outline_paths` is authored per object: in `tools/build_outdoor_locations.py` as the
`"outline"` key of each interactable for the four generated outdoor locations, and by hand in
`classroom.tscn`, `corridor.tscn` and `companion.tscn` (the companion's `AskAlong` traces
`../Actor`). The outline traces the object, not its support: a notice pinned to a wall traces
the sheet, and the wall stays in `support_paths` for the line-of-sight probe only.

**Exits look like ways out.** The way up to the flats from the street ("go on to the
flats") is a flight of twelve steps with a rail to a landing and a lit doorway into a short
passage; the courtyard's stair up ("look up the stairs") is fourteen steps with a rail to a
landing, a door and a lamp over it; the courtyard's way back to the street is a gate (posts,
lintel, sign) over thirteen steps cut down into the ground under the west block, between a
retaining wall and a balustrade; the courtyard's lane end is an arch with a lit recess behind it, and the
schoolyard's way back to the alley is a gate with posts, a lintel and a lamp. The schoolyard's
gate pieces draw only (no collision), because `tests/playground_art_slice_test.gd` pins the
yard's solids and its baked navigation.

**What the navigation bake counts as floor: thin boxes only.** `LocationNavigation._add_shape`
hands Recast each collision box's faces wound so that the box's *underside* is the face that
points up; the top points down. A box therefore bakes as floor only when it is thinner than one
climb voxel (0.25 m), so that its top and bottom fall in the same span and merge: the road,
pavements, kerbs and slab floors. A solid box (a step, a 1.6 m landing, a passage floor on a
plinth) is never floor. This was found by reproducing the bake outside Godot with the same
Recast settings: the flipped winding reproduces CI's mesh bounds and its closest point at the
head of the street stair exactly; the correct winding bakes the landing (and building roofs).
Changing the winding would change what every room bakes (roofs, tables and walls become
islands, and `tests/playground_art_slice_test.gd` pins the yard's polygons), so it is left as
a proposed follow-up, not done here. Instead the generator gives every walked-on solid box a
thin invisible slab at its top (`_tread`: the street's landing and passage, the courtyard
stair's landing) and every flight a thin invisible slope (`_ramp`: through the front edge of
each tread, ending level with the landing). The body stands on the boxes as before; only the
bake sees the slabs. The flights are kept gentle (12.3 cm and 12 cm risers) so the body walks
the slope without bumping the nosings.

## 5k. The window: size, centring and F11 (implemented contract)

`scripts/ui/display_mode.gd`, as the `DisplayMode` node in `scenes/main/main.tscn`. It
lives in the main scene, so it survives every location swap, and it does nothing else.

- **1600×900 is the design size** — the viewport the interface is composed and measured at
  (`project.godot` `[display]`, no smaller override), and the size the window opens at when
  the screen can hold it. The window is **resizable**, with a **1280×720 minimum**: that is
  the smallest size `tests/dialogue_layout_test.gd` and `tests/hud_layout_test.gd` verify the
  interface at, so it is the smallest size the window may be dragged to.
- **Centred, never off-screen.** `centred_rect()` clamps the requested size to the current
  screen's usable area and centres what is left. It is public because the tests check the
  arithmetic at several screen sizes rather than trusting the one laptop it was written on.
- **F11 toggles fullscreen** (`toggle_fullscreen` action, physical keycode 4194342). The
  windowed rectangle is remembered on the way in and restored on the way out, clamped back
  into the usable area because the display may have changed while the game was fullscreen. A
  second toggle inside 150 ms is ignored: a held key repeats, and a mode change costs a
  frame. `is_fullscreen()` reports the state the node believes; `is_window_fullscreen()`
  asks the display, because the OS shortcut exists too.
- **It touches nothing else.** No scene is reloaded, no autoload is reset, the player does
  not move and the dialogue is not interrupted. `tests/display_mode_test.gd` presses F11
  mid-game and asserts exactly that: same location, same player position, same flags, same
  child count.
- **Headless is a real state.** Under `--headless` (every CI test) `DisplayServer` is a stub,
  so the node still runs its state machine and the tests exercise the remembering and
  restoring without a window; it simply never calls `DisplayServer` there.

## 5l. Start-up text loading: what happens now, and what is only planned

The game loads **every chapter of every language** at start-up, twice: once through
`DialogueLibrary.load_all()` (all seven dialogue chapters × every locale), and once through
`InspectionLibrary.load_all()` (all six inspection chapters × every locale). `L10n` also
loads its table for every language. This is the implemented behaviour, and it is deliberate:
parity between languages is checked at load, so a translator cannot drop a branch and have
it discovered only when a player switches language mid-scene.

What the round added is the **measurement** of that cost, not a change to it:

- `DialogueLibrary` and `InspectionLibrary` each keep a `load_report` — total microseconds,
  per-chapter JSON bytes, conversation/node/inspectable counts and per-chapter parse time,
  per language — filled once inside `load_all()` and printed in debug builds only.
- `DialogueController` prints one line for the whole corpus.
- `tests/content_load_report_test.gd` cross-checks that report against the libraries
  themselves (the counts must match `get_conversation_ids()` and `get_ids_for()`), so the
  numbers cannot drift from the content they describe.

**Not implemented, and not to be described as if it were:** lazy or per-locale loading,
caching between runs, streaming chapters, or an async loader. The roadmap
(`docs/TECHNICAL_ROADMAP.md`, Phase 5b.3) records the intended shape — load the active
locale's chapters first, then the other language behind the first frame, keeping CI's
all-languages/all-chapters validation — together with the constraint that CI must keep
validating every language and every chapter however the runtime loads them.

## 5m. The background music (implemented contract)

One recorded guitar take, one player, one bus. The recording is the owner's own: a solo
fingerpicked improvisation, 46.738 s, mono, 48 kHz, 16-bit, peak −8.7 dBFS, no clipping and
no DC offset. It is not a sample library and not a stock track, and it is not synthesised
like the room tones and the cues — it is a performance, and the pipeline is built to leave
it alone.

**The source is kept, and kept out of the build.** The recording as delivered lives at
`art/audio/Guitar_loop_01.wav`, byte-identical (`art/audio/.gdignore` keeps the engine from
importing it, and the export preset excludes `art/`). The game ships a derived file,
`assets/audio/music/guitar_ambient_loop_01.wav`, and nothing in `assets/` is the only copy
of the music.

**The loop is made by a script, not by hand.** `tools/build_music_loop.py` drops the
0.396 s of room noise the take opens with, keeping the 0.30 s nearest the first note inside
the loop; keeps the 0.07 s the take has after its last note rather than padding silence onto
the end; and crossfades the tail into the material immediately before the loop start, so the
last sample of the file continues into its first the way the take did one loop earlier. The
seam measures −72 dBFS, i.e. eight 16-bit LSB, rather than a click.
`python3 tools/build_music_loop.py --check` runs in CI and fails if the committed WAV drifts
from a fresh build, exactly as the sample models do. No normalisation, limiting, EQ, reverb
or noise reduction is applied: the take's own dynamics and room are the point, and
"improving" them would be a second authorship of someone else's performance.

**Looping is an import setting.** The sidecar
`assets/audio/music/guitar_ambient_loop_01.wav.import` carries `edit/loop_mode=2`,
`edit/loop_begin=0` and `edit/loop_end=2224446`, so the stream that loads in the game *is*
a loop. Nothing duplicates the stream and sets `loop_mode` at runtime — that pattern exists
in `scripts/world/ambience_player.gd` for the generated room tones, and it is deliberately
not copied here. `tests/music_test.gd` reads the sidecar and asserts the loaded stream
carries the points, so a lost import setting fails a test instead of producing music that
stops after 46 seconds in someone's playthrough.

**The player is an autoload, and it is the only one.** `Music`
(`scripts/autoload/music_player.gd`) creates a single `AudioStreamPlayer` in `_ready()`,
starts the track with a 3 s fade-in, and survives scene changes because autoloads outlive
`change_scene_*()`. `play_track()` returns `false` when the requested track is already
playing, so a scene that calls it on entry cannot restart the music, and there is no second
player to overlap with. `stop()` fades out; `stop(true)` cuts.

**It cannot drown the game and cannot be turned down by accident.** The player sits on a
`Music` bus defined in `default_bus_layout.tres` (trimmed −6 dB), and the player's own
`volume_db` starts at −12 dB, so the music sits about 18 dB below the recording's −8.7 dBFS
peak — under the room tone's own peak. Every other sound (`CueAudio`'s cues, the ambience
beds, dialogue blips) is on `Master`, so `Music.set_volume_db()` moves the guitar and
changes nothing else. `tests/music_test.gd` asserts both halves of that: the cue volumes do
not move, and the cue players are not on the music bus.

**What it does not do yet.** There is no playlist, no per-room music, and no ducking during
dialogue — the game's dialogue is text, there is no voice track to talk over, and a ducking
path with nothing to duck for would be untested machinery. There is also no settings screen;
`set_volume_db()` is the dial such a screen would call. Music does not pause with the tree
(`process_mode = ALWAYS`), because a silent pause is a decision nobody has made yet.

`tests/music_test.gd` covers the import settings, the stream's format and length, the single
player, the scene change, the independent dial, and that seeking past the loop end wraps
instead of stopping. It cannot hear the result: whether the loop is seamless to an ear, and
whether −18 dB is the right level in a real room, are reviews for the owner.

## 6. Persistent identifiers and data

- Use stable IDs for dialogue nodes, characters, items, locations, and story flags.
- Treat IDs as save-data contracts; rename them only with an explicit migration plan.
- Do not use display names as identifiers.
- Validate external content at load time and report the file path and invalid field.
- Keep presentation text out of movement and world simulation scripts.
- Prefer typed Godot Resources for structured authoring; use JSON only where it materially improves localization, external editing, or automated validation. (Dialogue and inspection text use JSON for exactly that reason; see section 5b.)

## 7. Save/load (implemented, ADR 0005)

One versioned file, `user://save.json`, written by the `Save` autoload
(`scripts/autoload/save_manager.gd`) and encoded by `SaveCodec`
(`scripts/save/save_codec.gd`). It contains:

- the story flag table, with each value's type (`int` stays an `int`; JSON would
  have made every counter a float);
- the narrative knowledge log, whose entries are re-validated on the way in by the
  same rules `record()` uses — an unknown source is rejected, never downgraded to
  `observed`;
- the session's dice seed, so a check re-entered after a load shows the same faces;
- the current location, the spawn marker it was entered through, and the player's
  position and facing.

Saves are taken at **beat boundaries** — after a prologue step, after a location is
entered, when the slice ends — because that is when nothing is mid-flight. Validation
runs before anything is applied, so a refused file leaves the session untouched; the
file is copied to `user://save.broken.json` and the player is told on the end card.
The game resumes at boot when a readable save exists, because the build has no menu
(ADR 0005 §7 records when to revisit that). Migrations are registered per version
step and a newer-versioned file is refused with a message rather than guessed at.

## 7b. Build contents: baseline, budgets and what must not ship

The release build is read back out of the pack by `tools/verify_build.py`; the numbers
below are from that tool, and the per-category policy is written in
[ASSET_PIPELINE.md](ASSET_PIPELINE.md) §9.

- **Baseline (the release this round was measured against):** 256 files, **1.37 MiB
  packed**, largest entries the subset font (252 KiB), the playground bench mesh (206 KiB)
  and the student backpack mesh (134 KiB).
- **Budgets are per kind of file** — model, font, texture, audio, scene, text, other — each
  with a warning line and a hard limit. No category's hard limit is above the 2 MiB ceiling
  every single file already had, so the table only tightens the rule. The pack total keeps
  its 16 MiB hard limit and adds an 8 MiB warning line.
- **Excluded from the build, and checked as excluded:** `docs/` (documents and captured
  screenshots), `tests/` (the test suite and its capture scripts), `tools/` (build and
  content scripts), `art/` (the editable `.blend` sources), `addons/` (the narrative editor
  plugin) and `.github/`. The `.blend` files are additionally excluded from Godot's own
  resource filesystem by `art/props/.gdignore`.

## 8. Testing boundaries

- Unit tests: pure state transformations, dialogue condition evaluation, content validation, save serialization/migration, dice maths and seeds.
- Negative fixtures: a validator that has never rejected anything proves nothing, so the content and check tests feed it deliberately broken input and assert the rejection.
- Scene smoke tests: required nodes/resources instantiate and scenes load.
- Integration tests: movement/interaction/dialogue/scene-state transitions.
- Manual tests: navigation readability, pacing, camera comfort, typography, controller feel, and spatial surprises.

A successful headless import is not proof that the game is playable. PRs must say which level of validation they actually performed.
