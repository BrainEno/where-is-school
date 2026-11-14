# docs/screenshots：哪些是证据，哪些是历史

[English](README.md)

从 #88 起，Actions 不再把截图提交回 Git：每次捕获只把画面作为 artifact 上传。因此这个目录里已有的画面停在了当时，而游戏还在变；其中一些画面里的台词和对话框，游戏里已经没有了（#186）。在核对标签之前，不要把这里的任何画面当成游戏的现状。

## 标签：`MANIFEST.json`

本目录下直接存放的每一张图片都列在 [`MANIFEST.json`](MANIFEST.json) 里，并带有 `status`：

| status | 含义 | 必须带有 |
|---|---|---|
| `current` | 当前游戏的证据 | 拍摄它的提交和 CI 运行（`captured`）、文件的 SHA-256、尺寸、阅读带的 `ui_fingerprint`；如果画面是对话，还要写明画面上的那句台词（`shows`：语言、源文件、对话、节点、文本） |
| `historical` | 仅作对照保留 | `reason`（保留原因）；可选 `superseded_by`，指向取代它的当前画面 |

子目录各属于自己的评审（`collections`），每个都写明负责它的文档。

`tools/screenshot_evidence.py --check` 在 Godot CI 中运行。以下情况会失败：

- 当前画面上的台词已不是现在的作者文本——**改写开场句后，CI 会一直失败，直到重新捕获这些画面或把它们改标为历史**；
- 当前画面的字节、尺寸或来源与清单不符（画面只能捕获，不能手改像素）；
- 目录里有图片但清单没有，或清单列了但文件不存在；
- 仓库中任何 Markdown 引用了本目录下不存在的画面。

以下情况只给警告：当前对话画面拍摄时的阅读带与现在的不同（台词仍然一致；`--strict` 下视为错误）；文档引用了历史画面，但同一行没有注明“历史”。
`tests/opening_line_evidence_test.gd` 用运行中的游戏核对同一批画面：屏幕上的第一句必须是当前画面所示的节点和句子，中英文都要一致。

`python3 tools/screenshot_evidence.py --report` 每个画面输出一行。

## 当前画面

开场句和阅读带的画面——`01_opening_line.jpg` 与 `ui-dialogue-<1280x720|1600x900|1920x1080>-<en|zh>.jpg`——保持为当前画面。它们是捕获所写 PNG 的全尺寸 JPEG 重新编码（质量 0.9）；PNG 原图在该次运行的 artifact 中。

重新拍摄（例如开场句或对话面板改动之后）：

1. `gh workflow run playthrough-capture.yml --ref <分支> -f relay_dialogue_evidence=true`
2. 运行结束后执行
   `python3 tools/dialogue_evidence_relay.py fetch --run <运行 ID> --apply`：
   它从该次运行的注释中重建每张画面，SHA-256 与捕获时记录的不一致就拒绝，然后写入本目录，并在 `MANIFEST.json` 中记为当前画面。
3. 运行 `python3 tools/screenshot_evidence.py --check`，再提交画面和清单。

捕获脚本只有在面板显示的正是作者文本时才会保存这些画面（`tests/evidence_contract.gd`），所以转交过来的画面不可能是另一句台词。

## 历史画面

本目录下其余画面都来自最后一次回写（`359ed4a`，2026-11-11）或更早：游玩画面 `01`–`33`、点击提示候选、其他 `ui-*` 画面以及编辑器停靠面板。它们呈现的是当时的房间、人物和对话框。`PLAYTHROUGH.md`、`PLAYTHROUGH.log`、`UI_CAPTURE.log` 和 `EDITOR_CAPTURE.log` 是那几次运行的日志。每次新运行的画面见 `Playthrough capture` 工作流的 artifact。
