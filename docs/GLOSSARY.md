# 术语表：游戏文字用词、玩家称呼、代码 id 与 autoload 对照

> **状态：** 现行
> **最后核对：** 2026-11-19
> **负责人：** 文档 Agent
> **取代者：** 无；本页是 #230 要求的对照表，与 [README.md](README.md)、[ARCHITECTURE.md](ARCHITECTURE.md) 互补

同一个东西在玩家可读文字、场景文件、数据文件和代码注释里常常有三个名字。这份表把它们钉在一起：读到「走廊」就去找 `corridor`，不要去找 `walkway`；写台词时说「器材棚」，不要一会儿「工具棚」一会儿「小屋」。

本页不定义规则，只做对照。规则在 [ARCHITECTURE.md](ARCHITECTURE.md)（运行时边界）、[NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md)（叙事约束）、[data/dialogue_schema/README.md](../data/dialogue_schema/README.md)（对话内容契约）。剧本的可编辑文档格式见 [STORY_DOCS.zh-CN.md](STORY_DOCS.zh-CN.md)。

## 1. 地点：位置 id ↔ 地名

位置 id 是 `data/story/locations.json` 的键，也是 `LocationRoot.location_id`、存档字段和跨场景引用的值。**代码一律用 id，不用玩家称呼。** 地名列是游戏里显示的 `place.<id>` 文案（`data/locale/*.json`），台词提到这个地方时也用它。场景都在 `scenes/locations/<id>/<id>.tscn`。

| 位置 id | 中文地名 | 英文地名 | 备注 |
|---|---|---|---|
| `classroom` | 教室 | Classroom | 生物课教室，序章所在 |
| `corridor` | 走廊 | Corridor | 三层教学楼的走廊；旧文档写作 walkway |
| `street` | 街上 | Street | 校门外的街 |
| `residential` | 居民楼 | The flats | 几栋居民楼和楼间的居民院；不叫「小区」/ estate |
| `alley` | 小巷 | Alley | 居民楼后面，尽头是通往操场的栅栏门 |
| `playground` | 操场 | Playground | 旧文档写作 schoolyard；台词里英文多用 the yard |
| `laboratory` | —（无 `place.` 文案） | — | 尚不可达的开发切片 |
| `staff_office` | 教师办公室 | Staff office | |
| `restroom` | 厕所 | Restroom | 一楼 |
| `restroom_02` | 厕所（二楼） | Restroom (02) | |
| `restroom_03` | 厕所（三楼） | Restroom (03) | |
| `archive` | 档案室 | Archive | 走廊两端的附属房间之一 |
| `plan_room` | 图纸室 | Plan room | 同上 |
| `projection_room` | 投影准备室 | Projection room | 同上 |
| `computer_room` | 计算机教室 | Computer lab | 同上 |
| `vacant_office` | 空办公室 | Empty staff room | 同上 |
| `principal_office` | 校长室 | Principal’s office | 同上 |

`objective.*` 是目标条文案的 locale 键，不是地点。地点与目标的对应写在 `locations.json` 的 `objective` 字段里，会随流程变化。

## 2. 游戏文字用词（台词与检视文字必须一致）

中英两份内容是同一结构的两种语言，所以一个物件在两边各只有一个名字。改写或新写台词时按这张表；表外的物件第一次出现时，在这里补一行。

| 中文 | 英文 | 不要再写 | 说明 |
|---|---|---|---|
| 器材棚 | shed | 器材室、工具棚、小屋 | 操场边那间锁着的绿门小棚 |
| 操场 | yard / playground | 场子 | 整块场地；`place.playground` 是 Playground |
| 球场 | court | 院子、院里 | 地上画了白线、两头有篮筐的那一块 |
| 居民院 | courtyard | 院子（指居民楼时） | 居民楼之间的院子 |
| 居民楼 | the flats | 小区、estate | 也用于「居民楼后面的空地」 |
| 走廊 | corridor | walkway | |
| 生物课本 | textbook / biology textbook | 生物书 | 主角书包里缺的那本；Q 的口语里说「生物书」保留 |
| 栅栏门 / 铁栅门 | alley gate | estate gate | 小巷与操场之间的同一道门 |
| 防火门 | fire door | | 操场回教学楼的门，与「铁门」不同 |
| 铁门 | metal door / service door | | 小巷里挂着坏 U 形锁的那扇，与栅栏门不同 |
| 交还牌 | return plate | | 街边、巷口的小牌子 |
| 交还板 | return board | | 操场上那块板，与交还牌是不同物件 |
| 篮筐 | hoop | | 与「篮板」（backboard）不同 |

## 3. 人物、内心声音与知识徽章

| 说话人 id | 中文名 | 英文名 | 是谁 |
|---|---|---|---|
| `protagonist` | 你 | You | 以学生身份回到学校的成年人。叙述用第二人称，**游戏没有独立的旁白角色**：旁白就是主角说话人下的 `observed` 或 `recalled` 文字。故事文档里写作「旁白」，导入时仍是 `protagonist` |
| `q` | Q | Q | 同学。话多、自来熟，好像很熟悉主角；主角不记得他 |
| `b` | B | B | 生物老师。序章缺席，只出现在想象与他人转述里 |
| `n` | N | N | 年轻的代课老师，最后宣布自习 |
| `student` | 同学 | Classmate | 无名的其他学生 |
| `voice_orientation` | 路感 | Orientation | 内心声音，见下 |

