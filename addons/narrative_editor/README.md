# Narrative editor (Godot EditorPlugin, editor only)

A dock that edits what the game says, in both languages at once, without leaving the
editor. It is a tool for the author, not a runtime feature.

## What it does

Open the project in Godot 4.7.2 and the **剧情编辑** panel is at the bottom (reopen it from
the bottom panel's selector if it was closed). Pick a content type:

| 内容 | What it edits |
|---|---|
| 剧情对话 | `data/dialogue/<locale>/<chapter>.json` — node text and choice text |
| 场景检视 | `data/inspections/<locale>/<chapter>.json` — `title`, `prompt`, `text`, `repeat_text`, `recall.text`, `record.text` |
| 内心声音文案 | `data/abilities/<locale>.json` — each voice's `name` and `description` |

For every field the dock shows two text boxes, English on the left and 简体中文 on the
right, and a read-only column with the structure of the thing that is selected: node id,
speaker, narrative source, `next`, choices and where they go, conditions, effects, the
check (voice, difficulty, kind, success and failure branches), whether the conversation is
subjective, and — for voices — the value, the speaker and the passive rules that belong to
them.

Everything the tool cannot edit is therefore also something it cannot break: there is no
setter for an id, a branch, a condition, an effect, a check or a number, so the only edits
the dock can express are text edits.

## Saving

- The author edits text; nothing is written until **保存** is pressed.
- Before anything is written, both languages are re-parsed, compared to each other, checked
  against the field rules (no empty choice, no node with neither text nor choices, no empty
  inspection body) and then run through the loader the game itself uses. A candidate that
  would fail at start-up is never written.
- The comparison is structural: conversation ids, node ids and their order, choice ids and
  their order, branches, effects, conditions, checks, `once` flags and speakers must match
  between English and Chinese. Only the player-visible text may differ. A mismatch is
  reported with the address of the first difference, e.g.
  `conversations/q_wake/nodes/3/id`, and nothing is written.
- Writes are staged: both files are written to temporary siblings first, then renamed over
  the originals. If the second rename fails, the first is restored from the text that was
  on disk, and the dock reports a failure naming the file. There is no state in which one
  language is saved and the other is not, and no state in which a failure is reported as a
  success.
- The save is **minimal**: only the spans of the strings that changed are replaced. Field
  order, indentation, unknown fields and the trailing newline survive, so `git diff` shows
  the corrected line and nothing else.

Switching chapter, content type or selection while there are unsaved edits shows a banner
that has to be answered (保存并继续 / 放弃修改并继续 / 取消); it is a banner inside the panel
rather than a modal window so it behaves the same in an editor and in the headless capture.

## Layout of the addon

```
addons/narrative_editor/
  plugin.cfg                        EditorPlugin registration
  plugin.gd                         the only file that touches editor APIs
  core/narrative_paths.gd           where content lives; the chapter list, read from disk
  core/narrative_json_text.gd       one JSON file as text; span-level string replacement
  core/narrative_parity.gd          is the other language still the same document?
  core/narrative_file_writer.gd     staged writes, rollback, one seam for the tests
  core/narrative_store.gd           the session: open, edit, validate, save, search
  ui/narrative_editor_dock.gd       the dock itself (Controls, no file I/O)
```

`core/` is plain `RefCounted` code. It takes a data root and a writer, so
`tests/narrative_editor_test.gd` drives the real code against a `user://` copy of the
content, including the failure paths, without an editor and without risking `res://data`.

## Editor-only, on purpose

- `addons/` is listed in `exclude_filter` in `export_presets.cfg`, and
  `tools/verify_build.py` fails the release check if anything under `res://addons/` is
  packed.
- No autoload, no `class_name`, no preload from `scripts/` or `scenes/`: the game never
  resolves a path into this folder.
- The tool never rewrites content on its own. There is no file watcher, no "fix on open",
  no automatic save; the only write is the one behind the 保存 button.

## Manual acceptance in the Windows editor

CI can prove the data layer and photograph the panel, but no runner opens the Godot
editor. These are the steps that need a person in front of Windows Godot 4.7.2 with a
clean checkout. Each one is either a visible fact or a `git diff` you can read.

**The plugin loads**

1. Open the project. The bottom panel shows a **剧情编辑** tab, and it is in front on the
   first run. If it is not, the bottom panel's selector lists it — click it.
2. Project → Project Settings → Plugins: *Narrative Editor* is **enabled**.
3. Disable it: the panel disappears, nothing else changes, the project still runs
   (F5) and no error is printed. Enable it again: the panel returns.

**Browsing**

4. 内容 offers 剧情对话 / 场景检视 / 内心声音文案. The 章节 list of the first two matches
   the chapter files in `data/dialogue/` and `data/inspections/` — seven and six entries —
   and has no entry that is not a file.
5. Pick a chapter: the left list shows its conversations (dialogue) or its inspectable
   objects (inspections). Pick one: the node list fills, and the first node is selected.
6. Pick a node with choices: the two text boxes hold the English and the simplified
   Chinese line, and the right column lists the options, their ids and where they go, the
   check with its ability, difficulty, kind and both branches, the effects, the conditions
   and whether the conversation is subjective.
7. Node id, speaker and narrative source appear as text, not as fields, and none of them
   can be typed into. Same for the structure column.
8. 内心声音文案 lists `orientation`, shows its value, speaker and passive rules read-only,
   and offers only 名称 and 说明 for editing.

**Searching**

9. Type part of a node id in the search box: the list shows one row per node, labelled
   with the languages that matched. Click a row: the panel jumps to that node and the
   matching text box has focus.
10. Search a Chinese phrase from a line: the Chinese line's node is found, and the row
    names `zh-CN`.
11. Clear the search box: the normal lists come back.

**Editing**

12. Change one English line and one Chinese line. The status strip says how many edits are
    unsaved, 保存 and 放弃修改 become enabled, and the title area shows both file paths.
13. Change a line and change it back: the unsaved count drops to zero, and 保存 is disabled
    again (the tool does not record a non-edit).
14. Press 校验: it reports that a save would not change the structure, and writes nothing
    (`git status` is clean).
15. Press 保存: both files are written and the message names them. `git diff` shows exactly
    one changed line per language — no reformatting, no reordered keys, no trailing
    whitespace changes.
16. Copy the English text into the Chinese box for one node and press 保存: it succeeds
    (text may be identical), and `git diff` still shows one line per file.
17. Copy the English *description* of `orientation` into the Chinese 说明 and press 保存:
    the save is refused, the status area names the validator and the field, and nothing is
    written.
18. Edit a line, then try to switch chapter (or content type, or node) without saving: a
    banner appears with 保存并继续 / 放弃修改并继续 / 取消. 取消 leaves everything as it
    was; 放弃修改并继续 discards and switches; 保存并继续 writes and switches.
19. Edit a line, then press 重新载入: it asks first, then re-reads the file and the box
    shows the text on disk again.

**Failure paths**

20. Make `data/dialogue/zh-CN/prologue.json` read-only (right-click → Properties →
    Read-only, or open it in another program), edit the Chinese line and press 保存: the
    save is refused, the message names the Chinese file, and the English file on disk is
    unchanged (`git status` shows no English change).
21. While the save is blocked, the English text box still shows the unsaved line and the
    status strip still counts it as unsaved — nothing claims success.
22. Remove the read-only flag, press 保存 again: it succeeds.
23. Rename a node id in the Chinese file by hand (a text editor), then switch to that
    chapter in the dock, edit a line and press 保存: the save is refused with the address
    of the mismatch (`conversations/…/nodes/N/id`), and neither file changed.

**Never on its own**

24. With the panel open and unsaved edits, wait a minute: no file changes
    (`git status` clean) and no dialog appears. The tool writes only when 保存 is pressed.

**Build still clean**

25. Export Windows Desktop (or run the release workflow locally), then
    `python3 tools/verify_build.py --exe build/windows/where-is-school.exe`: it passes, and
    its listing contains nothing under `res://addons/`.
26. Run the game from that export: it starts, the dialogue works, and the narrative editor
    is not part of it.

## Disabling it

Project → Project Settings → Plugins → *Narrative Editor* → disable. The content is plain
JSON and stays editable by hand; `data/dialogue_schema/README.md` is the schema.
