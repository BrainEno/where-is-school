# 术语表：游戏文字用词、玩家称呼、代码 id 与 autoload 对照

> **状态：** 现行
> **最后核对：** 2026-11-11（第 19 轮：马棚院子、厕所外墙；第 16 轮：前操场、校门、小门）
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
| `front_yard` | 前操场 | Front yard | 第 16 轮新增：教学楼玻璃门外、校门以内的土操场，两边都是操场，没有马路；场景由 `tools/build_outdoor_locations.py` 生成 |
| `street` | 街上 | Street | 校门外的街；第 16 轮起只能从校门旁的小门出来，不再从教学楼直接到街上 |
| `residential` | 居民楼 | The flats | 几栋居民楼和楼间的居民院；不叫「小区」/ estate |
| `alley` | 小巷 | Alley | 居民楼后面，尽头是通往操场的栅栏门 |
| `playground` | 操场 | Playground | 旧文档写作 schoolyard；台词里英文多用 the yard |
| `laboratory` | —（无 `place.` 文案） | — | 尚不可达的开发切片 |
| `staff_office` | 办公室 | Staff office | 作者改稿用「办公室」（`place.staff_office`） |
| `restroom` | 厕所 | Restroom | 一楼 |
| `restroom_02` | 厕所（二楼） | Restroom (02) | |
| `restroom_03` | 厕所（三楼） | Restroom (03) | |
| `archive` | 档案室 | Archive | 走廊两端的附属房间之一 |
| `plan_room` | 图纸室 | Plan room | 同上 |
| `projection_room` | 投影教室 | Projection room | 同上；作者改稿用「投影教室」（`place.projection_room`） |
| `computer_room` | 计算机教室 | Computer lab | 同上 |
| `vacant_office` | 空办公室 | Empty staff room | 同上 |
| `principal_office` | 校长室 | Principal’s office | 同上 |

`objective.*` 是目标条文案的 locale 键，不是地点。地点与目标的对应写在 `locations.json` 的 `objective` 字段里，会随流程变化。

## 2. 游戏文字用词（台词与检视文字必须一致）

中英两份内容是同一结构的两种语言，所以一个物件在两边各只有一个名字。改写或新写台词时按这张表；表外的物件第一次出现时，在这里补一行。

