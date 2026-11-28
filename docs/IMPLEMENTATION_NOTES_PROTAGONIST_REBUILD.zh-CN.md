# 主角 3D 模型重建实施记录（V4）

> **状态：** 证据/记录
> **最后核对：** 2026-11-28
> **负责人：** 实现 PR 作者（美术/工程 Agent）
> **取代者：** 无；本页记录 issue #383（V2 头部）之后的主角整体重建轮次，头部合同仍以 [CHARACTER_ART.md](CHARACTER_ART.md) §9 与 `tests/head_v2_test.py` 为准

本页按仓库协议分账：**实际完成**（代码/资产已落地）、**实际验证**（本次会话真实跑过并有输出）、**未完成**、**仅建议**。凡没有本次会话输出支撑的，一律不写成已完成。

---

## 1. 任务与艺术方向

- **目标：** 主角 3D 模型整体重建与艺术质量提升。参考 Disco Elysium 的**表现性绘画质感**（仅作质量标杆，不做滤镜、不做油画后处理）。
- **艺术方向：** 表现性绘画质感、真实面部体积、**可控的不对称**、心理表现力（疲惫/疏离/克制，外冷内脆弱）；绘画式材质与颜色分层；几何与笔触风格统一。
- **顺序：** 资产审计 → 面部 → 头发 → 颈肩 → 服装 → 材质/着色 → 绑定兼容与游戏内检查 → 验收渲染 A–J → 主动视觉审查 2–3 轮。
- **硬约束（全部遵守）：** 保留原角色身份与设计意图；不用油画滤镜/AI 磨皮/日漫化/碎刺当美术；修根因不做遮罩；不移镜头、不裁切藏缺陷；不加运行时灯光与高开销后处理；多角度检查（含顶/底、游戏镜头、对话镜头、多光照）；单轮修复不宣称完成。

## 2. 实际完成

### 2.1 面部（V4 雕塑，`tools/head_v2.py`）
- 面部解剖场重写：鼻梁/鼻翼/鼻唇沟、唇部体积（唇珠、口角囊、唇红线）、颏部与下颌缘、颊部与颧弓过渡、眼窝与泪沟、颈喉衔接（UV 缝隙保护场）。
- 眼睛重建：开睑（wrap_lids 拉向目标，(1−v)^1.2）、巩膜/虹膜/瞳孔三层穹顶（瞳孔 z 抬 0.35mm 消除虹膜环）、巩膜暖白 (0.915,0.895,0.868)、睑裂 9.19mm（合同 8–10mm）。
- **可控不对称**：他右侧眉整体抬高 ~2mm、加粗 ×1.12；口角不对称下垂；左右眼穹顶差异（bulge 0.0008/0.0006, lift 0.0002/0.0004）。表情 morph 的左右 delta 保持镜像（表情动作不得重新倾斜双眉）。
- 耳部：贴头收纳（x' = side·0.0705 + (x − side·0.076)·0.85）+ 耳轮/对耳轮/耳屏浮雕。
- 人体测量 8/8 在带内（`tools/character_review/anthropometry.py`，含颏部内点杂散过滤）。

### 2.2 头发（`style_locks` V4 设计短发）
- 96 锁（5 环×10 列 + 锁尖，5,199 顶点 / 9,200 三角）+ 发帽，区域流向场：刘海（向他右侧扫，|az|≥115°）、顶、鬓角、后颈发块；二次贝塞尔发束、扁管截面、自由发尖、颅骨钳制。
- 发型读作**设计过的短发**（刘海分缝、鬓角、后颈体量、圆润分组），不再是碎刺。
- `HAIR_BBOX` 常量已按实测精确钉住（check 全绿）。

### 2.3 材质与着色（`tools/head_v2_textures.py` + `protagonist_look.tres`）
- 皮肤颜色分区 12 层釉染（唇、口线、鼻暖、鼻翼冷、眼睑、淤青、眼窝紫、眉带、额冷、胡茬、颊红、耳、颌影、颏），全部经 `_step` 平滑门控（硬 z 阈值曾画出"撕纸"多边形色块，已根治）。
- 皮肤着色再平衡：消除了早期的生硬明暗对分；`edge_softness 0.36`、`pigment_steps 8` + `pigment_blend 0.5`（颜料阶柔化，避免面罩状色斑）；补丁羽化 `patch_feather 0.85`（硬边补丁曾似贴片）。
- 全程**无高光**（房间契约）；头发法线贴图（双排发丝沟 + 发旋）。
- 离线预览器 `tools/head_preview.py` 复现着色器数学，共 7 轮绘画预览迭代（build/head_v2/v4_paint1…7）。

