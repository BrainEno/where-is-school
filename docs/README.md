# 文档索引与状态

> **状态：** 现行
> **最后核对：** 2026-11-20（仅核对索引、状态元数据与相对链接；不等于逐页内容或实机验收）
> **负责人：** 文档 Agent；改动任一 `docs/**/*.md` 的 PR 作者必须同步本页与相关状态
> **取代者：** 旧评审索引已归档到 [archive/full-code-review.md](archive/full-code-review.md)

本页是 `docs/` 的唯一集中索引。`AGENTS.md` 仍是仓库指令入口，[AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) 定义协作规则，[MODULE_INDEX.md](MODULE_INDEX.md) 索引全局 `class_name` 类型。判断某份文档是不是现状时先读本页的状态与取代者；不要把实现笔记、迁移记录或历史审计当成现行合同。

状态取值：`现行`、`阅读副本`、`历史记录`、`历史/归档`、`提案/待所有者`、`实验`、`证据/记录`、`目录/索引`。`最后核对` 是索引元数据复核日期，不代表文档内容已经重新实机验证。`负责人` 使用角色而非个人姓名；谁改动文档，谁负责同步索引和状态。

`docs/archive/` 只迁入没有外部路径引用的过期评审报告。已完成的实现笔记与迁移记录保留原路径，因为根 `README.md`、[ASSET_PIPELINE.md](ASSET_PIPELINE.md)、工具与测试仍引用这些路径；它们由 [archive/README.md](archive/README.md) 列出，并在下表标记为 `历史记录`，即“虚拟归档”，避免为了整理而制造断链。

