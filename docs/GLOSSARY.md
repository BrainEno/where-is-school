# Project Glossary and Terminology Mapping (术语表与命名对照)

This document establishes the canonical terminology and mappings between player-facing narrative descriptions, design documentation, data IDs, and code implementations in **where-is-school** (resolving [issue #230](https://github.com/BrainEno/where-is-school/issues/230) and [issue #208](https://github.com/BrainEno/where-is-school/issues/208)).

---

## 1. Locations: Player-Facing Names vs Data IDs (地点对照)

In gameplay, documentation, and dialogue, locations are often referred to by narrative names (such as "walkway" or "schoolyard"). In content files (`data/story/locations.json`) and scene paths, stable technical identifiers are used.

| English Player Name | Chinese Name (中文称呼) | Story Data ID (`locations.json`) | Scene Path (`res://...`) | Notes |
|---|---|---|---|---|
| **Classroom** | 生物教室 / 起始教室 | `classroom` | `scenes/locations/classroom/classroom.tscn` | Spawn point (`PlayerStart`). Opening lesson, desk inspection, Q & N dialogue. |
| **Walkway** | 教学楼连廊 / 走廊 | `corridor` | `scenes/locations/corridor/corridor.tscn` | Referred to as "walkway" in README and design briefs; data ID is `corridor`. Direct route between classroom and schoolyard. |
| **Street** | 街道 / 校外街道 | `street` | `scenes/locations/street/street.tscn` | Outside the main school gate; alternative longer exploratory route. |
| **Residential Courtyard** | 居民区小院 / 住宅庭院 | `residential` | `scenes/locations/residential/residential.tscn` | Courtyard with planter, staircase, and encounter with the green animal. |
| **Alley** | 巷道 / 夹道 | `alley` | `scenes/locations/alley/alley.tscn` | Connecting passage between residential courtyard and the schoolyard. |
| **Schoolyard** | 操场 / 远端操场 | `playground` | `scenes/locations/playground/playground.tscn` | Referred to as "schoolyard" in README and design docs; data ID is `playground`. Milestone 3 slice concludes at the far fence gap. |
| **Laboratory** | 实验室 | `laboratory` | `scenes/locations/laboratory/laboratory.tscn` | Room model and scene registered in `locations.json` (`spawn: Entry`), but has no playable entrance in the prologue vertical slice. |

---

## 2. Autoload Singletons (全局单例对照)

Autoload singletons are registered in `project.godot` under `[autoload]`. When calling an autoload singleton in GDScript, use the **Singleton Name** registered in `project.godot`, which may differ from the script's `class_name` or filename.

| Singleton Name (`project.godot`) | Class Name (`class_name`) | Script Path | Responsibility & Notes |
|---|---|---|---|
| `GameState` | `GameState` | `scripts/autoload/game_state.gd` | Runtime session flags (`_story_flags`), active location, spawn points, camera targets. In-memory only; does not write to disk directly. |
| `NarrativeState` | `NarrativeState` | `scripts/autoload/narrative_state.gd` | Epistemic knowledge log: records what the protagonist knows and how they know it (`observed`, `reported`, `recalled`, `imagined`). |
| `Save` | `SaveManager` | `scripts/autoload/save_manager.gd` | **Singleton name is `Save`**, not `SaveManager`. Coordinates persistence, verified write-and-swap, corrupted file quarantine (ADR 0005). |
| `Loc` | `Loc` | `scripts/i18n/loc.gd` | Runtime locale switching, string lookup, language change notifications. |
| `CueAudio` | `CueAudio` | `scripts/audio/cue_audio.gd` | Audio playback for interaction cues, sound effects, and feedback. |
| `Music` | `MusicPlayer` | `scripts/autoload/music_player.gd` | **Singleton name is `Music`**, not `MusicPlayer`. Plays global background music across room transitions. |
| `Settings` | `SettingsManager` | `scripts/autoload/settings_manager.gd` | **Singleton name is `Settings`**, not `SettingsManager`. User preferences (audio volume dials, text size/speed, input rebindings). |
| `Session` | `GameSession` | `scripts/ui/game_session.gd` | **Singleton name is `Session`**, not `GameSession`. Located in `scripts/ui/` rather than `scripts/autoload/` because it manages top-level UI states (title screen, gameplay session, pause menu). |

---

## 3. Core Architecture & System Concepts (系统与架构术语)

- **Leaf Module (叶子模块)**:
  A zero-dependency or low-dependency script holding shared constants or static utility methods (e.g. `Palette`, `NavMapUtil`, `SettingsStore`). Leaf modules never depend on gameplay, UI, or narrative layers, allowing cross-layer reuse without circular or inverted dependencies.
- **Inspectable / Inspection (可调查物与调查条目)**:
  An interactable object in a scene. When clicked, it displays examination dialogue or internal reflection parsed from `data/inspections/{locale}/{location}.json` by `InspectionLibrary`.
- **DestinationCue / HoverCue / WorldCue (空间视觉指引)**:
  Procedural UI visual feedback drawn in code:
  - `DestinationCue`: Small unshaded ground marker (ring + dot) indicating floor click destination.
  - `HoverCue` / `OutlineOverlay`: Warm thin silhouette outline traced around an interactable object when targeted.
  - `WorldCue`: Spatial interaction indicators.
- **Room Key (房间定调)**:
  The process in asset pipeline generation (`build_character_looks.py`) where character shadow and highlight colors are gently shifted toward a room's ambient lighting (e.g. classroom purple shadow `#7E74B0` and apricot highlight `#FFE0B4`).
- **ADR (Architecture Decision Record)**:
  Documents in `docs/adr/` recording significant technical decisions (e.g. ADR 0005 for save system, ADR 0007 for repository size limits).

---

## 4. Narrative & Dialogue Terms (叙事与对话术语)

- **Beat (剧情节拍)**:
  A discrete narrative milestone within a scene (e.g. `classroom_intro`, `after_bell`, `free_period`). Managed by the scene's `Director` node to control NPC positions, available exits, and dialogue triggers.
- **Source (叙事声音 / 来源)**:
  The identity or character voice delivering dialogue lines. Standard sources include `protagonist`, `q`, `b`, `n`, and `inner`. In UI, different sources receive distinct color styling (e.g. plum for speaker names, ink for body text, red ink for choices).
- **Story Flag (叙事标记)**:
  A boolean or integer variable tracked in `GameState` (for physical world state, such as `left_classroom` or `talked_to_q`) or `NarrativeState` (for knowledge entries).
- **Epistemic Modality (认识模态)**:
  The epistemic distinction preserved in `NarrativeState`:
  - `observed`: Directly witnessed in the physical environment.
  - `reported`: Heard from another character (e.g. Q's claims).
  - `recalled`: Subjective memory from the past.
  - `imagined`: Explicitly framed imagination or anxiety (e.g. the confrontation with B).
