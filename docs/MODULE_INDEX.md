# Public module index — search before implementing

This is a discovery map, not a second architecture or a promise that every Node is a
standalone utility. Read [AGENTS.md](../AGENTS.md) and the mandatory
[agent protocol](AGENT_PROTOCOL.md) first. Follow the source **and existing callers/tests**
before extending a module. Preserve its current owner and lifecycle instead of building
another controller, cache, state store or palette beside it.

## Find the existing owner

| If the task concerns… | Start here | Relevant checks / contracts |
|---|---|---|
| Menu colors, font, buttons, text size | `MenuStyle`, `UiTextScale` | [title/menu](../tests/title_menu_interaction_test.gd), [settings](../tests/settings_regression_test.gd) |
| Key/controller/mouse labels, language | `InputHint`, `L10n`, `Settings`, `Loc` | [input device](../tests/input_device_test.gd), [locale switching](../tests/language_switch_test.gd) |
| Headless setup, timeout, result collection | preload-only `TestHarness` below | [smoke](../tests/smoke_test.gd), [CI verdict helper](../tools/ci_run_check.sh) |
| Dialogue loading, traversal, auto/skip, read state | `DialogueLibrary`, `DialogueRuntime`, `DialoguePlayback`, `ReadLog` | [runtime](../tests/dialogue_runtime_test.gd), [playback](../tests/dialogue_playback_test.gd), [data schema](../data/dialogue_schema/README.md) |
| Knowledge, notebook or dice | `NarrativeEntry`, `JournalCatalog`, `JournalPage`, `CheckResolver` | [journal](../tests/journal_test.gd), [dice](../tests/check_resolver_test.gd) |
| Click-to-move, targeting, highlight or refusal | `PointerNavigator`, `InteractionController`, `WorldCue`, `OutlineOverlay` | [navigation](../tests/navigation_test.gd), [automatic activation](../tests/automatic_interaction_test.gd), [cue lifetime](../tests/destination_cue_lifecycle_test.gd) |
| Location swaps, Q following, opening/resume | `LocationHost`, `LocationFlow`, `CompanionController`, `OpeningSequence` | [transitions](../tests/location_transition_test.gd), [companion](../tests/companion_route_test.gd), [resume](../tests/opening_resume_test.gd) |
| Camera follow, occlusion or interaction focus | `CameraRig`, `CameraOccluderFader`, `CameraShot`, `CameraFocusDirector` | [camera](../tests/camera_rig_test.gd), [prologue art](../tests/prologue_art_test.gd) |
| Character appearance or movement | `CharacterLook`, `CharacterLookApplier`, `CharacterAnimation`, `CharacterVisualAnimation` | [character art](CHARACTER_ART.md), [integration](CHARACTER_INTEGRATION.md), [animation](CHARACTER_ANIMATION.md), [animation test](../tests/character_animation_test.gd) |
| Asset imports, rights or model registration | Existing preparation/generator and verifier tools below | [provenance](ASSET_PROVENANCE.md), [pipeline](ASSET_PIPELINE.md), [model catalog](MODEL_LIBRARY.md) |
| Saves, new game, settings or music | Existing autoloads below; `SaveCodec` for typed values | [save validation](../tests/save_validation_test.gd), [new-game failure](../tests/new_game_failure_ui_test.gd), [music](../tests/music_test.gd) |

Search names **and behavior synonyms**, then inspect usages, not only declarations:

```sh
git grep -n -E 'MenuStyle|UiTextScale|TestHarness' -- scripts scenes tests tools addons
git grep -n -E 'font_size|text_scale|arm_watchdog|ensure_state_autoloads' -- scripts tests
python3 tools/check_agent_docs.py --list
```

Record the actual keywords/commands, useful hits and reuse/non-reuse reason in the PR
[**已检索** subsection](../.github/pull_request_template.md). An empty search does not prove
that the behavior is absent; check adjacent owners and tests first.

## Globally named GDScript types

Every tracked top-level `class_name`, including scene-local types, must have exactly one
row between the markers below. Nodes/resources are indexed for discoverability, not
permission to add duplicate instances or new autoloads. Source links are relative to this
file; descriptions state the responsibility/boundary rather than copying APIs that drift.

<!-- class-name-index:start -->

