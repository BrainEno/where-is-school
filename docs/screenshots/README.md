# docs/screenshots — what is evidence and what is history

[简体中文](README.zh-CN.md)

Since #88, Actions no longer commits frames back to Git: each capture run uploads its
frames as an artifact. The frames already in this folder therefore stopped moving while
the game kept changing, and some of them show lines and a dialogue box the game no longer
has (#186). Take nothing here as the state of the game without checking its label first.

## The label: `MANIFEST.json`

Every image directly in this folder is listed in [`MANIFEST.json`](MANIFEST.json) with a
`status`:

| status | means | must carry |
|---|---|---|
| `current` | evidence of the game as it is | the commit and CI run that took it (`captured`), its SHA-256, its size, the reading band's `ui_fingerprint`, and — when it shows dialogue — the line it shows (`shows`: locale, source file, conversation, node, text) |
| `historical` | kept for comparison only | a `reason`; optionally `superseded_by`, naming the current frame that replaced it |

Subfolders are their own reviews (`collections`), each with the document that owns it.

`tools/screenshot_evidence.py --check` runs in Godot CI. It fails when:

- a current frame's line is no longer the authored one — **rewrite the opening line and
  CI fails until the frames are captured again or relabelled**;
- a current frame's bytes, size or provenance do not match its entry (frames are captured,
  never retouched by hand);
- an image is in the folder but not in the manifest, or listed but missing;
- a Markdown file anywhere in the repository refers to a frame here that does not exist.

It warns when a current dialogue frame was taken with a different reading band than the
one in the tree now (the words still match; `--strict` makes it an error), and when a
document cites a historical frame without saying so on the same line.
`tests/opening_line_evidence_test.gd` checks the same frames against the running game: the
first line on screen must be the node and sentence the current frames show, in English and
in Chinese.

`python3 tools/screenshot_evidence.py --report` prints one line per frame.

## Current frames

The frames of the opening line and the reading band — `01_opening_line.jpg` and
`ui-dialogue-<1280x720|1600x900|1920x1080>-<en|zh>.jpg` — are kept current. They are
full-size JPEG re-encodings (quality 0.9) of the PNGs the capture wrote; the PNGs are in the
run's artifact.

To take them again (for example after the opening line or the dialogue panel changes):

1. `gh workflow run playthrough-capture.yml --ref <branch> -f relay_dialogue_evidence=true`
2. When the run has finished:
   `python3 tools/dialogue_evidence_relay.py fetch --run <run id> --apply`
   rebuilds every frame from the run's annotations, refuses any whose SHA-256 differs
   from the one the capture recorded, writes them here, and records them as current in
   `MANIFEST.json`.
3. `python3 tools/screenshot_evidence.py --check`, then commit the frames and the manifest.

The capture scripts refuse to save these frames unless the panel draws the authored
sentence (`tests/evidence_contract.gd`), so a relayed frame cannot be of another line.

## Historical frames

Everything else directly in this folder is from the last write-back
(`359ed4a`, 2026-11-11) or earlier: the playthrough frames `01`–`33`, the cue candidates,
the other `ui-*` frames and the editor dock. They show the rooms, the people and the
dialogue box as they were then. `PLAYTHROUGH.md`, `PLAYTHROUGH.log`, `UI_CAPTURE.log` and
`EDITOR_CAPTURE.log` are the logs of those runs. The frames of each new run are the
artifacts of the `Playthrough capture` workflow.