<!-- docs-index:start -->
| 文档 | 用途 | 状态 | 负责人 | 最后核对 | 取代者 / 说明 |
|---|---|---|---|---|---|
| [README.md](README.md) | 文档、状态与归档的唯一集中索引 | 目录/索引 | 文档 Agent | 2026-11-17 | 本页；[AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) 指向此处 |
| [archive/README.md](archive/README.md) | 历史文档与虚拟归档清单 | 历史/归档 | 文档 Agent | 2026-11-17 | 列出保留原路径的历史记录；见 [README.md](README.md) |
| [archive/full-code-review.md](archive/full-code-review.md) | 评审报告的历史仓库侧索引 | 历史/归档 | 文档 Agent | 2026-11-17 | 由 [README.md](README.md)、[MODULE_INDEX.md](MODULE_INDEX.md) 与 [ADR 0004](adr/0004-art-direction.md) 取代；基线 f027f35 |
| [AGENT_EVALUATION.md](AGENT_EVALUATION.md) | 编码 Agent 的公平比较与选型协议 | 现行 | 仓库所有者 | 2026-11-17 | 与 [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) 配套使用 |
| [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) | 强制协作、证据与合并边界规则 | 现行 | 仓库所有者 | 2026-11-17 | 唯一入口是 [AGENTS.md](../AGENTS.md)；文档状态入口是本页 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 运行时模块边界与交互规则 | 现行 | 工程 Agent | 2026-11-18 | 全局类型见 [MODULE_INDEX.md](MODULE_INDEX.md)，离线诊断见 §7c |
| [ART_BIBLE.md](ART_BIBLE.md) | 英文美术方向源文档 | 现行 | 仓库所有者 | 2026-11-18 | 中文阅读副本为 [ART_BIBLE.zh-CN.md](ART_BIBLE.zh-CN.md) |
| [ART_BIBLE.zh-CN.md](ART_BIBLE.zh-CN.md) | 美术方向中文阅读副本 | 阅读副本 | 内容/美术 Agent | 2026-11-18 | 与 [ART_BIBLE.md](ART_BIBLE.md) 同步 |
| [ASSET_LICENSE_AUDIT.md](ASSET_LICENSE_AUDIT.md) | 角色、肖像与第三方动画资产发行审计 | 证据/记录 | 仓库所有者 | 2026-11-17 | 含 #308 现用三张肖像的出处与发行边界；是证据台账而非许可证明，见 [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md) |
| [ASSET_PIPELINE.md](ASSET_PIPELINE.md) | 资产导入、Godot UID 与干净导入检查的合同 | 现行 | 工程 Agent | 2026-11-18 | §1 记本仓原生顶点色居民与导入模型的区别，§7 记录 UID 侧车和共享导入步骤，§10.2b 同步 N／学生几何修订合同 |
| [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md) | 资产来源与权利证据台账 | 现行 | 仓库所有者 | 2026-11-18 | 发行审计见 [ASSET_LICENSE_AUDIT.md](ASSET_LICENSE_AUDIT.md)；含 #308 现用肖像出处，以及教室帆布书包、操场集装箱铺盖与球场道具的第一方来源；记录不等于权利放行或美术批准 |
| [BIOLOGY_CLASSROOM_EXPERIMENT.md](BIOLOGY_CLASSROOM_EXPERIMENT.md) | 生物教室开发实验说明 | 实验 | 工程 Agent | 2026-11-17 | 开发专用且不导出；同类实验见 [VISUAL_EXPERIMENTS.md](VISUAL_EXPERIMENTS.md) |
| [CHARACTER_ANIMATION.md](CHARACTER_ANIMATION.md) | 角色动画资产、重定向与集成说明 | 现行 | 工程/美术 Agent | 2026-11-18 | 含教室座位接触、起坐、翻包与主角步行摆幅；角色集成参见 [CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md) |
| [CHARACTER_ART.md](CHARACTER_ART.md) | 角色外观与肖像方向 | 现行 | 仓库所有者 | 2026-11-17 | 动画说明见 [CHARACTER_ANIMATION.md](CHARACTER_ANIMATION.md) |
| [CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md) | 角色外观集成工程记录 | 现行 | 工程/美术 Agent | 2026-11-18 | 中文阅读副本为 [CHARACTER_INTEGRATION.zh-CN.md](CHARACTER_INTEGRATION.zh-CN.md)；§§9–12 说明 N／学生几何、全员头部精修与主角步态，对照待所有者验收 |
| [CHARACTER_INTEGRATION.zh-CN.md](CHARACTER_INTEGRATION.zh-CN.md) | 角色集成中文阅读副本 | 阅读副本 | 内容/美术 Agent | 2026-11-18 | 与 [CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md) §§9–12 几何修订同步，不独立声称获批 |
| [CONCUSSION_VIEW.md](CONCUSSION_VIEW.md) | 序章摔伤后的“恍惚”画面：静止的后现代拼贴滤镜，落地最强、十分钟游戏时间内淡出 | 实验 | 实现 PR 作者 | 2026-11-21 | 只做美术；检查见 `tests/concussion_view_test.gd` 与 `concussion-view-capture.yml` |
| [CONCEPT_DIRECTION.md](CONCEPT_DIRECTION.md) | 英文概念方向源文档 | 现行 | 仓库所有者 | 2026-11-17 | 中文阅读副本为 [CONCEPT_DIRECTION.zh-CN.md](CONCEPT_DIRECTION.zh-CN.md) |
| [CONCEPT_DIRECTION.zh-CN.md](CONCEPT_DIRECTION.zh-CN.md) | 概念方向中文阅读副本 | 阅读副本 | 内容/美术 Agent | 2026-11-17 | 与 [CONCEPT_DIRECTION.md](CONCEPT_DIRECTION.md) 同步 |
| [CORRIDOR_ART.md](CORRIDOR_ART.md) | 三层教学楼、走廊与两端房间的美术与路线 | 现行 | 实现 PR 作者 | 2026-11-20 | 共用舞台规则见 `tests/location_art_test.gd`；考试梦叠加层见 [EXAM_DREAM_ART.md](EXAM_DREAM_ART.md)；同类改造见 [PROLOGUE_ART_MIGRATION.md](PROLOGUE_ART_MIGRATION.md) |
| [EXAM_DREAM_ART.md](EXAM_DREAM_ART.md) | 考试梦实验层：扶梯、售票处、03 考场/候考室与 01 后的马棚院子 | 实验 | 实现 PR 作者 | 2026-11-20 | 生成器 `tools/build_dream_annex.py`；只加不改，检查见 `tests/dream_annex_test.gd` |
| [GLOSSARY.md](GLOSSARY.md) | 术语表：游戏文字用词、17 个地点 id ↔ 中英地名、人物与徽章、对话章节、10 个 autoload | 现行 | 文档 Agent | 2026-11-19 | 台词用词以本表为准（器材棚、居民楼、球场等）；规则本身见 [ARCHITECTURE.md](ARCHITECTURE.md) |
| [IMAGINED_LESSON.md](IMAGINED_LESSON.md) | 序章想象场景：B 的变形模型、残影与蒙克波浪滤镜 | 实验 | 实现 PR 作者 | 2026-11-21 | 美术已做；第 7 轮加了审问骨架（每句 B 的问话三个方向、2–4 轮占位、异想天开检定），文案待作者；检查见 `tests/imagined_lesson_test.gd` |
| [IMPLEMENTATION_NOTES_BUILD.md](IMPLEMENTATION_NOTES_BUILD.md) | 导出与字体子集化实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行发布流程见 [RELEASE.md](RELEASE.md) 与 [README.md](../README.md) |
| [IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md](IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md) | 走廊模型落地实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行资产台账见 [MODEL_LIBRARY.md](MODEL_LIBRARY.md) |
| [IMPLEMENTATION_NOTES_DISPLAY_INPUT.zh-CN.md](IMPLEMENTATION_NOTES_DISPLAY_INPUT.zh-CN.md) | 显示与输入提示适配实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 唯一无英文配对的实现笔记；现行边界见 [ARCHITECTURE.md](ARCHITECTURE.md) |
| [IMPLEMENTATION_NOTES_FREE_PERIOD.md](IMPLEMENTATION_NOTES_FREE_PERIOD.md) | 自由活动与同伴路线实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行叙事约束见 [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md) |
| [IMPLEMENTATION_NOTES_IMPORTED_MODELS.md](IMPLEMENTATION_NOTES_IMPORTED_MODELS.md) | 导入生产模型实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行合同见 [ASSET_PIPELINE.md](ASSET_PIPELINE.md) |
| [IMPLEMENTATION_NOTES_LABORATORY.md](IMPLEMENTATION_NOTES_LABORATORY.md) | 实验室独立切片实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行地图规划见 [MAP_PLAN.md](MAP_PLAN.md) |
| [IMPLEMENTATION_NOTES_NAVIGATION.md](IMPLEMENTATION_NOTES_NAVIGATION.md) | 鼠标导航与自动交互实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行规则见 [ARCHITECTURE.md](ARCHITECTURE.md) §5f |
| [IMPLEMENTATION_NOTES_OPENING.md](IMPLEMENTATION_NOTES_OPENING.md) | 生物课序章实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行验收见 [PROTOTYPE_BRIEF.md](PROTOTYPE_BRIEF.md) |
| [IMPLEMENTATION_NOTES_PLAYGROUND.md](IMPLEMENTATION_NOTES_PLAYGROUND.md) | 操场与内心声音实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行叙事约束见 [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md) |
| [IMPLEMENTATION_NOTES_PROPS.md](IMPLEMENTATION_NOTES_PROPS.md) | 长椅与书包道具实现笔记 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行来源台账见 [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md) |
| [MAP_PLAN.md](MAP_PLAN.md) | 学校及周边地图规划英文源 | 现行 | 仓库所有者 | 2026-11-18 | 中文阅读副本为 [MAP_PLAN.zh-CN.md](MAP_PLAN.zh-CN.md) |
| [MAP_PLAN.zh-CN.md](MAP_PLAN.zh-CN.md) | 地图规划中文阅读副本 | 阅读副本 | 内容 Agent | 2026-11-17 | 与 [MAP_PLAN.md](MAP_PLAN.md) 同步 |
| [MODEL_LIBRARY.md](MODEL_LIBRARY.md) | 可复用模型库与放置状态台账 | 现行 | 工程 Agent | 2026-11-18 | 导入合同见 [ASSET_PIPELINE.md](ASSET_PIPELINE.md)；记录当前角色几何计数，旧审计仍为历史记录 |
| [MOBILE_BUILDS.md](MOBILE_BUILDS.md) | 原生移动构建、签名与设备验收 | 现行 | 工程 Agent | 2026-11-18 | 独立按需 APK/IPA 工作流、Mac 模拟器与 Windows ADB 调试；桌面发布见 [RELEASE.md](RELEASE.md) |
| [MODULE_INDEX.md](MODULE_INDEX.md) | 全局 class_name 公共类型索引 | 目录/索引 | 文档 Agent | 2026-11-18 | 开发前按 [AGENTS.md](../AGENTS.md) 要求读取 |
| [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md) | 游戏面向叙事约束 | 现行 | 仓库所有者 | 2026-11-17 | 产品范围见 [PRODUCT_BRIEF.md](PRODUCT_BRIEF.md) |
| [NARRATIVE_GAMEPLAY_REVIEW.zh-CN.md](NARRATIVE_GAMEPLAY_REVIEW.zh-CN.md) | 剧情玩法评审、双语小试与回访切片 | 提案/待所有者 | 仓库所有者 | 2026-11-18 | 原基线 `76c5e77`，审计补核 `b8524c6` / `e143990`；不取代 [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md) 或 [ARCHITECTURE.md](ARCHITECTURE.md) |
| [OFFICE_ARCHIVE_ART.md](OFFICE_ARCHIVE_ART.md) | 环境美术实验第二轮：03 办公室后现代家具与档案室（学生档案、学校规章、检查卷宗的隐喻） | 实验 | 实现 PR 作者 | 2026-11-20 | 生成器 `tools/postmodern_office.py`、`tools/registry_archive.py`；检查见 `tests/office_archive_dressing_test.py`；第一轮见 [EXAM_DREAM_ART.md](EXAM_DREAM_ART.md) |
| [OFFLINE_DIAGNOSTICS.md](OFFLINE_DIAGNOSTICS.md) | 离线事件审计、导出隐私及开发验证 | 现行 | 工程 Agent | 2026-11-18 | 运行时边界见 [ARCHITECTURE.md](ARCHITECTURE.md) §7c |
| [PLAYTEST_CHECKLIST.md](PLAYTEST_CHECKLIST.md) | 所有者人工试玩验收清单 | 现行 | 仓库所有者 | 2026-11-17 | 发布流程见 [RELEASE.md](RELEASE.md) |
| [PRODUCT_BRIEF.md](PRODUCT_BRIEF.md) | 产品意图与范围 | 现行 | 仓库所有者 | 2026-11-17 | 叙事约束见 [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md) |
| [PROLOGUE_ART_MIGRATION.md](PROLOGUE_ART_MIGRATION.md) | 序章美术迁移与证据记录 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行截图证据说明见 [screenshots/README.md](screenshots/README.md) |
| [PROLOGUE_DESIGN_SUPPLEMENT.zh-CN.md](PROLOGUE_DESIGN_SUPPLEMENT.zh-CN.md) | 生物老师 B 的主观幻想、异想天开、交织分支与人物刻板印象设计补充 | 提案/待所有者 | 仓库所有者 | 2026-11-21 | 不取代 [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md)；具体作者文本留白，待后续定稿 |
| [PROTOTYPE_BRIEF.md](PROTOTYPE_BRIEF.md) | 首个可玩垂直切片验收范围 | 现行 | 仓库所有者 | 2026-11-17 | 人工验收见 [PLAYTEST_CHECKLIST.md](PLAYTEST_CHECKLIST.md) |
| [Q_MODEL_MIGRATION.md](Q_MODEL_MIGRATION.md) | Q 正式模型迁移记录 | 历史记录 | 实现 PR 作者 | 2026-11-17 | 现行来源台账见 [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md) |
| [RELEASE.md](RELEASE.md) | 双平台发布与导出验证流程 | 现行 | 工程 Agent | 2026-11-18 | 发行审计见 [ASSET_LICENSE_AUDIT.md](ASSET_LICENSE_AUDIT.md) |
| [STORY_DOCS.zh-CN.md](STORY_DOCS.zh-CN.md) | 故事文档（台本）格式与 Google 文档往返流程 | 现行 | 内容 Agent | 2026-11-19 | 工具 `tools/story_doc.py`；内容契约见 [data/dialogue_schema/README.md](../data/dialogue_schema/README.md) |
| [TECHNICAL_ROADMAP.md](TECHNICAL_ROADMAP.md) | 技术路线与阶段计划 | 现行 | 工程 Agent | 2026-11-17 | 运行时边界见 [ARCHITECTURE.md](ARCHITECTURE.md) |
| [VISUAL_EXPERIMENTS.md](VISUAL_EXPERIMENTS.md) | 视觉实验开发场景说明 | 实验 | 工程 Agent | 2026-11-17 | 开发专用；同类实验见 [BIOLOGY_CLASSROOM_EXPERIMENT.md](BIOLOGY_CLASSROOM_EXPERIMENT.md) |
| [adr/README.md](adr/README.md) | 架构决策记录索引 | 目录/索引 | 文档 Agent | 2026-11-17 | ADR 文件路径是编号权威；见 [README.md](README.md) |
| [adr/0001-engine-and-rendering.md](adr/0001-engine-and-rendering.md) | ADR 0001：引擎、语言与渲染器 | 现行 | 仓库所有者 | 2026-11-17 | 已接受；状态见 [adr/README.md](adr/README.md) |
| [adr/0002-dialogue-and-narrative-state.md](adr/0002-dialogue-and-narrative-state.md) | ADR 0002：对话层与叙事知识状态 | 现行 | 仓库所有者 | 2026-11-17 | 已接受；状态见 [adr/README.md](adr/README.md) |
| [adr/0003-inner-abilities-and-checks.md](adr/0003-inner-abilities-and-checks.md) | ADR 0003：内心声音与骰子检定提案 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 未接受；状态见 [adr/README.md](adr/README.md) |
| [adr/0004-art-direction.md](adr/0004-art-direction.md) | ADR 0004：美术方向、空间逻辑与相机 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 方向已确认但相机细节仍开放；状态见 [adr/README.md](adr/README.md) |
| [adr/0005-saves.md](adr/0005-saves.md) | ADR 0005：存档格式、版本与恢复策略 | 现行 | 仓库所有者 | 2026-11-17 | 已接受；状态见 [adr/README.md](adr/README.md) |
| [adr/0006-painterly-rendering.md](adr/0006-painterly-rendering.md) | ADR 0006：绘画感渲染原型提案 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 实现与检查已落地但所有者采纳未决；状态见 [adr/README.md](adr/README.md) |
| [adr/0007-large-binaries-and-repository-size.md](adr/0007-large-binaries-and-repository-size.md) | ADR 0007：大文件与仓库体积规则提案 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 规则与检查已落地但历史重写需所有者授权；状态见 [adr/README.md](adr/README.md) |
| [scene_proposals/README.zh-CN.md](scene_proposals/README.zh-CN.md) | 三个场景提案的立项目录 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 不是实现；范围见 [PRODUCT_BRIEF.md](PRODUCT_BRIEF.md) |
| [scene_proposals/01_thirteenth_chair.zh-CN.md](scene_proposals/01_thirteenth_chair.zh-CN.md) | 场景提案：第十三把椅子 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 未实现；开工需所有者批准与 [ADR 0004](adr/0004-art-direction.md) |
| [scene_proposals/02_room_2_3.zh-CN.md](scene_proposals/02_room_2_3.zh-CN.md) | 场景提案：2-3 教室 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 未实现；开工需所有者批准与 [ADR 0004](adr/0004-art-direction.md) |
| [scene_proposals/03_through_the_picture.zh-CN.md](scene_proposals/03_through_the_picture.zh-CN.md) | 场景提案：穿过画 | 提案/待所有者 | 仓库所有者 | 2026-11-17 | 未实现；开工需新 ADR 与所有者批准 |
| [screenshots/PLAYTHROUGH.md](screenshots/PLAYTHROUGH.md) | 历史通关截图索引 | 证据/记录 | 证据 Agent | 2026-11-17 | 历史画面；以 [screenshots/README.md](screenshots/README.md) 与 MANIFEST.json 为准 |
| [screenshots/README.md](screenshots/README.md) | 截图证据与历史边界说明 | 目录/索引 | 证据 Agent | 2026-11-17 | 中文阅读副本为 [screenshots/README.zh-CN.md](screenshots/README.zh-CN.md) |
| [screenshots/README.zh-CN.md](screenshots/README.zh-CN.md) | 截图证据说明中文阅读副本 | 阅读副本 | 证据 Agent | 2026-11-17 | 与 [screenshots/README.md](screenshots/README.md) 同步 |
| [screenshots/classroom_art_review/README.md](screenshots/classroom_art_review/README.md) | 教室美术真实运行对照证据 | 证据/记录 | 证据 Agent | 2026-11-17 | 旧布局证据；现行验收以 CI artifact 与 [screenshots/README.md](screenshots/README.md) 为准 |
| [screenshots/classroom_art_review/logs/engine-noise-comparison.md](screenshots/classroom_art_review/logs/engine-noise-comparison.md) | 完整教室套件引擎噪声对照日志 | 证据/记录 | 证据 Agent | 2026-11-17 | 对照记录；边界见 [screenshots/README.md](screenshots/README.md) |
| [screenshots/map_art/README.md](screenshots/map_art/README.md) | 地点美术前后对照证据 | 证据/记录 | 证据 Agent | 2026-11-17 | 对照记录；边界见 [screenshots/README.md](screenshots/README.md) |
<!-- docs-index:end -->

## 维护规则

1. 新增、删除或移动 `docs/**/*.md` 时，必须在上面的索引表增删相应行；`python3 tools/check_docs_index.py --check` 会拒绝未索引文档、失效链接、缺失状态和过期 ADR 索引。
2. 过期文档优先迁入 `docs/archive/`，并在文件头写明状态、负责人、最后核对和取代者；若既有链接太多，可在 [archive/README.md](archive/README.md) 登记为虚拟归档，但索引行必须标记 `历史记录` 并在最后一列写明现行取代者。
3. 英文源文档与中文阅读副本要同步状态；中文副本只标 `阅读副本`，不单独声称自己是生产源。
4. 需要所有者决策的 ADR 与场景提案保持 `提案/待所有者`，不得因为代码已实现就冒充已批准。
5. 本页不复制文档正文，也不记录未经核实的数字；冲突时回到 [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) 的“报告冲突”规则。
