# Architecture Decision Records

Record significant technical decisions here. Each record should include status, date, context, decision, consequences, and conditions for revisiting it. Do not use ADRs for ordinary implementation details.

> **状态：** 目录/索引
> **最后核对：** 2026-11-17（索引、状态与相对链接）
> **负责人：** 文档 Agent
> **取代者：** [docs/README.md](../README.md) 是全部文档的集中索引

文件名是 ADR 编号的权威来源；历史分支名（例如 `docs/adr-0003-six-inner-voices`）不参与编号判断。下表状态只摘录文件头的接受/提案边界；具体条件仍以各 ADR 正文为准。`python3 tools/check_docs_index.py --check` 会拒绝缺失 ADR 行、断链或缺少状态列的索引漂移。

<!-- adr-index:start -->
| 编号 / 记录 | 状态 | 最后核对 | 复核条件 |
|---|---|---|---|
| [0001 — Engine, Language, and Renderer](0001-engine-and-rendering.md) | 已接受 | 2026-11-17 | 引擎、语言或渲染器路线改变时 |
| [0002 — Dialogue Layer and Narrative Knowledge State](0002-dialogue-and-narrative-state.md) | 已接受 | 2026-11-17 | 对话系统或知识状态所有权改变时 |
| [0003 — Inner voices and dice checks](0003-inner-abilities-and-checks.md) | 提案 | 2026-11-17 | 所有者接受或拒绝多声音与检定设计时 |
| [0004 — Art direction, spatial logic, and camera](0004-art-direction.md) | 待所有者 | 2026-11-17 | 相机投影、环境路线或角色着色由所有者决定时 |
| [0005 — Save Format, Versioning and Restore Policy](0005-saves.md) | 已接受 | 2026-11-17 | 菜单、存档槽或恢复策略改变时 |
| [0006 — Painterly Rendering Prototype](0006-painterly-rendering.md) | 提案 | 2026-11-17 | Windows 视觉复核与所有者采纳决定完成时 |
| [0007 — Large binaries and repository size](0007-large-binaries-and-repository-size.md) | 提案 | 2026-11-17 | 历史重写获得所有者授权或运行时音乐结论改变时 |
<!-- adr-index:end -->

## 新增 ADR

1. 使用下一个未占用的四位编号，不要复用或删除既有编号。
2. 文件头写明 `Status`、`Date`、依赖、背景、决定、后果与重新讨论条件。
3. 在上表增加一行，并同步 [docs/README.md](../README.md) 的集中索引；不要只改本页。
