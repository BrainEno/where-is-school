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

The project contains two autoloads.

- **GameState** — runtime story flags and snapshot/restore of those flags. It is
  not a dumping ground for quests, dialogue UI, scene transitions, audio,
  inventory, settings, or save-file I/O.
- **NarrativeState** — append-only narrative knowledge entries, each tagged
  observed / reported / recalled / imagined, de-duplicated by id, with
  snapshot/restore. It exists because knowledge categories are used by dialogue,
  inspection, and presentation independently of gameplay flags; see
  `docs/adr/0002-dialogue-and-narrative-state.md`.

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
- The player scene owns its controller and local camera rig. A later camera system may extract the rig if multiple actor modes require it.
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
3. everything else is refused: the cue collapses inward in the refusal colour and the
   character stays where they are. No walk, no dialogue, nothing to dismiss.

**The cues the mouse draws** (`scripts/interaction/world_cue.gd`,
`hover_cue.gd`, `destination_cue.gd`). Three decisions hold them together:

- **One palette, one pen.** `WorldCue` owns the colours (bone = where you clicked, amber =
  the thing you clicked or can use, a duller rose = refused), the stroke width, the dash
  rhythm and one cached unshaded alpha-only material per role. A cue is a mark, not a
  light: unshaded, no depth write, back faces drawn, so it reads on any surface without
  being lit by the room or punching a hole in what is behind it. Every mesh is built in
  code (`SurfaceTool`), so no prop, scene or camera distance needs new art.
- **Motion is the interface.** The destination ripple expands once and fades; the ring
  left behind turns and breathes while the character walks; the hover cue's ground ring
  spins, its halo breathes out of step, and its shard bobs and tumbles; both cues fade in
  and out over ~0.15 s instead of switching between frames. The motion is slow on purpose
  (a full turn in about forty seconds) so a cue never competes with the character or the
  reading band. The refused cue is the exception that proves the rule: it *collapses*,
  because an expanding ring is a promise of a walk.
- **The cue is laid on the world, not on a plane.** The navigator passes the ground normal
  under the click (one short ray, only on a click) and the cue's basis puts its +Y on that
  normal, so a kerb, a ramp or a tilted floor plate gets a ring that lies flat on it. The
  hover cue's ground ring is projected the same way, downwards: an interactable is authored
  at the middle of its prop, so `Interactable` casts one ray to find the floor under it and
  draws the ring there rather than at the sheet's own height.
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
`tests/interaction_cue_test.gd` — the two cues as objects rather than as pixels: the parts
they claim to have, that they are animated, that a role decides the colour, that the ring
is laid on the ground normal it was given, that a refusal collapses and ends itself, that a
cue hides when it is finished, and that the hover ring follows the interaction radius.

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
emitted, and the return value is false. `OpeningSequence._transition_to()` fades back in
and hands control back; nothing downstream (Q's placement, the objective line, the
arrival beat) runs off a transition that did not happen.

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

## 6. Persistent identifiers and data

- Use stable IDs for dialogue nodes, characters, items, locations, and story flags.
- Treat IDs as save-data contracts; rename them only with an explicit migration plan.
- Do not use display names as identifiers.
- Validate external content at load time and report the file path and invalid field.
- Keep presentation text out of movement and world simulation scripts.
- Prefer typed Godot Resources for structured authoring; use JSON only where it materially improves localization, external editing, or automated validation. (Dialogue and inspection text use JSON for exactly that reason; see section 5b.)

## 7. Save/load design (future requirement)

When implemented, saves should contain a schema version and explicit snapshots for:
- current location and safe spawn identifier;
- story/world flags;
- journal discoveries;
- player progression and inventory, if later approved;
- relevant dialogue state only if the design requires mid-dialogue continuation.

Use user:// paths. Write to a temporary file, validate the result, then replace the prior save. Implement migrations before changing a released schema. Never save absolute machine paths or arbitrary Node references.

## 8. Testing boundaries

- Unit tests: pure state transformations, dialogue condition evaluation, content validation, save serialization/migration, dice maths and seeds.
- Negative fixtures: a validator that has never rejected anything proves nothing, so the content and check tests feed it deliberately broken input and assert the rejection.
- Scene smoke tests: required nodes/resources instantiate and scenes load.
- Integration tests: movement/interaction/dialogue/scene-state transitions.
- Manual tests: navigation readability, pacing, camera comfort, typography, controller feel, and spatial surprises.

A successful headless import is not proof that the game is playable. PRs must say which level of validation they actually performed.