### UI presentation and shared style

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `BacklogPanel` | [`scripts/ui/backlog_panel.gd`](../scripts/ui/backlog_panel.gd) | Render identity-based dialogue history and reword it on locale changes; no story-state ownership. |
| `CheckOverlay` | [`scripts/ui/check_overlay.gd`](../scripts/ui/check_overlay.gd) | Present visible dice checks; calculation remains in CheckResolver. |
| `ConfirmPrompt` | [`scripts/ui/confirm_prompt.gd`](../scripts/ui/confirm_prompt.gd) | Shared cancel-first confirmation surface for destructive actions. |
| `DialogueModeBar` | [`scripts/ui/dialogue_mode_bar.gd`](../scripts/ui/dialogue_mode_bar.gd) | Mouse-accessible auto/skip controls in the dialogue hint line; preserve the reading-band layout contract. |
| `DialoguePanel` | [`scripts/ui/dialogue_panel.gd`](../scripts/ui/dialogue_panel.gd) | Render speakers, text, portraits, choices, typing and layout; it does not walk the content graph. |
| `EndCard` | [`scripts/ui/end_card.gd`](../scripts/ui/end_card.gd) | Present the slice boundary and restart/title actions; delegate lifecycle changes to Session. |
| `FadeLayer` | [`scripts/ui/fade_layer.gd`](../scripts/ui/fade_layer.gd) | Presentation-only full-screen fades for beats and location transitions. |
| `GameHud` | [`scripts/ui/hud.gd`](../scripts/ui/hud.gd) | Localized objective, interaction hint and notebook notices; thin presentation of director-owned state. |
| `GameUI` | [`scripts/ui/game_ui.gd`](../scripts/ui/game_ui.gd) | Typed access to the persistent HUD, dialogue, backlog, fades and overlays. |
| `ImaginationOverlay` | [`scripts/ui/imagination_overlay.gd`](../scripts/ui/imagination_overlay.gd) | Mark subjective beats visibly as imagined, not observed world events. |
| `InputHint` | [`scripts/ui/input_hint.gd`](../scripts/ui/input_hint.gd) | Localized action labels from the active device and live bindings; do not hard-code key names in another UI. |
| `JournalPanel` | [`scripts/ui/journal_panel.gd`](../scripts/ui/journal_panel.gd) | Render the notebook from existing knowledge, routes and reading progress; do not create a second knowledge store. |
| `Palette` | [`scripts/theme/palette.gd`](../scripts/theme/palette.gd) | The project's colours as names: ink, paper, bone, ember, sheet, and the four source colours. A leaf module (imports nothing) so the dialogue and actor layers can name a colour without importing the interface; `tools/check_ui_palette.py` fails one value written in two files, and fails this file if it ever loads anything. |
| `MenuStyle` | [`scripts/ui/menu_style.gd`](../scripts/ui/menu_style.gd) | Menu type, entry buttons, labels, page/form styling and control factories; it re-exports `Palette`'s names, so `MenuStyle.INK` and `Palette.INK` are one value. Do not add a colour here - add it to `Palette`. |
| `NewGameFailureText` | [`scripts/ui/new_game_failure_text.gd`](../scripts/ui/new_game_failure_text.gd) | Turn a Session failure report into localized player-facing text; keep technical details in the log. |
| `NotebookPaper` | [`scripts/ui/notebook_paper.gd`](../scripts/ui/notebook_paper.gd) | Draw the dialogue band's torn notebook sheet, rules, red margin and set-square wedge; never takes input; DialoguePanel sizes it and aligns its rules. |
| `PauseMenu` | [`scripts/ui/pause_menu.gd`](../scripts/ui/pause_menu.gd) | In-game pause, notebook, settings and save/quit UI; Session owns the transactions. |
| `SettingsPanel` | [`scripts/ui/settings_panel.gd`](../scripts/ui/settings_panel.gd) | Shared settings and binding editor; Settings applies and persists changes. |
| `TitleScreen` | [`scripts/ui/title_screen.gd`](../scripts/ui/title_screen.gd) | Start/continue/settings/quit surface and save status; use Session for a new run. |
| `UiTextScale` | [`scripts/ui/ui_text_scale.gd`](../scripts/ui/ui_text_scale.gd) | Apply the Settings text multiplier from an authored base size (`apply`, `set_base`, `scaled`); repeated scaling must not compound. |