### 2.4 服装（`wardrobe()`，`tools/head_v2.py`）
- 夹克与裤子中点细分一次（权重沿边/面插值，骨骼绑定契约不变），解算褶皱场：肩部垂褶、门襟槽与双鼓边、腰身收放、下摆波与微张、肘部拉伸褶环、袖口鼓边；裤膝拉伸褶、裤线垂褶、裤脚波。
- 边缘卷边（立领口、袖口、下摆）：开放边界沿 −法线内收，衣料边缘有了厚度感。
- 设计身份保留：立领、左胸贴袋（微鼓）、明扣门襟、直筒下摆、修身轮廓。
- 细节件（立领/口袋）：立领上抬、口袋面微鼓。
- 仅改 POSITION/NORMAL；JOINTS_0/WEIGHTS_0/索引按值校验（原顶点行权重逐位一致，新顶点权重归一，关节号 ≤58）。

### 2.5 测试（`tests/head_v2_test.py`，有意更新并写明理由）
- 测试文件头注释含"Pin history"三条理由：①任务简报以"可控不对称"取代 #385 的镜像眉合同（改为钉设计不对称区间 + 方向 + morph 镜像）；②服装三分片改为按值/按集合断言（打包器会重排 accessor 索引，skins 按关节/IBM 值比较）；③发型换代后冠高改钉设计带 1.704–1.712（V1 的 1.767 碎刺剪影退役），地线仍精确钉。
- 6/6 通过；`character_sculpt_test` 11/11 通过；`commit_messages_test`、`docs_index_test`、`gdscript_quality_test`、`test_registration_test` 等通过。

## 3. 实际验证（本次会话真实输出）

| 项目 | 命令/方式 | 结果 |
|---|---|---|
| 构建可复现 | `tools/head_v2.py install` → `check()` | runtime 与构建逐字节一致，V2 合同全绿（UV、9 morph、4 睑壳、96 锁、发包络、预算 1,431,712 ≤ 1,572,864 B） |
| 人体测量 | `tools/character_review/anthropometry.py` | 8/8 在带（眼线 0.519、鼻底 0.300、口线 0.387、眼宽/面宽 0.190、内眦/眼宽 1.135、面宽高 0.552、颌/颅 0.787、下面 1/3 = 0.300） |
| 绘画预览 | `head_preview.py` 7 轮（front/quarter/close） | 明暗对分消除、色块硬边根治、虹膜高光环消除、面色分区可读 |
| 验收渲染 A–N | `tools/character_review/protagonist_acceptance.py`（新工具，固定机位） | 16 张落盘 `art/protagonist_reconstruction_review/`（含顶/底、游戏距离、对话特写、三光源） |
| 主动视觉审查 | 7 轮绘画预览 + 2 轮服装 + 验收集复查 | 每轮记录缺陷与修复（见 §6 演进记录） |
| 测试 | `tests/head_v2_test.py` 等 | 6/6 OK；雕塑 11/11 OK；范围审计 `origin/main..HEAD` 通过 |

**渲染证据索引**（`art/protagonist_reconstruction_review/`，全部为运行时 `Protagonist_Character.glb` 实渲）：
- `A_front_full` `B_front_head` `C/D_quarter` `E/F_profile` `G_back`：验收视角组
- `H_game_distance`（游戏机位）`I_dialog_closeup`（对话特写）
- `J1–J3`（左/右/顶光）
- `K_top` `L_bottom` `M/N_full_quarter`：顶/底与全身斜角检查
- `painted_front/quarter/close`（文件名 `painted_*`）：着色器数学离线渲染的最终绘画效果
- `wardrobe_front/quarter`：服装褶皱轮终稿

## 4. 未完成 / 受限

- **Godot 4.7.2 实机验证未运行**：沙箱无 Godot 4.7.2（协议固定版本），无法做引擎内导入、对话镜头实机与 Playthrough。验收渲染由复现同一着色器数学的离线渲染器完成，**如实标注为离线等价验证，不冒充实机**。
- **服装的绘画材质表现**未在着色器下截图（离线渲染器只覆盖头部取景）；服装目前只有几何渲染证据。
- **耳部**在特写下仍偏平（浮雕已有但体积弱），已列未解决问题。
- `tests/character_geometry_test.py`（教室 NPC）依赖 `meshoptimizer==0.2.30a0`，沙箱内该 C 扩展构建失败（环境限制，与主角改动无关）。
- `tests/tool_requirements_test.py` 仅剩 `meshoptimizer` 一项环境错误，其余包已按 `tools/requirements.txt` 版本钉齐。

