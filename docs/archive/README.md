# 历史文档归档

> **状态：** 历史/归档
> **最后核对：** 2026-11-17（索引、状态与相对链接）
> **负责人：** 文档 Agent
> **取代者：** [docs/README.md](../README.md) 是现行文档索引；[AGENTS.md](../../AGENTS.md) 是仓库指令入口

本目录保存不再代表当前 `main` 的评审材料，以及在原路径被大量引用、因而不能安全移动的历史实现与迁移记录。两种条目都不是现行合同；当前状态以 [docs/README.md](../README.md) 索引表为准。

## 已迁入的过期审计

- [full-code-review.md](full-code-review.md)：`f027f35` 基线的评审索引。已被 [docs/README.md](../README.md)、[MODULE_INDEX.md](../MODULE_INDEX.md) 与 [ADR 0004](../adr/0004-art-direction.md) 等现行文档取代；文件头明列失效结论。

## 保留原路径的虚拟归档

以下文件仍位于 `docs/`，因为根 [README.md](../../README.md)、[ASSET_PIPELINE.md](../ASSET_PIPELINE.md)、模型/资产台账与测试脚本直接引用其路径。移动它们会制造断链；因此仅在此登记为历史记录，不复制正文，也不改写旧链接。

- [IMPLEMENTATION_NOTES_BUILD.md](../IMPLEMENTATION_NOTES_BUILD.md)：构建与字体子集化；现行流程见 [RELEASE.md](../RELEASE.md)。
- [IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md](../IMPLEMENTATION_NOTES_CORRIDOR_PROPS.md)：走廊模型落地；现行台账见 [MODEL_LIBRARY.md](../MODEL_LIBRARY.md)。
- [IMPLEMENTATION_NOTES_DISPLAY_INPUT.zh-CN.md](../IMPLEMENTATION_NOTES_DISPLAY_INPUT.zh-CN.md)：显示与输入提示适配；现行边界见 [ARCHITECTURE.md](../ARCHITECTURE.md)。
- [IMPLEMENTATION_NOTES_FREE_PERIOD.md](../IMPLEMENTATION_NOTES_FREE_PERIOD.md)：自由活动与同伴路线；现行约束见 [NARRATIVE_BIBLE.md](../NARRATIVE_BIBLE.md)。
- [IMPLEMENTATION_NOTES_IMPORTED_MODELS.md](../IMPLEMENTATION_NOTES_IMPORTED_MODELS.md)：导入生产模型；现行合同见 [ASSET_PIPELINE.md](../ASSET_PIPELINE.md)。
- [IMPLEMENTATION_NOTES_LABORATORY.md](../IMPLEMENTATION_NOTES_LABORATORY.md)：实验室独立切片；现行规划见 [MAP_PLAN.md](../MAP_PLAN.md)。
- [IMPLEMENTATION_NOTES_NAVIGATION.md](../IMPLEMENTATION_NOTES_NAVIGATION.md)：鼠标导航与自动交互；现行规则见 [ARCHITECTURE.md](../ARCHITECTURE.md) §5f。
- [IMPLEMENTATION_NOTES_OPENING.md](../IMPLEMENTATION_NOTES_OPENING.md)：生物课序章；现行验收见 [PROTOTYPE_BRIEF.md](../PROTOTYPE_BRIEF.md)。
- [IMPLEMENTATION_NOTES_PLAYGROUND.md](../IMPLEMENTATION_NOTES_PLAYGROUND.md)：操场与内心声音；现行约束见 [NARRATIVE_BIBLE.md](../NARRATIVE_BIBLE.md)。
- [IMPLEMENTATION_NOTES_PROPS.md](../IMPLEMENTATION_NOTES_PROPS.md)：长椅与书包道具；现行台账见 [ASSET_PROVENANCE.md](../ASSET_PROVENANCE.md)。
- [PROLOGUE_ART_MIGRATION.md](../PROLOGUE_ART_MIGRATION.md)：序章美术迁移；现行证据说明见 [screenshots/README.md](../screenshots/README.md)。
- [Q_MODEL_MIGRATION.md](../Q_MODEL_MIGRATION.md)：Q 模型迁移；现行台账见 [ASSET_PROVENANCE.md](../ASSET_PROVENANCE.md)。

历史截图与证据目录（例如 [screenshots/PLAYTHROUGH.md](../screenshots/PLAYTHROUGH.md)）不移动：其相对链接和 `MANIFEST.json` 依赖原路径，边界由 [screenshots/README.md](../screenshots/README.md) 说明。