### Dialogue and reading

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `CharacterDirectory` | [`scripts/dialogue/character_directory.gd`](../scripts/dialogue/character_directory.gd) | Resolve ordinary and inner-voice speaker profiles from resources and the ability registry. |
| `ConversationRouter` | [`scripts/dialogue/conversation_router.gd`](../scripts/dialogue/conversation_router.gd) | Ordered, declarative story-flag lookup for NPC conversation selection. |
| `DialogueController` | [`scripts/dialogue/dialogue_controller.gd`](../scripts/dialogue/dialogue_controller.gd) | Load content, drive runtime events and coordinate dialogue/inspection presentation and history. |
| `DialogueGraph` | [`scripts/dialogue/dialogue_graph.gd`](../scripts/dialogue/dialogue_graph.gd) | Strict parsing and validation of one chapter in one language, including runtime-reachable edges. |
| `DialogueHistory` | [`scripts/dialogue/dialogue_history.gd`](../scripts/dialogue/dialogue_history.gd) | Session history keyed by stable content identity; locale re-rendering must not append duplicates. |
| `DialogueLibrary` | [`scripts/dialogue/dialogue_library.gd`](../scripts/dialogue/dialogue_library.gd) | Load all chapters/locales and resolve conversations; reuse its validation and parity checks. |
| `DialogueParity` | [`scripts/dialogue/dialogue_parity.gd`](../scripts/dialogue/dialogue_parity.gd) | Compare bilingual content structure, branches, choices and effects while allowing translated text. |
| `DialoguePlayback` | [`scripts/dialogue/dialogue_playback.gd`](../scripts/dialogue/dialogue_playback.gd) | Pure auto/skip/manual pacing decisions; controller owns input and performs the returned action. |
| `DialogueRuntime` | [`scripts/dialogue/dialogue_runtime.gd`](../scripts/dialogue/dialogue_runtime.gd) | UI-independent graph walker with explicit story/knowledge references and subjective-world restrictions. |
| `ReadLog` | [`scripts/dialogue/read_log.gd`](../scripts/dialogue/read_log.gd) | Cross-run read lines and taken choices; distinct from this session's DialogueHistory. |
| `ReadingProgress` | [`scripts/dialogue/reading_progress.gd`](../scripts/dialogue/reading_progress.gd) | Compute the shared reading-progress denominator and totals from loaded content and ReadLog. |

### Narrative content and notebook data

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `CharacterProfile` | [`scripts/narrative/character_profile.gd`](../scripts/narrative/character_profile.gd) | Speaker display/portrait resource; narrative text stays in content files. |
| `InspectionLibrary` | [`scripts/narrative/inspection_library.gd`](../scripts/narrative/inspection_library.gd) | Load and validate localized inspectable-object content, records and first-read effects. |
| `JournalCatalog` | [`scripts/narrative/journal_catalog.gd`](../scripts/narrative/journal_catalog.gd) | Resolve knowledge-entry identities back to content in the current locale. |
| `JournalPage` | [`scripts/narrative/journal_page.gd`](../scripts/narrative/journal_page.gd) | Pure grouping/filtering of knowledge entries into notebook presentation dictionaries. |
| `JournalRoute` | [`scripts/narrative/journal_route.gd`](../scripts/narrative/journal_route.gd) | Derive visited places from catalog arrival flags already stored by GameState. |
| `NarrativeEntry` | [`scripts/narrative/narrative_entry.gd`](../scripts/narrative/narrative_entry.gd) | Observed/reported/recalled/imagined knowledge model; never silently convert one source into another. |
| `StoryFlags` | [`scripts/narrative/story_flags.gd`](../scripts/narrative/story_flags.gd) | Stable named flag constants and value contracts; renaming requires a save-migration plan. |

### Inner abilities and dice

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `CheckResolver` | [`scripts/rpg/check_resolver.gd`](../scripts/rpg/check_resolver.gd) | The single seeded dice/math core for visible and hidden checks; no UI or content ownership. |
| `InnerAbilities` | [`scripts/rpg/inner_abilities.gd`](../scripts/rpg/inner_abilities.gd) | Load and validate the data-driven inner-voice registry, values and passive rules. |

### Localization

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `Locales` | [`scripts/i18n/locales.gd`](../scripts/i18n/locales.gd) | Supported locale profiles, aliases and reading speeds; add language metadata here. |
| `L10n` | [`scripts/i18n/l10n.gd`](../scripts/i18n/l10n.gd) | Static interface-string lookup and locale tables; use Loc for persistent locale choice and change notifications. |