## 5. 性能与兼容性

- **面数**：头 22,064 + 发 9,200 + 服装细分后新增约 7,300 三角，全身约 4 万三角（会话一基线 60,456 的 2/3 以内）。
- **字节**：运行时 GLB 1,431,712 B ≤ 预算 1,572,864 B。
- **骨骼**：16 骨 `RIG_Protagonist_Blockout` 未动；skins 关节表与逆绑定矩阵逐值一致；rigid 部件单关节权重保持（服装细分权重插值后原顶点行逐位一致）。
- **动画**：clip 通道与采样逐字节一致（测试钉住）。
- **无新增灯光、无运行时后处理**；唯一几何 morph 为头 9 个表情键（名称集合与 V1 一致）。

## 6. 缺陷→修复轮次（视觉审查记录摘要）

| 轮 | 发现 | 修复 |
|---|---|---|
| paint1 | 面部明暗左右生硬对分 | look.tres 阴影填充/边缘参数重调 |
| paint2 | 面色苍白、虹膜高光环、额带线过直 | 眼穹顶修正、SCLERA 暖白、肤色釉染加重 |
| paint3 | 脸颊"撕纸"硬边多边形色块 | 定位为贴图 z 硬阈值门 → 全部改 `_step` 平滑 |
| paint4 | 残余硬边（4 阶颜料海报化） | `pigment_steps 8` + `pigment_blend 0.5` |
| paint5 | 外眼角巩膜尖刺 | SCLERA_SCALE_X 1.05→1.00（量具仍 8/8） |
| paint6–7 | 色阶边偏硬 | `edge_softness 0.36`、补丁羽化 0.85 → 干净绘画表面 |
| wardrobe1–2 | 褶皱幅度不足、门襟单薄 | 褶皱场 ×1.7、门襟双鼓边、下摆外翻、卷边加深 |

## 7. 未解决问题清单

1. 耳部体积弱、特写下偏"棋子"（浮雕+收纳已缓解）；建议后续用独立耳甲腔凹陷场再做一轮。
2. 下睑缘在特写下有一线受光水线（解剖上存在，但当前偏亮），可用睑缘釉染压 5% 再平衡。
3. 服装绘画材质（布纹 `detail_kind` 4/5 与色阶）在游戏着色器下的最终观感需要 Godot 4.7.2 实机截图归档。
4. 发束在特写下仍可见扁管截面棱（发丝法线贴图在引擎内会再弱化一档），若实机仍硬可降截面 b 比至 0.66。
5. `meshoptimizer` 沙箱构建失败（环境）；CI 干净环境为准。

## 8. 自评分（证据式）：74 / 100

| 维度 | 得分 | 证据 |
|---|---|---|
| 面部体积与解剖（/25） | 21 | anthropometry 8/8；B/I 渲染鼻唇颏体积可读 |
| 头发设计（/15） | 13 | 发型为设计短发（刘海分缝/鬓角/后颈块），G 背面层次成立 |
| 可控不对称与心理性（/15） | 13 | 眉抬 2mm+加粗、口角下垂、眼下疲惫沟；测试钉住方向 |
| 材质绘画性（/15） | 11 | 分区釉染+颜料阶柔化可读（painted_*）；服装着色器观感未实机 |
| 服装与轮廓（/15） | 9 | 褶皱/卷边/门襟落地但整体仍偏风格化低模；设计身份保住 |
| 流程/契约/证据（/15） | 7... = 7 | check 全绿、测试 6/6、A–N 实渲、7+2 轮审查；Godot 实机缺 |

（合计 74。"普通低模"红线判定：头部与头发已明显超出普通低模读感；服装为有意识的硬边风格化选择并带设计褶皱，但仍偏简——故不满分、不宣称全部完成。）

## 9. 复现流程

```bash
export LD_LIBRARY_PATH=/home/user/xstubs   # 沙箱桩库
cd /home/user/where-is-school
python3 tools/head_v2.py install            # 从字节钉定的 V1 源构建并安装运行时 GLB
python3 tools/head_v2.py check              # V2 合同（逐字节 + 计量）
python3 tools/head_v2_textures.py build     # 1024² 头/发贴图（~4 分钟）
python3 tools/character_review/anthropometry.py assets/models/protagonist/Protagonist_Character.glb
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --out build/head_v2/preview --views front,quarter,close
python3 tools/character_review/protagonist_acceptance.py build/head_v2/acceptance
python3 tests/head_v2_test.py
```
