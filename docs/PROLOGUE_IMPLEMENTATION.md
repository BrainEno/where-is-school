# Biology-class graybox prologue

## Scope and player flow

The game wakes the seated protagonist in the classroom. Q starts an ordinary, overfamiliar conversation with three choice points (greeting, uncertain exam recollection, and response to Q's description of B). Each option produces a distinct immediate line; selections are recorded. The schoolbag adds a fourth choice, whose result also changes Q's later response. All dialogue is newly written placeholder game content, not manuscript text, and awaits owner approval.

After checking the bag, the player can inspect the set square, blackboard, window, and clock, talk to Q, and check the initially closed door. **Space** explicitly starts the lesson when the player is clear of N's entrance path; N enters and B remains absent. N grants free activity, the door opens, and the player can leave, return to the classroom, and reach a clear endpoint at the far end of a short corridor. The endpoint can return to the corridor or restart. The street, animal encounter, larger memory paths, and later chapters are outside this slice.

Controls and run instructions are in the [README](../README.md). The A− / A+ and instant/slow text controls are in the history panel; the chosen settings last for the current run. A long current line can be scrolled with the mouse wheel over the dialogue text; history supports the mouse wheel and Page Up / Page Down.

## Implementation boundaries

- `scenes/main/main.tscn` composes the player, location, HUD, audio, interaction controller, and dialogue runner. `scripts/main/main.gd` orchestrates the compact sequence, locks control during dialogue/transitions, records observed events, and swaps locations. The existing `Main/Ground/Player/Camera3D` smoke-test contract remains intact.
- `PlayerController` owns camera-relative movement, camera framing and seated/standing graybox visuals. Location scenes own geometry and collisions. The classroom manages N's short entrance, the entrance-clearance check, and its door. On re-entry it reconstructs the released state from `GameState`.
- `Interactable` nodes expose an ID, prompt, availability, and radius. `InteractionController` chooses the nearest available target and emits an intent; the main controller interprets the ID. Targeting is distance-based, not a general line-of-sight system.
- `data/dialogue/biology_class.json` contains the placeholder lines, choices, condition branches and scalar effects. `DialogueContent` validates links, IDs, kinds, speaker attribution, and effect categories; `DialogueRunner` traverses the graph and emits lines/choices. `PrologueHUD` renders these, the backlog, settings, and subjective color treatment without being the authoritative state store.
- `GameState` retains its generic flag/snapshot API and adds categorized recording helpers. `observed.*` is written by the scene controller for enacted events; `statement.q.*` / `statement.n.*` represent each speaker's account; `recollection.*` is uncertain memory; `imagination.*` is explicitly not an event; and `choice.*` is a player's selection. Validation prevents dialogue effects from writing objective observations or attributing an imagined line to an NPC. The generic legacy setter remains available to other code, so this is a project convention and validated content boundary, not a security sandbox.
- The hallway and classroom use the same live `GameState` during a run. There is no disk save, mid-dialogue serialization, persistent settings, or inventory system. Audio is limited to synthesized placeholder room tone and a bell; visual assets are primitive grayboxes, not final painterly art. See [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md).

This small custom JSON runtime is a **temporary slice implementation**, not a final dialogue-tool selection. The [architecture](ARCHITECTURE.md) and [roadmap](TECHNICAL_ROADMAP.md) still call for a bounded Dialogic comparison; no addon has been evaluated or adopted here. If an export preset is added, include `data/dialogue/*.json` as non-resource files in the export filter and test the packaged build.

## Documentation conflict

`TECHNICAL_ROADMAP.md` Phase 3 describes a residential approach before the classroom; `PROTOTYPE_BRIEF.md` and this task specify waking in the classroom. This slice follows the classroom-first request and does not implement the residential route. The owner should reconcile the roadmap; this implementation is not a decision about the eventual full-game opening.

## Validation and screenshots

Engine: **Godot 4.7.2.stable.official.ed1daf0bf**, standard GDScript build. On Linux, `GODOT=godot bash tests/run_headless.sh` runs these commands, scans for script/error/failure output, and requires both test completion markers:

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/smoke_test.gd
godot --headless --path . --fixed-fps 60 --quit-after 20000 res://tests/prologue_test.tscn
```

On a clean source copy without `.godot/`, the import and original smoke test passed, and the prologue suite passed **167 checks** with no script/resource errors reported. The suite exercises validation, all authored choice alternatives, evidence categories, long Unicode text and scrolling bounds, history and settings, keyboard interaction, walkable routes/collisions, N's clearance and collider, transitions, revisiting and the endpoint. It checks that imagination doesn't change objective state or move scene actors. See `tests/prologue_test.gd` for precise assertions.

The captures in [`screenshots/`](screenshots/) are from a real Linux Godot window using the Compatibility renderer, Mesa software rendering, dummy audio, and agent-simulated keyboard/mouse input (`--time-scale 2`). They show the opening, choices, history/settings, classroom interaction, imagined possibility, N's entrance/observation, the corridor, and ending. This is graphical smoke evidence, **not** a human playtest, Windows acceptance, real audio listening, normal-speed pacing, or Forward+ performance validation.

### Human acceptance checklist (still to perform)

- [ ] On a clean Windows machine with Godot 4.7.2, import and play at normal speed with the default Forward+ renderer; check framing, navigation, collision, readability, pacing, and performance.
- [ ] Try all Q and book choices; review history, change text size/speed, and verify long text plus Chinese glyphs with a suitable installed/bundled font.
- [ ] Inspect the bag and all four props, attempt the closed door, wait near and away from N's path, talk to N, pass the open door, return, and reach the endpoint; try both endpoint buttons.
- [ ] Listen to the room tone and bell on real audio output; assess levels and looping.
- [ ] Review the placeholder dialogue and assets for narrative/art direction, rights, and production approval.

Remaining work includes human playtesting, accessible font/localization strategy, controls/controller and settings persistence, save/load, a dialogue-tool evaluation, performance profiling, and production art/audio. The current route and timing are deliberately a small vertical-slice test, not a complete school or street.
