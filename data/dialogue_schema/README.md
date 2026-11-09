# Dialogue and inspection content: schema and editing guide

Everything the game says lives in JSON under `data/`. No dialogue line, prompt,
inspection description or objective label is written in GDScript, so a writer can
change the story without opening the editor and without touching code.

```
data/
  dialogue/<locale>/<chapter>.json     conversations: who says what, in order
  inspections/<locale>/<chapter>.json  descriptions of objects the player looks at
  abilities/abilities.json             inner voices: value, speaker, passive rules
  abilities/<locale>.json              inner voices: their name and description
  locale/<locale>.json                 interface strings (prompts, badges, HUD, cards)
  characters/<id>.tres                 speaker name, role, colour, portrait slot
```

`<locale>` is `en` or `zh-CN`.

`<chapter>` is the group the file belongs to. It is not one list: dialogue and
inspections have different chapters because they cover different places.

| Tree | Chapters that ship |
|---|---|
| `data/dialogue/<locale>/` | `prologue`, `corridor`, `street`, `residential`, `alley`, `playground`, `inner_voice` |
| `data/inspections/<locale>/` | `classroom`, `corridor`, `street`, `residential`, `alley`, `playground` |

`inner_voice` is not a place: it holds the lines an inner voice says without being
asked, and keeping it separate makes it obvious how much of the game is the
protagonist talking to himself. `prologue` has no inspections (classroom is the
prologue's room) and `classroom` has no conversations.

The runtime iterates `DialogueLibrary.CHAPTERS` and `InspectionLibrary.CHAPTERS`,
so a chapter file that is not in those constants is never loaded. The editor dock
reads the directory instead and warns when the two disagree — see “Editing in the
editor” below.

Two rules keep this maintainable:

1. **Every language has the same structure.** Same conversations, same node ids,
   same order, same branches, same effects. Only text differs. A translation that
   drops a node fails the build.
2. **Content may not carry gameplay meaning in prose.** A node changes state
   through `effects`, never because its text says so.

## Adding or editing a line

1. Find the chapter file for the scene, e.g. `data/dialogue/en/prologue.json`.
2. Find the node by its `id` (ids never change when text changes; that is what
   makes `git diff` readable and what keeps translations aligned).
3. Edit `text` only. Keep `id`, `speaker`, `next`, `choices`, `effects`,
   `conditions` exactly as they are.
4. Make the identical edit in the other language file — or make both edits at once in
   the editor dock described below.
5. Run the content checks (below). The game refuses to start a conversation whose
   structure is broken, and CI reports the file, the conversation and the node.

## Editing in the editor

Since Phase 6a.1 the same files can be edited inside Godot, in both languages at once,
through the **剧情编辑** dock (`addons/narrative_editor/`; open it from the bottom panel
if it is not on screen). Pick a content type — 剧情对话, 场景检视, 内心声音文案 — then a
chapter, then a conversation and a node; or search by node id, speaker or text in
either language.

The two text boxes are the only editable things. Everything else about the node is
shown read-only next to them: speaker, narrative source, `next`, the options and where
they jump, conditions, effects, the check with its ability, difficulty, kind and both
branches, and whether the conversation is subjective. Each option is a field of its
own, and an inspection's `recall` and `record` text are edited separately from its body.

Saving is one button and it is careful:

- nothing is written until **保存** is pressed, and switching chapter, type or
  selection with unsaved edits asks first (保存并继续 / 放弃修改并继续 / 取消);
- before writing, both languages are compared — same conversations, same node ids in
  the same order, same options in the same order, same branches, effects, conditions
  and checks; only the text may differ. A mismatch is reported with its address, e.g.
  `conversations/q_wake/nodes/3/id`, and nothing is written;
- the candidate files are also run through the loaders the game uses, so a file that
  would fail at start-up is refused before it reaches the disk;
- both files are staged as temporaries and swapped in; if the second cannot be
  written, the first is restored and the save reports a failure naming the file;
- only the strings that changed are rewritten, so the file keeps its formatting, its
  field order and any field the tool does not know about, and the diff is the line
  that changed.

The dock never writes on its own: no watcher, no save-on-blur, no “fix on open”. Its
chapter list comes from the chapter files, and it warns if that disagrees with
`DialogueLibrary.CHAPTERS` / `InspectionLibrary.CHAPTERS`.

## Conversation file

```json
{
  "format_version": 2,
  "locale": "en",
  "chapter": "prologue",
  "conversations": {
    "conversation_id": {
      "default_source": "observed",
      "subjective": false,
      "start": "node_id",
      "nodes": []
    }
  }
}
```

| Field | Meaning |
|---|---|
| `format_version` | Must be `2`. Bumped when the schema changes incompatibly. |
| `locale` | Must match the directory. |
| `chapter` | Free-text label; one file per chapter. |
| `default_source` | Narrative category inherited by every node: `observed`, `reported`, `recalled`, `imagined`. |
| `subjective` | `true` for imagined or expected sequences. Such a conversation **cannot** set flags, change the objective, record observed/reported knowledge, carry a `check`, or mark a choice `once`. The last two are refused because both write story state (the dice record and the "already taken" record); see the notes under Checks and Choices. |
| `start` | Node id the conversation opens on. |

### Nodes

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Stable, unique inside the conversation. Used by tests, parity and `next`. |
| `speaker` | yes | Character id from `data/characters/` (`protagonist`, `q`, `n`, `b`). |
| `text` | yes | The line. May not be empty; a node with only choices may omit it. |
| `source` | no | Overrides `default_source` for this line. |
| `next` | no | Id of the next node. **Absent** = fall through to the next node in file order. **`null`** = the conversation ends here. |
| `choices` | no | Player choices. A node with choices never falls through: only the branches the options point at are reachable from it, so a line placed after a hub needs an explicit `next` from somewhere. If no option is available the presentation ends rather than continuing. |
| `effects` | no | State changes applied when the line is shown. |
| `conditions` | no | `{"all_flags": [...], "not_flags": [...], "requires": {"flag": true}}`. A node whose conditions are not met is skipped, as if it were a `next` step. A skipped `check` node ends the conversation instead of continuing: its branch belongs to the node that rolled it. |
| `tags` | no | Free markers for tooling; unused by the runtime. |

The last node of every conversation must end explicitly with `"next": null`,
otherwise the end of the file is ambiguous and the build fails.

### Choices

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique inside the node. Part of the save/`once` key, so never reuse one. |
| `text` | yes | The option as the player reads it. |
| `next` | yes | Node id the option jumps to. |
| `once` | no | The option disappears after it was taken (tracked per conversation). Writes a story flag, so it is refused inside a `subjective` conversation. |
| `effects` | no | Applied when the option is chosen, not when it is listed. |
| `conditions` | no | Same shape as a node's conditions. |

### Checks

A node may carry a `check` block. It is refused inside a `subjective` conversation:
the resolved result is stored so it cannot be re-rolled, and that record is story
state. The runtime rolls a check when the node is entered,
shows the line, and then continues to one of two branches. A check node never has
`next` and never has `choices`.

| Field | Required | Meaning |
|---|---|---|
| `ability` | yes | Inner-voice id from `data/abilities/abilities.json`. Shipping today: `orientation`. Its value is added to the die. |
| `difficulty` | yes | 1..30. The total needed. Typical values are 8-12. |
| `kind` | yes | `visible` = the player sees the voice, the die, the difficulty and the outcome. `hidden` = only the resulting line is shown. Use `visible` when the player chose the attempt, `hidden` when a voice speaks up on its own. |
| `success` | yes | Node id to continue to on success. |
| `failure` | yes | Node id to continue to on failure. Must exist and must carry real content: a failed check can never be the only way past a required beat. |
| `modifiers` | no | `[{"flag": "saw_set_square", "value": 1}]`. Each set flag adds its value; unset flags add nothing. |
| `repeatable` | no | Default `false`. When false the resolved result is recorded under `check:<conversation>:<node>` and replayed on a later visit, so the attempt cannot be re-rolled. Leave it false. |

```json
{
  "id": "ps_boundary_check",
  "speaker": "voice_orientation",
  "text": "Let me feel how it sits.",
  "check": {
    "ability": "orientation", "difficulty": 9, "kind": "visible",
    "success": "ps_boundary_ok", "failure": "ps_boundary_bad"
  }
}
```

The `speaker` of a voice line is the voice's `speaker` from `abilities.json`
(`voice_orientation` today), not its ability id. The two are separate on purpose: the
ability id is what the dice read, the speaker id is who the reading surface draws.

To stop an attempt being offered twice, gate the *choice* that leads to the check on
its record:

```json
{"id": "frame", "text": "Try the door against its frame.", "next": "ps_boundary_check",
 "conditions": {"not_flags": ["check:pg_shed:ps_boundary_check"]}}
```

Note the colon: the key is `check:<conversation>:<node>`, which is exactly what
`StoryFlags.check_record_flag()` writes.

### Passive inner-voice lines

A voice that speaks without being asked is an ordinary conversation whose first
node is a `hidden` check, plus a rule in `data/abilities/abilities.json`:

```json
{"id": "playground_hoop_orientation", "ability": "orientation",
 "trigger": {"kind": "inspection", "id": "pg_hoop"},
 "conversation": "voice_hoop", "once": true}
```

`trigger.kind` is `inspection`, `location` or `conversation_end`. Rules are rationed
by the director (once per rule, a per-voice session cap, and no two unprompted lines
in a row); see ADR 0003.

### Who a speaker is

A node names a `speaker`; two different things can answer to that id.

- An **ordinary character** (`protagonist`, `q`, `n`, `b`, and anyone added later)
  comes from `CharacterDirectory.ORDINARY_CHARACTER_PATHS`, a short explicit list, so
  that no exported build can be missing the resource. Adding one means adding a
  `.tres` and one line to that list.
- An **inner voice** is found from the ability registry: `abilities.json` gives the
  voice a `speaker` id, and its profile must be `data/characters/<speaker_id>.tres`.
  Nothing is listed twice, and a voice with a missing profile, a mismatched
  `character_id` or a speaker id that collides with an ordinary character is a
  start-up error.

Neither lookup falls back to another profile. A line spoken with someone else's name
and colour is worse than a line that does not appear.

### Inner-voice text and translation exceptions

`data/abilities/<locale>.json` holds one entry per voice, with a `name` and a
`description`. Both are JSON **strings**; a number or an object is an error, not
something to convert.

Both languages must define the same voices, and a Chinese name that is the English
name copied over is treated as an unfinished translation — with one exception,
declared on purpose and only where it is needed:

```json
"orientation": {
  "name": "Orientation",
  "description": "……",
  "untranslated_fields": ["name"]
}
```

`untranslated_fields` lists the fields of *that* voice, in *that* language, that are
allowed to keep the source wording. There is no global switch: an undeclared
identical string is still an error, a declaration only covers the fields it names,
and a declaration whose field was translated after all is an error again, so an
exception cannot outlive the reason it was added. The reference language (`en`) may
not declare anything — its text is the source.

### Effects

| Effect | Shape | Notes |
|---|---|---|
| Set a story flag | `{"type": "set_flag", "flag": "textbook_missing", "value": true}` | Flag names live in `scripts/narrative/story_flags.gd`. |
| Change the objective | `{"type": "set_objective", "key": "objective.check_bag"}` | `key` only — literal text is rejected, because it could not be translated. |
| Record knowledge | `{"type": "record", "entry_id": "...", "source": "observed", "speaker": "protagonist", "text": "..."}` | `source` is one of the four categories below; `text` is what the player later sees in the recollection list, so it is translated like any other line. |

### Narrative sources

| `source` | Badge the player sees | Meaning |
|---|---|---|
| `observed` | SEEN / 亲眼所见 | The protagonist saw or heard it happen. |
| `reported` | HEARD / 听人说的 | Someone else said it. Not verified. |
| `recalled` | REMEMBERED / 记忆里的 | The protagonist remembers it, possibly wrongly. |
| `imagined` | IMAGINED / 想象中的 | Fantasy, worry, expectation. Never becomes world state. |

## Inspection files

```json
{
  "format_version": 1,
  "locale": "en",
  "classroom_schoolbag": {
    "title": "Your schoolbag",
    "prompt": "Search the bag",
    "speaker": "protagonist",
    "source": "observed",
    "text": "…",
    "repeat_text": "…",
    "recall": {"entry_id": "...", "text": "..."},
    "record": {"entry_id": "...", "source": "observed", "text": "..."},
    "effects": [{"type": "set_objective", "key": "objective.no_textbook"}]
  }
}
```

`text` is shown on the first read, `repeat_text` on every later read, and the
optional `recall` line is queued once, right after the first read. `record` writes
a knowledge entry; `effects` are applied on the first read only.

The `prompt` field is the text that appears next to the interact key, so an object's
prompt is translated in the same place as its description. Scenes fall back to a
literal `prompt_text`/`prompt_key` only when the object has no inspection.

## Interface strings

Short strings the interface generates (`prompt.talk`, `objective.check_bag`,
`badge.observed`, `end.slice.title`, …) live in `data/locale/<locale>.json` under
`strings`. Both languages must define exactly the same keys; a missing key shows
as `[[key]]` on screen and fails the build.

## Validation

`godot --headless --path . --script res://tests/dialogue_validation_test.gd` and
the content test check, in CI, that:

- every file is valid JSON with the declared `format_version`;
- node and choice ids are unique, and every `next` points at a node that exists;
- no node is unreachable from `start`, no `next` chain loops, and the last node ends;
  the walk follows exactly the edges the runtime follows — choices for a `choices`
  node, `success`/`failure` for a `check` node, `next` or the file order only for an
  ordinary node — so "unreachable" here means unreachable in play;
- every node has text or choices, and every choice has text, an id and a `next`;
- speakers exist in `data/characters/`, and objective keys exist in every locale;
- a subjective conversation writes no flags, no objective, and no observed or
  reported knowledge (this is refused while parsing, before any line is shown);
- both languages define the same conversations, node ids, order, branches and
  effects, and no inspection is left with an empty translation;
- the inner-voice registry has the types it says it has: `once` is a JSON boolean,
  `requires` is an array of non-empty flag names, a rule's `id`, `ability`,
  `conversation`, `trigger.kind` and `trigger.id` are strings, and a localised
  `name`/`description` is a string rather than something that happens to stringify;
- a translation that is the source text copied over is rejected, except for the
  fields a voice declares in `untranslated_fields` (see above).

Every error names the file, the conversation and the node id, e.g.
`res://data/dialogue/zh-CN/prologue.json: q_wake/interrupted: 'next' points at
'missing_node', which does not exist.`

The editor dock runs its own version of these checks before it saves (structure,
field rules, and the same loaders), and `tests/narrative_editor_test.gd` proves it
does; the tests above are still the authority, because a file can also be edited by
hand.

## Adding a chapter or a language

**Chapter:** create `data/dialogue/<locale>/<chapter>.json` for every locale and add
the chapter name to `DialogueLibrary.CHAPTERS`; if the chapter has inspectable
objects, add `data/inspections/<locale>/<chapter>.json` for every locale and the
chapter to `InspectionLibrary.CHAPTERS` as well. Loading is by chapter file, so nothing
else changes — but the constants are the list the game loads, so a file without a
constant is dead content. The editor dock reads the directory instead of the constants
and warns when the two disagree, which is the cheapest way to notice a missing entry.

**Language:** copy `data/locale/en.json`, the whole `data/dialogue/en/` and
`data/inspections/en/` trees and `data/abilities/en.json`, translate the text, then add
the locale code to `L10n.LOCALES` and to `project.godot` if it needs a different font. The switch key
(`L`) cycles through `L10n.LOCALES`, and the language name is read from the locale
file's `name` field, so the hint is never hard-coded.

## Lines pending author review

These placeholder lines encode a story choice that only the author can settle.
They exist so the level is playable; they are not proposals, and nothing else in
the repository depends on their content.

| Node / inspection | What is undecided |
|---|---|
| `residential.json`, `residential_stair` (`rs_up_1`, `rs_down_1`) | Whether the stair that brings the player back to the same courtyard is literally the same stair. |
| `residential.json`, `animal_sighting` (`a_c_2`, `a_recall`) | Whether the animal should be linked to a biology-textbook drawing at all. Its identity, origin, fate and meaning are deliberately left open. |
| `street.json`, `street_wall` (`w_2`) | Whether the camera that watches an empty strip of grass is a motif worth keeping. |
| `street.json`, `street_notice` (`n_2`) | Whether the mismatched notice on the pole is worth keeping. |
| `inspections/*/residential.json`, `res_stain` | Whether the repeated stain belongs to the same wall, and whether the game should ever say so. |
| `prologue.json`, `q_wake` (whole conversation) | Q's register and how much the protagonist says out loud. |
| `prologue.json`, `expected_b` | Which half-remembered details of the imagined confrontation are allowed to survive. |
| All `zh-CN` files | Every simplified-Chinese line is a placeholder written for this build, pending the author's own voice. |

Working through this list is what the editor dock is for: both languages of one line are
in front of you, the structure they have to keep is shown read-only beside them, and a
save refuses to write a file that breaks it.

The character and story facts that must not change without the author: the
protagonist is already a student when the scene opens; Q is an ordinary classmate,
not a guide; B is a biology teacher who never appears on screen and is only reached
through memory, hearsay and imagination; N is a young substitute; the protagonist
imagined a possible confrontation with B before N arrived.

## Confidentiality

This repository contains an unpublished manuscript that is **not** to be copied
into content. These files contain original placeholder dialogue written for the
prototype. Do not paste manuscript passages, paraphrases of them, or private
drafts into this directory, into tests, into commit messages, or into pull request
descriptions.