**内心声音**（[叙事圣经](NARRATIVE_BIBLE.md#inner-voices)定稿六个，目前只实装路感）：路感 Orientation（空间、方向）、细察 Scrutiny（细节与证据）、回声 Echo（记忆与联想）、臆想 Imagination（想象与潜意识）、推演 Inference（推理与因果）、共鸣 Resonance（情绪与人际）。

**知识来源与徽章：**

| Source | 中文徽章 | 英文徽章 | 能否变成世界状态 |
|---|---|---|---|
| `observed` | 亲眼所见 | SEEN | 能 |
| `reported` | 听人说的 | HEARD | 能 |
| `recalled` | 记忆里的 | REMEMBERED | 能 |
| `imagined` | 想象中的 | IMAGINED | **永远不能** |

## 4. 内容文件：章节

`data/dialogue/<locale>/<章节>.json` 共 8 章，`data/inspections/<locale>/<地点>.json` 共 17 份（按位置 id 命名）。对话章节与地点不是一一对应：

| 章节 | 内容 |
|---|---|
| `prologue` | 教室里的全部会话：Q、N、点名、窗帘异常、跌落 |
| `corridor` | 走廊里的喇叭、推车、等待、楼层表 |
| `school_annexes` | 走廊两端六个附属房间的对齐会话 `align_*` |
| `street` | 到达街上、校墙、告示、同学 |
| `residential` | 到达居民楼、楼梯、绿色动物 |
| `alley` | 到达小巷 |
| `playground` | 到达操场、器材棚、球 |
| `inner_voice` | 路感的被动开口 `voice_*` |

## 5. autoload：节点名 ↔ 脚本

`project.godot` 的 `[autoload]` 节点名与脚本文件名**有意不一致**（`Save` 的脚本是 `save_manager.gd`）。代码里引用单例时用节点名。共 10 个，按注册顺序：

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
| `Settings` | `scripts/autoload/settings_manager.gd` | 玩家偏好（文字、声音、界面缩放、操作），见 [ADR 0005](adr/0005-saves.md) |
| `Session` | `scripts/ui/game_session.gd` | 一次游玩的进出（标题、继续、新游戏）；脚本不在 `scripts/autoload/` 下 |

## 6. 核心术语

| 术语 | 含义 | 出处 |
|---|---|---|
| **beat** | 一段被编排的场景节拍：`begin_beat()` 到 `end_beat()` 之间，房间归这一拍所有。不是「关卡」。 | `scripts/world/opening_sequence.gd` |
| **step** | 序章的一步（`wake`、`q_wake`、`bag`、`expectation`、`bell`、`substitute`），每步由一个 flag 证明已完成，读档从第一个未完成的步继续。 | `scripts/world/prologue_steps.gd` |
| **Source** | 一条知识的来路，见第 3 节徽章表。 | `data/dialogue_schema/README.md` |
| **subjective** | 主观会话（想象、回忆）：不能设 flag、不能检定、不能有 `once` 选项，只能记录 `recalled` / `imagined`。 | 同上 |
| **flag** | 一个剧情布尔（少数带值），存在 `GameState` 里。常量表在 `scripts/narrative/story_flags.gd`。**该文件是文档索引，不是白名单**：`set_flag()` 只拒绝空名，不校验常量表。 | `scripts/autoload/game_state.gd` |
| **`seen:<inspection>`** | 看过某个检视物的落盘键，由检视自动写入，可以在 conditions 与检定加值里读。 | `scripts/narrative/story_flags.gd` |
| **`check:<conversation>:<node>`** | 一次检定结果的落盘键。非 `repeatable` 的检定会写入它，所以同一尝试不会被重掷。conditions 里出现这种键是正常内容，不是待注册的 flag。 | `data/dialogue_schema/README.md` |
| **`choice:<conversation>:<option>`** | 选项「已经选过」的落盘键，用于 `once` 选项。同样不是待注册的 flag。 | 同上 |
| **entry_id** | 一条知识条目的稳定 id。**全库只记录一次**：两个节点写同一个 `entry_id` 会让同一件事在记忆列表里出现两遍。 | `tests/dialogue_content_test.gd` |
| **inspection** | 一个可观察物：一段文字、一个 `repeat_text`、可选的 `recall` 和 `record`。不是对话。 | `data/inspections/` |
| **route** | `ConversationRouter` 里的一张有序规则表，首个 `requires` 命中者胜。route id 通常与它默认指向的会话同名，但不必相同。 | `scripts/dialogue/conversation_router.gd` |
| **passive** | 内心声音自动开口的规则：触发方式为 `inspection` 或 `location`，目标的会话**必须**以隐藏检定开场（玩家没做选择，所以不掷可见骰）。 | `data/abilities/abilities.json` |
| **故事文档 / 台本** | 对话与检视文字导出的可编辑文本（Google 文档），每行带稳定 id，改完可导回 JSON。 | [STORY_DOCS.zh-CN.md](STORY_DOCS.zh-CN.md) |

## 7. 维护约定

本表在出现新的不一致或新物件时更新。若改了上面任何一处 id、地名、autoload 名或脚本路径，同一个 PR 里同步本页——`tools/check_docs_index.py --check` 会拦住漏进索引的文档，但拦不住表里某一行的内容过时，那需要人看一眼。

本页引用的每条事实都可在仓库里直接核对：`data/story/locations.json`、`data/locale/*.json` 的 `place.` / `name.` / `badge.` 键、`project.godot` 的 `[autoload]`、`data/dialogue_schema/README.md`、`scripts/narrative/story_flags.gd`。