### Save encoding

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `SaveCodec` | [`scripts/save/save_codec.gd`](../scripts/save/save_codec.gd) | Typed JSON envelope/value encoding and strict decoding; Save owns payload selection and file I/O. |
| `SettingsStore` | [`scripts/save/settings_store.gd`](../scripts/save/settings_store.gd) | The preferences file and its keys (`user://settings.cfg`, `[display] locale`); Loc and Settings both read and write through it instead of keeping their own copy of the path. |

### Interaction and world cues

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `DestinationCue` | [`scripts/interaction/destination_cue.gd`](../scripts/interaction/destination_cue.gd) | Own the lifetime and gesture of the click destination/refusal mark; use WorldCue for its visual primitives. |
| `HoverCue` | [`scripts/interaction/hover_cue.gd`](../scripts/interaction/hover_cue.gd) | Present the currently usable object through OutlineOverlay; do not draw a second ground highlight. |
| `Interactable` | [`scripts/interaction/interactable.gd`](../scripts/interaction/interactable.gd) | Authored activation contract and outline meshes; emits requests, never opens UI or loads rooms itself. |
| `InteractionController` | [`scripts/interaction/interaction_controller.gd`](../scripts/interaction/interaction_controller.gd) | Sole owner of the highlighted target and E activation, reconciling pointer and facing selection. |
| `LocationExit` | [`scripts/interaction/location_exit.gd`](../scripts/interaction/location_exit.gd) | Declare destination scene/id/spawn and report exit intent; LocationFlow performs the transition. |
| `OutlineOverlay` | [`scripts/interaction/outline_overlay.gd`](../scripts/interaction/outline_overlay.gd) | Screen-space silhouette outline of the target's own meshes, with original visual layers restored on release. |
| `PointerNavigator` | [`scripts/interaction/pointer_navigator.gd`](../scripts/interaction/pointer_navigator.gd) | Translate world clicks into navigation and the same Interactable activation used by the keyboard. |
| `StagedInteractable` | [`scripts/interaction/staged_interactable.gd`](../scripts/interaction/staged_interactable.gd) | Route an authored prop action through the sequence director's beat/lock boundary. |
| `WorldCue` | [`scripts/interaction/world_cue.gd`](../scripts/interaction/world_cue.gd) | Shared cue roles, palette, material cache and procedural mark meshes; callers own motion and targeting. |

### Actors, looks and animation

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `AnimationRetarget` | [`scripts/actors/animation_retarget.gd`](../scripts/actors/animation_retarget.gd) | Rest-relative semantic rig mapping and baking into real Animation resources; UAL inputs/derivatives remain dev-only. |
| `CharacterAnimation` | [`scripts/actors/character_animation.gd`](../scripts/actors/character_animation.gd) | Semantic-bone resolution, shared clips, authored layers and pose resets; never assume identical rigs. |
| `CharacterDialogueAnimation` | [`scripts/actors/character_dialogue_animation.gd`](../scripts/actors/character_dialogue_animation.gd) | Visible-speaker-to-animation bridge, explicitly opted into by the wrapper; no dialogue routing. |
| `CharacterLook` | [`scripts/actors/character_look.gd`](../scripts/actors/character_look.gd) | Material-name and resting-expression resource; source model geometry stays independent. |
| `CharacterLookApplier` | [`scripts/actors/character_look_applier.gd`](../scripts/actors/character_look_applier.gd) | Apply look treatments, stable paint coordinates and blink without changing the wrapper/rig contract. |
| `CharacterMotionProfile` | [`scripts/actors/character_motion_profile.gd`](../scripts/actors/character_motion_profile.gd) | Per-character tempo, posture and layer parameters for the shared animation API. |
| `CharacterNameplate` | [`scripts/actors/character_nameplate.gd`](../scripts/actors/character_nameplate.gd) | Localized development-only name labels; not collision or click targets. |
| `CharacterVisualAnimation` | [`scripts/actors/character_visual_animation.gd`](../scripts/actors/character_visual_animation.gd) | One wrapper-level animation state machine for actions, seating, dialogue and locomotion. |
| `NpcActor` | [`scripts/actors/npc/npc_actor.gd`](../scripts/actors/npc/npc_actor.gd) | Location actor visibility, facing, marker-path motion and model attachment; not the companion collision body. |
| `NpcGaze` | [`scripts/actors/npc/npc_gaze.gd`](../scripts/actors/npc/npc_gaze.gd) | SkeletonModifier3D gaze layered after animation with bounded trunk/neck/head turns. |
| `PlayerController` | [`scripts/actors/player/player_controller.gd`](../scripts/actors/player/player_controller.gd) | One camera-relative movement path shared by keyboard and automatic navigation, with explicit control locks. |