| 中文 | 英文 | 不要再写 | 说明 |
|---|---|---|---|
| 器材棚 / 杂物室 | shed | 器材室、工具棚、小屋 | 操场边那间锁着的绿门小棚；作者在结尾卡（`end.slice.body`）里叫它「杂物室」，两种叫法都保留。第 20 轮起在操场东北角：紧贴集装箱西侧，背靠教学楼前的栅栏，门朝南对着球场（节点 `ShedBody`，检视 `pg_shed_door`） |
| 操场 | yard / playground | 场子 | 整块场地；`place.playground` 是 Playground |
| 球场 | court | 院子、院里 | 地上画了白线、两头有篮筐的那一块 |
| 水泥地 | concrete | 土地、泥地（指操场地面时） | 第 20 轮：球场以外的操场地面全是浅灰的大方块水泥板；球场本身是更粗粝的水泥 |
| 仙人掌 | the cactus / saguaro | 仙人柱、树 | 第 20 轮：操场西边空地上，水泥地里突然出现的一块方形土地（节点 `CactusPlot`）里那棵巨大的柱形仙人掌（`CactusPlot/Saguaro`）。目前没有检视或台词（待做） |
| 跳绳的小女孩 | the girl with the skipping rope | 小姑娘、女孩子 | 第 20 轮：站在仙人掌旁边、背对镜头跳绳的小女孩，白裙、盘发（`CactusPlot/Girl`）。没有碰撞、没有对话；是否让她出现在台词里由作者决定（待做） |
| 居民院 | courtyard | 院子（指居民楼时） | 居民楼之间的院子 |
| 居民楼 | the flats | 小区、estate | 也用于「居民楼后面的空地」 |
| 走廊 | corridor | walkway | |
| 生物课本 | textbook / biology textbook | 生物书 | 主角书包里缺的那本；Q 的口语里说「生物书」保留 |
| 铁门 / 小铁门 | metal gate / the small gate | | 作者改稿（06）：巷子尽头通往球场、学生平时进出的那扇小门（`alley_to_playground`）；`objective.alley`「尽头有一道小铁门」 |
| 栅栏门 / 铁栅门 | alley gate | estate gate | 作者改稿（06）：小铁门旁边那扇更大的伸缩式栅栏门，几乎从不对学生开放 |
| 防火门 | fire door | | 操场回教学楼的门，与「小铁门」不同 |
| 前操场 | front yard | 前院、院子、校园 | 第 16 轮：教学楼正门（玻璃门）外到校门之间的土操场（`front_yard`）；与后面的「操场」（`playground`）是两个地点 |
| 校门 | school gate | 大门（单说时）、正门 | 前操场通往街上的那道门洞：一扇伸缩门加旁边一扇小门。「出校门」（`prompt.out_gate`）指从小门出去 |
| 伸缩门 | retractable gate | 推拉门、闸门、栅栏门（指校门时） | 校门那扇停车场式的电动伸缩门，铝格子折叠、带机头和轨道，平时关着、不能走。场景节点 `RetractableGate`（网格 `stage_art/meshes/retractable_gate_*.tres`）；检视 `front_yard_gate`。与小巷尽头的「栅栏门」是两扇门 |
| 小门 / 刷卡小门 | side door | 侧门、小铁门（指校门时） | 伸缩门旁边只容一个人过的小门，平时开着，不用刷卡也能过。场景节点 `SideDoor`；前操场出口 `front_yard_to_street`，街上回来是 `street_back_to_school`。与小巷的「小铁门」不同 |
| 刷卡机 | card reader | 打卡机、门禁 | 小门里面（前操场一侧）立柱上的刷卡机，只能看（`front_yard_card_reader`），不刷也能过 |
| 枯树 | dead tree | 死树、秃树 | 前操场上没有叶子的干树，靠校门的几棵从街上隔墙也看得到；检视 `front_yard_dead_tree` |
| 马棚 / 马棚院子 | stable / stable yard | 马厩、牲口棚、农家院 | 考试梦里一楼玻璃门西边那条小路尽头的院子（`DreamAnnex/StableYard`）：马棚、鸡窝、晾被子的绳、两个干活的老太太（一个筛谷子，一个耙谷子）；第 19 轮起地面是和操场一样起伏的土 |
| 厕所外墙 | the restroom's outside wall | 厕所后墙、卫生间外墙 | 第 19 轮：一楼厕所（`restroom`）在走廊西头那道墙后面，它的外墙就挨着马棚院子东边和小路北边，有高处的磨砂小窗、排风口和落水管（`TeachingBlock/GroundFloor/RestroomExterior`）；只是外观，不能从外面进 |
| 围墙 | school wall | 校墙（新写时） | 校门两边的砖墙，把前操场和街隔开；街那一侧有墙裙（`SchoolWallDado`）。旧台词里的「校墙」保留不改 |
| 栏杆 | railing | 栅栏（指前操场时） | 前操场南北两头的铁栏杆（`NorthRail` / `SouthRail`），挡路但看得过去 |
| 上锁的门 | locked door | 后门、service door | 作者定名（第 7 轮）：小巷里挂着坏 U 形锁的那扇（`alley_service_door` / `alley_door`）。只改检视标题；检视正文和日志记录仍按作者原句写「铁门」，不与「小铁门」混用 |
| 交还牌 | return plate | | 街边、巷口的小牌子 |
| 交还板 | return board | | 操场上那块板，与交还牌是不同物件 |
| 篮筐 | hoop | | 与「篮板」（backboard）不同 |
| 建造中的大楼 | the building under construction | 工地大楼、新楼、在建楼 | 操场西南角外的工地：蓝色施工挡板、紧闭的校门、门前两三座中空沙堆、黄色挖掘机、一层层椭圆楼板。以后会写成「椭球大楼」（the ellipsoid building）；在那之前台词里不要提前用这个名字。场景节点 `PlaygroundArt/BuildingSite`（`construction_site.tscn`，网格在 `meshes/site/*.tres`）；楼里是单独的地点 `site_interior`（从门廊的门进去） |
| 集装箱堆场 | the container yard | 集装箱场、堆场、货柜场 | 操场那只蓝色集装箱后面，铁丝网被剪开、往里翻起的地方钻过去。像停车场，蓝色红色（极少橙色）的集装箱一到三层高，从上往下看是迷宫；卡车轮胎垒成台阶，箱顶之间搭着会晃的长木板。单独的地点 `container_yard`（`tools/build_container_yard.py`）；停在空地上的卡车，箱子开往码头，爬进去就到港口 |
| 港口 | the port | 码头、海港 | 爬进堆场卡车上那只开往码头的货柜到这里。世界的边缘：混凝土码头，伸进海里的窄栈桥，水面是铺平的天空（不受光，只映出傍晚的天和云，慢慢晃）；岸桥吊着一只货柜，靠岸的货船，等着装船的集装箱。单独的地点 `port`（`tools/build_port.py`） |

