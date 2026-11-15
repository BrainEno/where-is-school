# docs/screenshots：哪些是证据，哪些是历史

[English](README.md)

从 #88 起，Actions 不再把截图提交回 Git：每次捕获只把画面作为 artifact 上传。因此这个目录里已有的画面停在了当时，而游戏还在变；其中一些画面里的台词和对话框，游戏里已经没有了（#186）。在核对标签之前，不要把这里的任何画面当成游戏的现状。

## 标签：`MANIFEST.json`

本目录下直接存放的每一张图片都列在 [`MANIFEST.json`](MANIFEST.json) 里，并带有 `status`：

| status | 含义 | 必须带有 |
|---|---|---|
| `current` | 当前游戏的证据 | 拍摄它的提交和 CI 运行（`captured`）、文件的 SHA-256、尺寸，以及画面内容：对话画面要写阅读带的 `ui_fingerprint` 和那句台词（`shows`：语言、源文件、对话、节点、文本）；教室时钟画面要写场景、视角、指针设定的时间，以及从该画面像素上读出的时间（`shows`：`kind: "clock"`、scene、view、reads、measured） |
| `historical` | 仅作对照保留 | `reason`（保留原因）；可选 `superseded_by`，指向取代它的当前画面 |

子目录各属于自己的评审（`collections`），每个都写明负责它的文档。

`tools/screenshot_evidence.py --check` 在 Godot CI 中运行。以下情况会失败：

- 当前画面上的台词已不是现在的作者文本——**改写开场句后，CI 会一直失败，直到重新捕获这些画面或把它们改标为历史**；
- 当前时钟画面显示的时间已不是场景指针现在的时间（指针从 `scenes/locations/classroom/classroom.tscn` 读取），或拍摄时从像素读出的时间与当时场景设定的时间不一致；
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

### 教室时钟（#173）

Q 告诉玩家生物课九点开始，所以教室前墙上的时钟指向九点。`tests/capture_classroom_clock.gd` 用三种视角拍摄它，每张都是真实的 1600 × 900 渲染：

| 画面 | 视角 |
|---|---|
| `clock_closeup` | 正对表盘的相机 |
| `clock_gameplay_rows` | 游戏相机，玩家站在第一排课桌旁的过道 |
| `clock_gameplay_aisle` | 游戏相机，站在讲台下过道中表盘最大、且两根指针都完整可见的位置 |

每个视角都会再渲染同一帧：隐藏两根指针、只显示时针、只显示分针。指针的像素就是它出现时发生变化的那些像素，所以表盘上画的任何东西都不会被当成指针。`tests/clock_reading.gd` 把这些像素映射回表盘平面（斜看的表盘按表盘来读，而不是按屏幕上的椭圆来读），报告每根指针指向哪里、看起来多长、多深，以及有多少长度可见（实测长度与几何投影长度之比）。只有每个视角都读出 `9:00`、两根指针都与表盘有足够反差、每根指针至少 90% 可见、并且分针看起来更长，捕获才通过。有指针被遮挡的过道位置会被跳过，并在 `CLOCK.txt` 中记为 `occluded`。每条记录都带有捕获的 `verdict`；只有 `PASS` 的画面才能记为当前画面（`fetch --apply` 与 `screenshot_evidence.py` 都会拒绝其余画面；`fetch --out <目录>` 可把失败运行的画面写到别处查看）。近景下指针与九点的偏差上限为 3°；游戏相机中表盘只有几十像素宽，上限为 15°（时针的一刻钟、分针的两分半）。

时钟捕获在 `Classroom visual evidence` 的每个渲染任务中运行（Forward+ 与 Compatibility），`tools/classroom_render_evidence.py` 会复核它的读数。`tests/clock_reading_test.gd`（Godot CI，headless）在它自己绘制的表盘上运行读取器——正面、透视压缩、40 像素宽、缺指针、指针过淡、污渍、侧对的表盘——并检查教室的指针节点读出九点。

提交这些画面：

1. `gh workflow run classroom-art-evidence.yml --ref <分支> -f relay_clock_evidence=true`
2. `python3 tools/dialogue_evidence_relay.py fetch --run <运行 ID> --apply`
3. 运行 `python3 tools/screenshot_evidence.py --check`，再提交画面和清单。

**观察到，未修改。** 在运行 43668432193 中（两个渲染器结果一致），黑板上方的天花板灯具在离黑板最近的三个过道位置遮住了部分分针（房间坐标 x 0.45；z −2.9：分针可见 77%，−3.4：43%，−3.9：0%）——恰好是表盘最大的位置。因此过道画面取自 z −2.4。移动灯具或时钟需要修改 `classroom.tscn`（#151 协调范围），留给 owner 决定。

这是 Linux 软件渲染（Mesa lavapipe/llvmpipe）。九点在 Windows 屏幕上是否清楚可读、owner 是否接受这些画面，仍由 owner 在 #173 中决定。

## 历史画面

本目录下其余画面都来自最后一次回写（`359ed4a`，2026-11-11）或更早：游玩画面 `01`–`33`、点击提示候选、其他 `ui-*` 画面以及编辑器停靠面板。它们呈现的是当时的房间、人物和对话框。`PLAYTHROUGH.md`、`PLAYTHROUGH.log`、`UI_CAPTURE.log` 和 `EDITOR_CAPTURE.log` 是那几次运行的日志。每次新运行的画面见 `Playthrough capture` 工作流的 artifact。