### Locations, sequencing, camera and presence

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `AmbiencePlayer` | [`scripts/world/ambience_player.gd`](../scripts/world/ambience_player.gd) | Per-location looping ambience and fade-in; session-wide background music belongs to Music. |
| `BPresence` | [`scripts/world/b_presence.gd`](../scripts/world/b_presence.gd) | Rebuild B's presence from existing story state when locations are instantiated. |
| `CameraFocusDirector` | [`scripts/world/camera_focus_director.gd`](../scripts/world/camera_focus_director.gd) | Engage/release interaction shots at the player-lock boundary; hover must not move the camera. |
| `CameraOccluderFader` | [`scripts/world/camera_occluder_fader.gd`](../scripts/world/camera_occluder_fader.gd) | Fade current camera blockers and restore the previous set; not a second target/highlight owner. |
| `CameraRig` | [`scripts/world/camera_rig.gd`](../scripts/world/camera_rig.gd) | Own follow framing, default movement axes, roll, framed points and composable focus layers. |
| `CameraShot` | [`scripts/world/camera_shot.gd`](../scripts/world/camera_shot.gd) | Relative interaction framing resource (center mix, distance, yaw, lens and glide times). |
| `CompanionController` | [`scripts/world/companion_controller.gd`](../scripts/world/companion_controller.gd) | Persistent Q follow/wait/resume body using the location navigation map; hides when the location authors its own Q. |
| `ExitWatch` | [`scripts/world/exit_watch.gd`](../scripts/world/exit_watch.gd) | The blocked-exit staged watch and camera framing; use the host beat lifecycle. |
| `InnerVoiceDirector` | [`scripts/world/inner_voice_director.gd`](../scripts/world/inner_voice_director.gd) | Schedule passive voices under rule/session caps and silence/beat constraints; CheckResolver owns dice. |
| `LocationCatalog` | [`scripts/world/location_catalog.gd`](../scripts/world/location_catalog.gd) | Load location/start/arrival metadata from data/story/locations.json, not a new hard-coded location switch. |
| `LocationFlow` | [`scripts/world/location_flow.gd`](../scripts/world/location_flow.gd) | Coordinate exit, fade, transactional load, arrival and checkpoint through the host's existing beat lock. |
| `LocationHost` | [`scripts/world/location_host.gd`](../scripts/world/location_host.gd) | Load/swap location scenes transactionally: validate scene/id/spawn/placement before replacing the old room. |
| `LocationNavigation` | [`scripts/world/location_navigation.gd`](../scripts/world/location_navigation.gd) | Bake/query a location's own static-collider mesh and expose synchronization; never borrow a neighboring map. |
| `LocationRoot` | [`scripts/world/location_root.gd`](../scripts/world/location_root.gd) | Location-owned spawn, waypoint, actor and interactable lookup contract. |
| `NavMapUtil` | [`scripts/world/nav_map_util.gd`](../scripts/world/nav_map_util.gd) | The one answer to "does this map hold geometry?"; the player, the pointer and the companion call it instead of repeating the check. Region *counts* keep their own owners. |
| `NPresence` | [`scripts/world/n_presence.gd`](../scripts/world/n_presence.gd) | Restore substitute N at the room's authored lectern path endpoint from n_arrived. |
| `OpeningSequence` | [`scripts/world/opening_sequence.gd`](../scripts/world/opening_sequence.gd) | Flag-gated prologue sequencing, shared beat/player locks and checkpoint/resume coordination; do not copy its lock state. |
| `QPresence` | [`scripts/world/q_presence.gd`](../scripts/world/q_presence.gd) | Restore classroom Q and the talk anchor from story flags and room markers. |