## 3. 人物、内心声音与知识徽章

| 说话人 id | 中文名 | 英文名 | 是谁 |
|---|---|---|---|
| `protagonist` | 你 | You | 以学生身份回到学校的成年人。叙述用第二人称，**游戏没有独立的旁白角色**：旁白就是主角说话人下的 `observed` 或 `recalled` 文字。故事文档里写作「旁白」，导入时仍是 `protagonist` |
| `q` | Q | Q | 同学。话多、自来熟，好像很熟悉主角；主角不记得他 |
| `b` | B | B | 生物老师。序章缺席，只出现在想象与他人转述里 |
| `n` | N | N | 年轻的代课老师，最后宣布自习 |
| `student` | 同学 | Classmate | 无名的其他学生 |
| `voice_insight` | 洞察 | Insight | 言外之意、矛盾与动机假说，不是导航 |
| `voice_scrutiny` | 细察 | Scrutiny | 观察、细节与证据；窗帘细节等归此 |
| `voice_echo` | 回声 | Echo | 记忆、经验与联想；检定不把记忆变成事实 |
| `voice_imagination` | 臆想 | Imagination | 想象、潜意识与推测性联想；主观会话唯一可用的检定能力 |
| `voice_inference` | 推演 | Inference | 逻辑分析、推理与因果 |
| `voice_resonance` | 共鸣 | Resonance | 情绪、共情与人际信号；已注册，暂无合适的现有检定文案 |

**内心声音：** [叙事圣经](NARRATIVE_BIBLE.md#inner-voices)确定的六声部均已注册，暂定基础值都为 3。19 个既有检定按行为语义分配，而非统一改成洞察；旧 `orientation`／`whimsy` 不再是有效的注册能力，幻想检定归入 `imagination`，不另增第七项。旧节点 `e3_whimsy` 和被动规则的 `*_orientation` 是稳定存档键，故保留拼写；兼容层只更新已知旧检定的归属，不重掷或重算结果。成长、人格与新增台词尚未实现，见[内容契约](../data/dialogue_schema/README.md#six-voice-registry-and-reviewed-attempts-280)。

**知识来源与徽章：**

| Source | 中文徽章 | 英文徽章 | 能否变成世界状态 |
|---|---|---|---|
| `observed` | 亲眼所见 | SEEN | 能 |
| `reported` | 听人说的 | HEARD | 能 |
| `recalled` | 记忆里的 | REMEMBERED | 能 |
| `imagined` | 想象中的 | IMAGINED | **永远不能** |

## 4. 内容文件：章节

`data/dialogue/<locale>/<章节>.json` 共 8 章，`data/inspections/<locale>/<地点>.json` 共 21 份（按位置 id 命名）。对话章节与地点不是一一对应：

| 章节 | 内容 |
|---|---|
| `prologue` | 教室里的全部会话：Q、N、点名、窗帘异常、跌落 |
| `corridor` | 走廊里的喇叭、推车、等待、楼层表 |
| `school_annexes` | 走廊两端六个附属房间的对齐会话 `align_*` |
| `street` | 到达街上、校墙、告示、同学 |
| `residential` | 到达居民楼、楼梯、绿色动物 |
| `alley` | 到达小巷 |
| `playground` | 到达操场、器材棚、球 |
| `inner_voice` | 洞察、推演与细察的三个既有被动开口 `voice_*` |

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
| **step** | 序章的一步（`wake`、`q_wake`、`expectation`、`bag`、`bell`、`substitute`；第 7 轮起想象场景在 Q 的对话里选择进入，排在翻书包之前），每步由一个 flag 证明已完成，读档从第一个未完成的步继续。 | `scripts/world/prologue_steps.gd` |
| **Source** | 一条知识的来路，见第 3 节徽章表。 | `data/dialogue_schema/README.md` |
| **subjective** | 主观会话（想象、回忆）：不能设 flag、不能有 `once` 选项，只能记录 `recalled` / `imagined`；检定只允许「臆想」（`imagination`），其余能力的检定一律拒绝。 | 同上 |
| **恍惚 / 拼贴滤镜** | 序章摔伤（`curtain_landing_injured`）落到集装箱顶那一刻起的画面风格：静止的后现代拼贴，约四分钟游戏时间内淡出（先快后慢）；从集装箱顶跳下会再摔一次、滤镜更重；操场水龙头喝一口减轻三分之一，洗脸立刻清醒。`concussion_seconds_left` 记剩余秒数。只是美术，不晃不动。 | [CONCUSSION_VIEW.md](CONCUSSION_VIEW.md) |
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
