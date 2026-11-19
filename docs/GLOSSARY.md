# 术语表：玩家称呼、代码 id 与 autoload 对照

> **状态：** 现行
> **最后核对：** 2026-11-19
> **负责人：** 文档 Agent
> **取代者：** 无；本页是 #230 要求的对照表，与 [README.md](README.md)、[ARCHITECTURE.md](ARCHITECTURE.md) 互补

同一个东西在玩家可读文字、场景文件、数据文件和代码注释里常常有三个名字。这份表把它们钉在一起，唯一的目的是让搜索能命中：读到"走廊"就去找 `corridor`，不要去找 `walkway`。

本页不定义规则，只做对照。规则在 [ARCHITECTURE.md](ARCHITECTURE.md)（运行时边界）、[NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md)（叙事约束）、[data/dialogue_schema/README.md](../data/dialogue_schema/README.md)（对话内容契约）。

## 1. 地点：英文称呼 ↔ 位置 id

位置 id 是 `data/story/locations.json` 的键，也是 `LocationRoot.location_id`、存档字段和跨场景引用的值。**代码一律用 id，不用玩家称呼。**

| 英文称呼（文档/README） | 位置 id | 场景 | 中文称呼 |
|---|---|---|---|
| classroom | `classroom` | `scenes/locations/classroom/classroom.tscn` | 教室 |
| walkway | `corridor` | `scenes/locations/corridor/corridor.tscn` | 走廊 |
| street | `street` | `scenes/locations/street/street.tscn` | 校外街道 |
| residential courtyard | `residential` | `scenes/locations/residential/residential.tscn` | 住宅院子 |
| alley | `alley` | `scenes/locations/alley/alley.tscn` | 小巷 |
| schoolyard | `playground` | `scenes/locations/playground/playground.tscn` | 操场 |
| laboratory | `laboratory` | `scenes/locations/laboratory/laboratory.tscn` | 实验室（尚不可达） |
| staff office | `staff_office` | `scenes/locations/staff_office/staff_office.tscn` | 办公室 |
| restroom | `restroom` | `scenes/locations/restroom/restroom.tscn` | 卫生间 |

**最容易搜错的两处：**

- **walkway = corridor。** README 的路线图写 walkway，因为玩家看它是一条走廊状的高架通道；代码与所有内容文件叫 `corridor`。
- **schoolyard = playground。** README 与叙事文档用 schoolyard（学校的院子），`data/` 与脚本用 `playground`。两者是同一个地方，不是两个。另有 `residential` 有时被写成 "courtyard"，那是住宅院子，与学校无关。

`objective.*` 是目标条文案的 locale 键，不是地点。地点与目标的对应写在 `locations.json` 的 `objective` 字段里，会随流程变化。

## 2. autoload：节点名 ↔ 脚本

`project.godot` 的 `[autoload]` 节点名与脚本文件名**有意不一致**（`Save` 的脚本是 `save_manager.gd`）。代码里引用单例时用节点名。

| autoload 名 | 脚本 | 职责 |
|---|---|---|
| `Diagnostics` | `scripts/autoload/diagnostics.gd` | 离线诊断收集与导出 |
| `GameState` | `scripts/autoload/game_state.gd` | 剧情 flag 与快照；不认识文件 |
| `NarrativeState` | `scripts/autoload/narrative_state.gd` | 已获得的知识条目 |
| `Save` | `scripts/autoload/save_manager.gd` | 存取 `GameState` / `NarrativeState` 的快照 |
| `Loc` | `scripts/i18n/loc.gd` | 本地化字符串 |
| `CueAudio` | `scripts/audio/cue_audio.gd` | 指针反馈音 |
| `WorldAudio` | `scripts/audio/world_audio.gd` | 世界音（脚步、椅子、纸、门）与 SFX 总线 |
| `Music` | `scripts/autoload/music_player.gd` | 全场唯一背景音乐播放器，跨场景存活 |

游戏会话对象 `Session` 不是 autoload，其脚本在 `scripts/ui/game_session.gd`。搜索时按脚本找，不要按 `scripts/autoload/` 找。

## 3. 核心术语

| 术语 | 含义 | 出处 |
|---|---|---|
| **beat** | 一段被编排的场景节拍：`begin_beat()` 到 `end_beat()` 之间，房间归这一拍所有。不是"关卡"。 | `scripts/world/opening_sequence.gd` |
| **Source** | 一条知识的来路，四选一：`observed` / `reported` / `recalled` / `imagined`。决定记忆列表里显示哪个徽章，也决定它能否变成世界状态（只有 `imagined` 永远不能）。 | `data/dialogue_schema/README.md` |
| **flag** | 一个剧情布尔（少数带值），存在 `GameState` 里。常量表在 `scripts/narrative/story_flags.gd`。**该文件是文档索引，不是白名单**：`set_flag()` 只拒绝空名，不校验常量表。 | `scripts/autoload/game_state.gd` |
| **`check:<conversation>:<node>`** | 一次检定结果的落盘键。非 `repeatable` 的检定会写入它，所以同一尝试不会被重掷。conditions 里出现这种键是正常内容，不是待注册的 flag。 | `data/dialogue_schema/README.md` |
| **`choice:<conversation>:<option>`** | 选项"已经选过"的落盘键，用于 `once` 选项。同样不是待注册的 flag。 | 同上 |
| **entry_id** | 一条知识条目的稳定 id。**全库只记录一次**：两个节点写同一个 `entry_id` 会让同一件事在记忆列表里出现两遍。 | `tests/dialogue_content_test.gd` |
| **inspection** | 一个可观察物：一段文字、一个 `repeat_text`、可选的 `recall` 和 `record`。不是对话。 | `data/inspections/` |
| **route** | `ConversationRouter` 里的一张有序规则表，首个 `requires` 命中者胜。route id 通常与它默认指向的会话同名，但不必相同。 | `scripts/dialogue/conversation_router.gd` |
| **passive** | 内心声音自动开口的规则：触发方式为 `inspection` 或 `location`，目标的会话**必须**以隐藏检定开场（玩家没做选择，所以不掷可见骰）。 | `data/abilities/abilities.json` |

## 4. 维护约定

本表只在出现新的不一致时更新。若改了上面任何一处 id、autoload 名或脚本路径，同一个 PR 里同步本页——`tools/check_docs_index.py --check` 会拦住漏进索引的文档，但拦不住表里某一行的内容过时，那需要人看一眼。

本页引用的每条事实都可在仓库里直接核对：`data/story/locations.json`、`project.godot` 的 `[autoload]`、`data/dialogue_schema/README.md`、`scripts/narrative/story_flags.gd`。