### Environment prop behavior

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `ClassroomDoorDressing` | [`scripts/environment/classroom_door_dressing.gd`](../scripts/environment/classroom_door_dressing.gd) | Apply the classroom door wrapper's own materials to the approved imported assembly. |
| `PaperZone` | [`scripts/environment/paper_zone.gd`](../scripts/environment/paper_zone.gd) | Scoped paper-reveal overlay around the window; restores covered meshes and excludes actors. |
| `ProjectorScreen` | [`scripts/environment/projector_screen.gd`](../scripts/environment/projector_screen.gd) | Prop-local screen unroll amount and animation; no story-state ownership. |
| `SeeThroughProp` | [`scripts/environment/see_through_prop.gd`](../scripts/environment/see_through_prop.gd) | Thin collider-free suspended decoration when it hides the player. |
| `SuspendedStair` | [`scripts/environment/suspended_stair.gd`](../scripts/environment/suspended_stair.gd) | Retained unplaced staircase behavior for future authored use; not a new opening requirement. |
| `SwingDoor` | [`scripts/environment/swing_door.gd`](../scripts/environment/swing_door.gd) | Retained hinge behavior, currently unplaced; do not reintroduce the rejected rear-door opening. |
| `WindowCurtain` | [`scripts/environment/window_curtain.gd`](../scripts/environment/window_curtain.gd) | Prop-local curtain drawing and instant restore geometry; story sequencing stays in the location/director. |

### Audio lifecycle

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `AudioRelease` | [`scripts/audio/audio_release.gd`](../scripts/audio/audio_release.gd) | Stop audio players and allow a bounded audio mix to release playback at shutdown; do not hide leak output. |

### Scene-local globally named types

| Public type | Source | Responsibility / reuse boundary |
|---|---|---|
| `ClassroomAnomalies` | [`scenes/locations/classroom/classroom_anomalies.gd`](../scenes/locations/classroom/classroom_anomalies.gd) | Classroom-specific curtain/void/paper staging and restoration; use its authored props and story flags. |
| `ClassroomScreenControl` | [`scenes/locations/classroom/classroom_screen_control.gd`](../scenes/locations/classroom/classroom_screen_control.gd) | Classroom-specific staged projection-screen toggle; leaves story/save state unchanged. |

<!-- class-name-index:end -->

## Shared entry points without `class_name`

Do not make these globally named merely to fit the table above. Use their existing
preload, scene or autoload registration. The autoload registration source is
[project.godot](../project.godot); the list below describes ownership, not a new singleton
policy. See [ARCHITECTURE.md](ARCHITECTURE.md) for the dependency/lifecycle boundaries.

| Entry point | Source | Reuse boundary |
|---|---|---|
| `TestHarness` (local preload alias) | [tests/test_harness.gd](../tests/test_harness.gd) | Reuse `ensure_autoload`, `ensure_state_autoloads`, `clear_session_state`, `arm_watchdog`, `finish`; setup clears shared test saves. Test-only, never a runtime dependency. |
| Capture evidence contract | [tests/evidence_contract.gd](../tests/evidence_contract.gd) | Shared authored-line/panel comparison and evidence fingerprints; capture/test-only, not fabricated images. |
| Classroom wall contract | [tests/classroom_wall_contract.gd](../tests/classroom_wall_contract.gd) | Reuse measured wall/render assertions rather than maintaining another wall specification. |
| `GameState` | [scripts/autoload/game_state.gd](../scripts/autoload/game_state.gd) | Named runtime flags and snapshots, not UI or file I/O. |
| `NarrativeState` | [scripts/autoload/narrative_state.gd](../scripts/autoload/narrative_state.gd) | Validated, identity-based knowledge and snapshots. |
| `Save` | [scripts/autoload/save_manager.gd](../scripts/autoload/save_manager.gd) | Versioned save payload, safe file writes, recovery and world binding. |
| `Loc` | [scripts/i18n/loc.gd](../scripts/i18n/loc.gd) | Persist locale choice and emit locale changes; delegate lookup to L10n. |
| `CueAudio` | [scripts/audio/cue_audio.gd](../scripts/audio/cue_audio.gd) | Shared interaction-cue buffers and players, not one copy per caller. |
| `Music` | [scripts/autoload/music_player.gd](../scripts/autoload/music_player.gd) | One background-music player across room changes. |
| `Settings` | [scripts/autoload/settings_manager.gd](../scripts/autoload/settings_manager.gd) | Preferences, bindings, active input device and change notifications. |
| `Session` | [scripts/ui/game_session.gd](../scripts/ui/game_session.gd) | Title/new-game/save-and-quit transactions; menus do not delete saves themselves. |
| Display mode scene script | [scripts/ui/display_mode.gd](../scripts/ui/display_mode.gd) | Shared window size/fullscreen state and guard; not a world controller. |
| Speaker cue scene script | [scripts/world/speaker_cue.gd](../scripts/world/speaker_cue.gd) | Prop-local conversation-triggered sound; not global music or dialogue logic. |

Example of the **existing** test-only import (the alias is not a `class_name`):

```gdscript
const TestHarness := preload("res://tests/test_harness.gd")
```

### Editor-only tools

The [narrative editor README](../addons/narrative_editor/README.md) maps `core/` paths,
JSON text edits, parity, writer, validator, store and dock. Reuse those editor components
through their existing local preloads; never add a global `class_name`, autoload, export
entry or runtime dependency to make them easier to find. I/O tests use `user://` copies,
not the shipped `res://data/`. Headless assertions live in
[narrative_editor_test.gd](../tests/narrative_editor_test.gd) and
[ability_validation_test.gd](../tests/ability_validation_test.gd).

### Repository / CI tools (Python and shell, not game runtime)

| Need | Existing owner | Important boundary |
|---|---|---|
| Tracked-file inventory and UID auditing | [godot_sidecars.py](../tools/godot_sidecars.py), including `tracked_files(root)` | Shared inventory already handles shallow checkouts and plain fixture trees; the documentation check reuses it. |
| CI pass/fail verdict | [ci_run_check.sh](../tools/ci_run_check.sh) | Preserve nonzero exits, script/parse errors and missing verdict failures. |
| Model inventory/import contract | [model_library.py](../tools/model_library.py) | Uses the existing pack verifier budgets; do not copy the limits. |
| Pack contents and size | [verify_build.py](../tools/verify_build.py), [repo_size.py](../tools/repo_size.py) | Export and tracked-source limits are different contracts; no size exceptions. |
| Screenshot validity | [screenshot_evidence.py](../tools/screenshot_evidence.py), [classroom_render_evidence.py](../tools/classroom_render_evidence.py) | Authored-line/manifest evidence and render provenance, not a general Markdown/type index. |
| Engine noise attribution | [engine_noise_report.py](../tools/engine_noise_report.py) | Classify actual logs; do not filter them to invent a pass. |
| Character preparation / look generation | [prepare_q.py](../tools/prepare_q.py), [prepare_teacher_n.py](../tools/prepare_teacher_n.py), [build_character_looks.py](../art/characters/build_character_looks.py) | Check source/derived reproducibility and provenance; do not hand-edit generated output. |
| Generated environments | [build_outdoor_locations.py](../tools/build_outdoor_locations.py), [build_laboratory.py](../tools/build_laboratory.py) | Regenerate scenes from their owner rather than editing generated locations. |
| Font coverage | [subset_font.py](../tools/subset_font.py) | Rebuild/check subsets when game-visible text changes; keep source fonts out of exports. |
| External Action pins | [check_workflow_action_pins.py](../tools/check_workflow_action_pins.py) | Full commit pins with consistent version comments. |
| Interface palette duplication | [check_ui_palette.py](../tools/check_ui_palette.py) | Refuse one RGB literal in two files; the palette must stay a leaf; report pairs between allowlisted writers. |
| Agent entry/index/template contracts | [check_agent_docs.py](../tools/check_agent_docs.py) | Check public type coverage and local discovery links without importing Godot or changing source files. |

## Keep this map current

1. Add, rename or move a global type? Update exactly one row in its subsystem, keeping
   the actual declaration name, repository-relative source path and a useful boundary.
2. Add a new preload-only/shared helper? Add it to the appropriate discovery section;
   global-type coverage alone cannot discover whether an unregistered script is reusable.
3. Update affected quick routes, callers/tests and relevant canonical design documents.
4. Stage newly added `.gd` files before the inventory check: it follows **tracked** files
   (outside Git it scans a fixture tree, excluding `.git/` and `.godot/`). Then run:

```sh
python3 tools/check_agent_docs.py --check
python3 tests/agent_docs_test.py
```

The independent [Agent documentation workflow](../.github/workflows/agent-docs.yml) runs
on every PR, including changes that introduce a type in a new directory. It rejects a
missing, stale, duplicated, wrongly linked or empty-description type row, duplicate
public declarations, broken local file links in the entry/index/protocol, an instruction
entry over 150 lines, and a PR template without **已检索** or its eight required sections.
It checks file targets, **not external websites, Markdown heading anchors or API semantics**;
existing syntax/runtime tests and human review still apply. A green index is not evidence
that every module is suitable for a particular task or that gameplay was tested.
