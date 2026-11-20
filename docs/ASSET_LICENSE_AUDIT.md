# 角色、肖像与第三方动画资产发行审计 — Issue #64 / #308

## 当前处置（#64 / #308）

- **UAL 从当前树退役，不是许可放行。** 正式角色的 wrapper 使用项目语义动作、角色动作配置及 Q/N 模型内置层；未引用 `UAL1_Standard.glb`、`protagonist_ual.res` 或其专用预览。经所有者确认可移除，删除原 GLB、导入侧车、派生库以及专用预览和 bake 工作流，保留仍受测试的自有开发骨架/预览和通用算法。Windows/Linux 与移动预设的开发目录排除不变；发行验证器仍拒绝已知 UAL 名称。普通删除不移除 Git 历史、既有克隆或历史 Actions artifact；未重新打包、分享独立 UAL 资源或裁定 CC0/QAL 的适用关系。
- **主角来源已补记。** [所有者书面确认](https://github.com/BrainEno/where-is-school/issues/64#issuecomment-6941291502)：现用主角是其本人用 Blender 和 Python 脚本制作，所有权归仓库作者。这是作者声明，不是由 GLB header 推断，也不替其他资产作权利证明。

### 现用对话肖像出处（#308）

[游戏作者对现用版本的确认记录](https://github.com/BrainEno/where-is-school/issues/308#issuecomment-7038464634)：主角、Q、N 均由游戏作者本人手绘，再由作者使用 ChatGPT 加工生成。现用 Q 是 [后续重绘 `35b4560`](https://github.com/BrainEno/where-is-school/commit/35b4560039914b0a57eec2666a3743b5138bb8da)，由本次确认直接覆盖，不沿用 #64 对旧图的声明。肖像与对应角色的 3D 模型是不同资产。

| 肖像 | 游戏供图（非未加工手绘原稿） | 游戏使用的文件 | 出处 |
|---|---|---|---|
| 主角 | `art/portraits/protagonist.png` | `assets/ui/portraits/protagonist.webp` | 游戏作者本人手绘，再由作者使用 ChatGPT 加工生成 |
| Q（现用重绘） | `art/portraits/q.png` | `assets/ui/portraits/q.webp` | 游戏作者本人手绘，再由作者使用 ChatGPT 加工生成 |
| N | `art/portraits/n.webp` | `assets/ui/portraits/n.webp` | 游戏作者本人手绘，再由作者使用 ChatGPT 加工生成 |

六个文件的 SHA-256 与下文 §3.3 相应条目一致，正式档案仍绑定到上述游戏文件；旧 Q 的裁切及旧图指纹仅供历史对照。逐图的现行条目见[来源台账](ASSET_PROVENANCE.md)。

**发行许可仍未核验。** 本次确认手绘作者和加工服务，不确认加工日期、ChatGPT 模型/版本、当时适用条款或输出权利。三张图的商用、修改、随游戏再分发、源图或宣传再分发、必要署名与 AI 披露仍须在发行前核验，未获放行。按所有者要求，在出处记录落到 `main` 后关闭 #308；关单不等于完成许可核验，不作为公开或商店发行批准。无法核明时仍须替换为权利清楚的版本或暂缓相应发行。

下文保留 #197 及后续快照的历史审计证据；其中“当前”“本 PR”及待答项以当时的范围为准，最新处置以上段为准。

## 1. 结论与边界

**这是证据台账与技术隔离审计，不是法律意见，也不是发行许可证明。**

- **公开/Steam 发行仍有阻塞：** 新主角 GLB 的作者、实际制作工具/流程和权利链未确认；三张肖像各自的生成服务、模型、适用条款与输出权利未确认。全部保留 **UNKNOWN / NOT CLEARED**，不因为文件由 Owner 上传、已有截图、能导出或 CI 通过而放行。
- **UAL 决定不变：RESTRICTED / DEVELOPMENT ONLY。** 原始库及 retarget/bake 派生动画都不进入游戏发行包；当前公开 CC0 标签与 QAL 的差异未被本 PR 裁定或消除。开发专用是项目处置，不代表内部使用和源码再分发已获法律确认。
- **已解决的子项不重新挂起：** Q 的 3D 模型与 16 个环境模型保留现有 Owner 确认记录。它们不证明新主角或任何肖像的来源。
- **技术补强不是权利门禁：** 本 PR 修复了预检与包验证器的真实绕过，并补充反例；仍不会自动阻止所有 UNKNOWN 资产被导出，不能拿绿色构建作商店发布批准。#64 必须继续开放，待补证或另行授权替换。

审计资产快照为 `e12205a9d5e1731de3d25a4f074c2a3e4ddd4efa`。平台最初起点为
`77fb79cc086ae0e77012bbe8b586b05b20f325f4`；发现 main 前移且台账重叠后，经 Owner 明确授权，
仅在当前固定分支安全快进到上述精确 SHA，保留实验室来源新增记录，没有换分支或改写历史。
本 PR 不修改资产字节、Blender 源、GLB、shader、动画、正式场景、肖像、对话 UI/内容、
DialogueController、ReadLog 或其他 Agent 的美术实验。

范围限于：四份 runtime 角色 GLB 的来源记录与 manifest、三肖像源/runtime/档案绑定、
`art/character_rig_audit/` 和 `art/character_rigging/` 的阶段说明、
`scenes/dev/animation_retarget_test/`、相关代码/导出预设/验证脚本/CI 工作流和交接文档。
字体与 Poly Haven 道具沿用原台账，不借本次审计宣布全仓已合规；没有读取私人手稿或私人云盘材料。

## 2. 状态与证据层级

| 标记 | 含义与边界 |
|---|---|
| `OWNER_CONFIRMED_RECORDED` | 仓库中有明确记述 Owner 确认的记录；本次接受 #64 对已解决子项的状态，不冒充新取得的签署声明 |
| `RECORDED_OWNER` | 已有交接记为 Owner 作品；本次仅核对记录/文件链，不据此升级为新的法律尽调结论 |
| `GENERATED / AI_DETAILS_UNKNOWN` | 供图记录称新生成；具体生成方式、AI 服务/模型、人工参与和上游输入仍未知，不能凭画风认平台 |
| `UNKNOWN / NOT CLEARED` | 缺足够来源/适用授权；不作商用、游戏再分发或源文件分享的许可承诺 |
| `RESTRICTED / DEV_ONLY` | 项目禁止生产发行；这不是某一许可版本已经确定适用或所有再分发面都已解决 |

证据分四类，不能互相替代：

1. **可靠的文件/技术证据：** SHA-256、GLB JSON、无外部 buffer/image URI 的检查、源码引用、历史差分、可重复转换和实际测试结果。它们证明“是什么/从哪个文件转换”，不证明“谁有权授权”。
2. **本次公开可核实：** 下列 UAL 包页/itch.io、QAL、CC0 原文与 Steamworks Content Survey 的当前公开内容。当前网页不是本项目取得素材当时的条款快照。
3. **Owner 必须提供：** 新主角创作来源与各肖像独立的服务/模型/制作日期、账户方案、输入素材权利、当时条款和输出许可。不能用提交人、Git 时间、exporter header 或别的资产的确认代填。
4. **需许可/法律专业判断：** CC0 与 QAL 对此下载副本的适用关系、生成输出在相关法域的保护/使用范围、第三方人物/素材权利与独立源码分发。必要时向原作者取得书面澄清；本报告不裁决。

## 3. 逐项资产审计表

“游戏再分发”包括在付费/免费游戏中随包提供；“独立再分发”包括原图、GLB、动画库、源码克隆与独立 artifact。
“允许”与“已查到某条记录”是不同结论。

| 资产与实际使用 | 来源分类 / 证据 | 实际制作工具（转换工具另列） | 商业使用 | 随游戏再分发 | 独立再分发 / 状态 |
|---|---|---|---|---|---|
| `assets/models/protagonist/Protagonist_Character.glb`，当前玩家 | Owner 提供，**不等于原创**；PR #118 明确保留作者待答；E2/E3 | **UNKNOWN**。header 只自报 glTF Blender exporter；不能反推完整制作工具、作者或 AI/第三方输入 | **UNKNOWN** | **UNKNOWN**；包括自带 mesh、骨架、9 个头部 blend shape、5 个嵌入动画 | **UNKNOWN / NOT CLEARED** |
| `art/portraits/protagonist.png` → `assets/ui/portraits/protagonist.webp` | Owner 供图，记录称新生成；`GENERATED / AI_DETAILS_UNKNOWN`；E4/E5 | 生成工具/服务/模型 **UNKNOWN**；转换为 Pillow 裁切、Lanczos 缩放、WebP 编码 | **UNKNOWN** | **UNKNOWN** | 原图与裁切版均 **UNKNOWN / NOT CLEARED** |
| `art/portraits/q.png` → `assets/ui/portraits/q.webp` | 2026-11 重绘，由本项目工作会话中的图像生成模型产出，Owner 审核后替换旧图；与 Q 的 3D 模型是不同作品；E4/E5 | 生成工具/服务/模型 **UNKNOWN**；转换同上 | **UNKNOWN** | **UNKNOWN** | **UNKNOWN / NOT CLEARED**；旧的 `q-picture.webp` 已不在库中 |
| `art/portraits/n.webp` → `assets/ui/portraits/n.webp` | 原供图名 `teacher-n.webp`；与 N 的 3D 模型是不同作品；E4/E5 | 生成工具/服务/模型 **UNKNOWN**；转换同上 | **UNKNOWN** | **UNKNOWN** | **UNKNOWN / NOT CLEARED** |
| `scenes/dev/animation_retarget_test/UAL1_Standard.glb` | 第三方 Quaternius；记录为 Standard/free；E7/P1–P4 | 文件自报 exporter `Khronos glTF Blender I/O v4.5.48`；取得版本/日期 **UNKNOWN** | 当前公开页面均允许一定范围商用，但**此副本适用授权仍未定**；项目不放行生产使用 | **项目禁止**，不能因 QAL 允许完成品而擅自改变决定 | 资产本身再分发有冲突；**RESTRICTED / DEV_ONLY** |
| 同目录 `protagonist_ual.res`，开发预览加载 | UAL 动作经 `tools/bake_animation_retarget.gd` 在目标骨架上重采样；E7/E8 | Godot / `AnimationRetarget.bake()`；脚本采样 30 fps。未在本轮重新 bake | 不因 retarget 获得新的独立许可 | **项目禁止**，包括转换格式或复制目录后 | 与上游相连；**RESTRICTED / DEV_ONLY** |
| `assets/models/q/new-Q.glb` 与 `art/character_models/q/new-Q_source.glb` | 本次迁移中 Owner 明确确认为 **ChatGPT 为本项目生成的原创 Q**，并批准正式使用；上传 commit `f9aa19d4fa8ad56b0e4d2e46c48c799d10ffbb42` | ChatGPT AI 生成；确切模型/版本未提供；`tools/prepare_q.py` 仅做可复现技术整理 | Owner 已明确批准本项目正式使用，不再次要求来源确认 | 本批准仅涵盖 Q 3D；不覆盖 Q 肖像、主角或其他未清理素材 | `OWNER_APPROVED_AI_ORIGINAL`；新 Q 不是旧 Q Blender/Python 制作链的延续；美术/变形签收另行，#64 保持开放 |
| `assets/models/protagonist/protagonist.glb`，现为坐姿学生 | 旧主角，已有 Owner 程序化 Blender 制作/导出记录；E6 | 记录为 Blender 5.2.3 LTS；本次未重新取得原始制作声明 | 沿用既有记录，不升级尽调等级 | 沿用既有记录 | `RECORDED_OWNER`；不能据此认定新玩家 GLB 为原创 |
| `assets/models/teacher-n/teacher-n.glb` 与 source | PR #130 记为 Owner Blender 作品；源 hash 与处理链可核；E6 | Blender（交接记录）；`prepare_teacher_n.py` 为优化工具，不是原始作者证明 | 沿用既有记录 | 沿用既有记录，含 N 自带 4 个 idle loops | `RECORDED_OWNER`；原图肖像不在该确认范围 |
| 16 个教室/走廊/操场模型 | Owner 确认自制，PR #102 / #64；E1/E6 | Blender（Owner 确认记录） | 已解决的既有子项 | 沿用既有项目记录 | `OWNER_CONFIRMED_RECORDED`；本轮仅有界交叉核对 |

### 3.1 肖像不可合并代答的字段

| 字段 | protagonist | Q | N |
|---|---|---|---|
| 生成工具 / 服务 / 模型及版本或 checkpoint | **UNKNOWN** | **UNKNOWN** | **UNKNOWN** |
| 实际生成日期 / 服务版本 / 账户方案 | **UNKNOWN** | **UNKNOWN** | **UNKNOWN** |
| 由谁提示、编辑、最终选定；是否 AI 辅助/生成 | **UNKNOWN**（记录称新生成） | **UNKNOWN**（记录称新生成） | **UNKNOWN**（记录称新生成） |
| 取得时适用条款的 URL / 日期 / 存档 | **UNKNOWN** | **UNKNOWN** | **UNKNOWN** |
| 商用、修改、游戏随包再分发、源文件公开分享 | **UNKNOWN** | **UNKNOWN** | **UNKNOWN** |
| 是否须署名、标识 AI、购买额外授权、取得输入/人物许可 | **UNKNOWN** | **UNKNOWN** | **UNKNOWN** |

PR #125 的供图记录使用 2026-11-12；这是**供图记录日期，不是生成日期**。即使后来确认三张使用同一服务，
也须明确该答复覆盖哪三份 hash、是否同一条款/账户方案，不能默默继承。无可证明的工具信息，
就没有可负责任地选取的具体 AI 服务条款；本次没有用某家服务的“可商用”营销页凑结论。

### 3.2 源文件到玩家可见资源的链

- 三个角色档案 `data/characters/{protagonist,q,n}.tres` 的 `portrait_path` 均指向上表对应的 `assets/ui/portraits/*.webp`。这些不是闲置参考图，而是玩家可见内容；档案另有展示裁切，不能把初次图片裁切参数当作全部 runtime 构图。
- `tools/prepare_portraits.py` 校验完整源 SHA-256，再转 RGB、按以下源像素框裁切、Lanczos 缩放至高 1100，WebP quality 92 / method 6。Godot 的 `.import` 继续做 lossy WebP / mipmap 导入。
- 本轮 Pillow **11.3.0** / libwebp **1.5.0** 下 `--check` 三张逐字节一致；没有写入图片。PNG 无附带 info/EXIF；WebP 只读到 background/loop，无 EXIF、XMP 服务/作者字段。**未发现可识别生成服务的元数据，不等于没有 AI 或已经清权。**
- `art/portraits/.gdignore` 与 preset 排除阻止完整源被当作游戏资源导入/打包；它们不是授权证明，也不阻止源图已存在于 Git 克隆中。裁切、缩放、重新编码或 shader 淡出不会自动清除上游要求。

| 肖像 | 源像素框 `(left, top, right, bottom)` | runtime 尺寸 | runtime 文件字节数 |
|---|---|---|---|
| protagonist | `(20, 20, 1125, 1354)` | 911×1100 | 418,492 |
| Q | `(25, 20, 1085, 1254)` | 945×1100 | 458,216 |
| N | `(180, 30, 1150, 1500)` | 726×1100 | 228,724 |

### 3.3 精确文件指纹

以下为审计快照的 SHA-256；本 PR 不改这些字节。源到输出的可重复性不包含商业授权结论。

| 路径 | SHA-256 |
|---|---|
| `assets/models/protagonist/Protagonist_Character.glb` | `80239a44cbbfdd6eebf560750a904a124e1d0db8f2e503db67150dc1ea60c09d` |
| `art/portraits/protagonist.png` | `2b8494996f8569977a94b4a79e34aa866ae98f933d1b563bfc2aed5aad9c7b2b` |
| `art/portraits/q.png` | `3d73b25001d4540802dacc052f0d561b57caeb86668b271b78faef7e5520ca60` |
| `art/portraits/n.webp` | `2417a5b79db609d754ad2bc78705bf0fad495af7f4fa7ab82f65612679feae3d` |
| `assets/ui/portraits/protagonist.webp` | `622a85104c2140f60e11db21594e81ba8db1b34f91e1d3333d1880d604ab703b` |
| `assets/ui/portraits/q.webp` | `68c8001a33e604c619710573fbd253eefffde2d3fa233a93a996463df0b4d42c` |
| `assets/ui/portraits/n.webp` | `cd6039a337c7be6a8243406b7caa20fbe8f4b65f3ae1f903649231aa479e4552` |
| `scenes/dev/animation_retarget_test/UAL1_Standard.glb` | `69591853d817488edaa8fd9bf8fc1d821eaeaf789f8627b3cd23b41c4ed67997` |
| `scenes/dev/animation_retarget_test/protagonist_ual.res` | `3aa7bd48fb77061c76f4f443538d8999e89eb57ab29ca6bd6a19b6f3f1226835` |

## 4. 可追溯证据索引与历史纠错

| ID | 可复核入口 | 支持的事实 / 不支持的推论 |
|---|---|---|
| E1 | [Issue #64](https://github.com/BrainEno/where-is-school/issues/64) 当前正文；[历史评论](https://github.com/BrainEno/where-is-school/issues/64#issuecomment-6799227546) | 当前正文明确 Q/16 模型已解决、新主角/肖像未解决、UAL 开发专用。不能用较旧评论把后来已解决的 Q/结构检查写成仍完全缺失；正文所标日期也不是素材生成/取得证据 |
| E2 | [PR #118](https://github.com/BrainEno/where-is-school/pull/118) §7；[作者待答评论](https://github.com/BrainEno/where-is-school/pull/118#issuecomment-6819492844)；整合提交 [8056b8c](https://github.com/BrainEno/where-is-school/commit/8056b8c5e92849ee10f0a4772302cfbe9955dc9c) | 记录上传线索 `c7b6fa4` 和 owner-supplied，不确认作者/工具；可读的 main 整合快照为 `8056b8c`。没有从 Git 提交人推断原创 |
| E3 | [PR #126](https://github.com/BrainEno/where-is-school/pull/126)；颜色修复提交 [ed16a02](https://github.com/BrainEno/where-is-school/commit/ed16a027a8c54033b423bcaf5039d986ec789c92) | 本轮比较 `8056b8c` 与当前 GLB：BIN chunk 一致；去掉 12 个 `baseColorFactor` 后 JSON 一致。证明修改范围，不证明最初作者 |
| E4 | [PR #125](https://github.com/BrainEno/where-is-school/pull/125) 的肖像/风险/Owner 待答；提交 [fbb8ce7](https://github.com/BrainEno/where-is-school/commit/fbb8ce772a837c6ad5b256cb5d9b846dbb67d8eb) | 三张源图、供图名、转换链、当时就未记录生成工具/商用条款；没有新的 Owner 许可答复 |
| E5 | [prepare_portraits.py 固定快照](https://github.com/BrainEno/where-is-school/blob/e12205a9d5e1731de3d25a4f074c2a3e4ddd4efa/tools/prepare_portraits.py)；同快照 `art/portraits/`、`assets/ui/portraits/`、`data/characters/` | 当前文件、源 hash、裁切、绑定和复现检查；不提供生成服务协议 |
| E6 | [PR #112 确认记录](https://github.com/BrainEno/where-is-school/pull/112#issuecomment-6815295245)、[PR #102](https://github.com/BrainEno/where-is-school/pull/102)、[PR #130](https://github.com/BrainEno/where-is-school/pull/130)、[历史 rig 说明](../art/character_rig_audit/README.md) | Q/16 模型的已确认状态、N 的已有 Owner 制作交接、旧主角与 Q 源/rigged 阶段的区别；manifest 是结构契约，不是商业许可证 |
| E7 | UAL 可见引入提交 [7c975e3](https://github.com/BrainEno/where-is-school/commit/7c975e350322ff43cd5a8fe3d794da2eb309b02f)；[bake 脚本快照](https://github.com/BrainEno/where-is-school/blob/e12205a9d5e1731de3d25a4f074c2a3e4ddd4efa/tools/bake_animation_retarget.gd) | GLB 实测 67 nodes、1 mesh、2 materials、65 joints、43 clips、7,618,436 bytes；header 无许可。入库提交不是下载日期，也不能对应当前网页的最新包版本 |
| E8 | 同快照的 [bake workflow](https://github.com/BrainEno/where-is-school/blob/e12205a9d5e1731de3d25a4f074c2a3e4ddd4efa/.github/workflows/bake-animation-retarget.yml)、`protagonist_ual_preview.tscn`、`scripts/dev/ual_preview.gd` | 独立开发 artifact 路径和派生库加载；没有在本轮 dispatch、重新上传或清理它们 |

**已纠正的台账表述：**

- 去掉开头把新玩家角色一并称为 Owner 原创、把全部其余资产视为已知自制的概括；主角的 `Project-owned pending` 与未核权肖像的 `Attribution: No` 改为 UNKNOWN。
- 三肖像拆行；Q/N 模型的确认不再被误用于同名肖像。
- 历史 protagonist rig audit 指向旧 `protagonist.glb`，不能证明新 `Protagonist_Character.glb` 的作者/结构。runtime manifest 当前明确登记四个 GLB；不再称“没有自动检查”。
- N 台账原称来自 PR #126，但该 PR 实际是主角颜色修复；本轮改记原上传 `fcafc6d91dd07a703e9448dd7fdecd45dc2a559d` 与整合 PR #130。这是来源链接纠错，不是新获得作者许可。
- 删除 UAL “cannot reach a build”、无条件“都是 CC0/所以可提交”的保证；区分项目禁发决定、许可冲突、验证能力边界与 Git/artifact 再分发。

## 5. UAL 公开条款与分发面

### 5.1 本次直接读取的公开材料

| ID | 页面 / 版本 | 本次读到的要点与限制 |
|---|---|---|
| P1 | [Quaternius Universal Animation Library 包页](https://quaternius.com/packs/universalanimationlibrary.html) | 明示 `License CC0` 和可用于 personal/educational/commercial projects；这是当前页面，不是此文件取得时的归档凭证 |
| P2 | [itch.io 该包](https://quaternius.itch.io/universal-animation-library) | 明示 CC0 1.0 Universal、Standard 下载及商业使用；感谢协作动画师 Gonzalo Furnier，页面标记未使用生成式 AI。网页的当前版本/changelog/AI 声明不证明仓库副本就是该版本或已取得全部权利 |
| P3 | [Quaternius Asset License v1.0](https://quaternius.com/license.html)，页面自述更新 2026-08-28 | §2 允许使用、修改及分发包含资产的完成品；§3(a) 限制资产本身（包括修改版）作为独立资产、asset pack、stock/template 等再分发，免费/收费皆包括，并明确不限制仅包含资产的完成品。§7 对已取得资产不追溯修改、以取得时版本为准；§9 是 entire agreement。**不能把它简化成禁止一切商业游戏使用，也不能自行裁定它撤销了 CC0** |
| P4 | [CC0 1.0 原文](https://creativecommons.org/publicdomain/zero/1.0/legalcode.en) | §2 的权利放弃、§3 的后备授权、§4 的权利与担保限制；仅在有权授予及其覆盖范围内适用，不是所有人物/商标/上游来源的保证 |
| P5 | [Steamworks Content Survey](https://partner.steamgames.com/doc/gettingstarted/contentsurvey#5) | 关注由玩家消费、随游戏提供的 AI 辅助/生成内容；Pre-Generated 包括开发期间制作的此类美术等，仍须符合不违法/不侵权及营销一致的承诺。填写问卷不会自动取得输出版权或素材许可 |

未把旧台账列出的 Godot Asset Store / OpenGameArt 标签当作本轮重新核验的独立证据；P1/P2 已足以确认
“当前包页 CC0 与另一份官方许可限制存在差异”。尚缺 Owner 当时的下载包/许可副本或原作者对该副本的澄清，
不能从新补取的 Git 历史补造下载日期。也不需要为维持项目禁发决定先替两份条款裁定优先级。

### 5.2 不能混同的分发面

| 分发面 | 当前事实 / 本轮处置 | 剩余风险 |
|---|---|---|
| Windows / Linux 游戏 ZIP 及嵌入 PCK | 两个 preset 仍排除开发目录；验证器补强；最终实际包检查单独见 PR 验证节 | 路径/已知名检查不是识别任意改名/内嵌动作的版权扫描；源码审查与实际包清单都要保留 |
| 当前 Git 树、源码 ZIP 与历史克隆 | 原始 UAL 和 baked `.res` 仍 tracked；没有删除/改二进制 | 排除导出不等于停止源码再分发；普通删除仅影响未来树，不清已有历史/克隆 |
| `Bake the retargeted animation` workflow 的 artifact | dispatch-only，能上传独立 `protagonist_ual.res`；本轮未运行、未新增下载或分享该 artifact | 不是游戏发行包，但属于独立资源分发面；仍需许可澄清/Owner 决定；本 PR 不擅改工作流或历史 artifact |
| 角色预览与 retarget-ready GLB、`.blend` | `art/character_rigging/` 有 `.gdignore`；开发场景位于 `scenes/dev/` | 旧角色来源记录与上游动画来源是两条链；retarget 不会把动画变成自主授权 |
| 游戏截图、商店宣传与公开源码中的肖像 | 肖像已经用于 runtime，截图/源图不因 `docs/` 或 `art/` 不进 PCK 就自动清权 | 新主角/肖像的授权应覆盖实际计划的游戏及营销用途；本轮不擅改截图/资产 |

当前生产 wrapper 未发现对 `UAL1_Standard`、`protagonist_ual.res` 或开发预览的引用。
`scripts/actors/animation_retarget.gd` 是重定向算法，不等于那批动作数据；生产七个程序化 clip 来自
`character_animation.gd`。**例外必须保留：N 的 idle 使用自己模型内的四个 loops**；新玩家 GLB 自带五个动画虽不播放，
仍不能当成“未分发数据”免去来源确认。上述是静态依赖核对，不冒充本地运行时观测。

## 6. 发行检查、真实漏洞与修复证据

### 6.1 两个平台的配置与检查链

两个 preset 均为 `export_filter="all_resources"`、空 `include_filter`、`embed_pck=true`、不加密 PCK。
排除集合一致，保持原样：

```text
tests/*, tools/*, docs/*, art/*, scenes/dev/*, scripts/dev/*, .github/*, addons/*
```

`release.yml` 先执行 preset 预检，Godot 4.7.2 standard 导入、分别导出 Windows/Linux，再显式复制 executable、
运行说明、Linux launcher/icon 与版权/OFL 文件到 ZIP；不是递归复制整个仓库。随后对**成品 ZIP 内的 executable/PCK**
运行 `verify_build.py --package ... --list`。tag-only publish job 下载后再次验证；PR CI 的通过不是发布或合并授权。

### 6.2 已复现而非猜测的验证器缺口

这些反例使用临时 preset 和合成 PCK/ZIP，**没有把第三方原文件复制进发行包，也没有证明旧正式包已经泄漏**。

| 缺口（基线实现） | 复现 | 本 PR 修复与反例 |
|---|---|---|
| preset 把“包含目录名子串”当作完整排除 | `scenes/dev/*.tscn` 或 `unrelated/scenes/dev/*` 均通过旧预检，但前者不覆盖 GLB/`.res`，后者指错目录 | 拆分逗号项，要求明确根目录 `directory/*`（允许 `res://` 与外部空白）；两个平台逐一破坏每个禁发目录的过滤项，均应拒绝。不试图证明任意 glob 等价，故意 fail closed |
| PCK 禁发列表漏了 `scripts/dev/` | 内容其余完整的合成条目加 `res://scripts/dev/ual_preview.gdc`，旧 `verify_contents()` 仍返回空问题列表 | 补齐前缀，与其他开发目录相同拒绝；现有预设未改 |
| 只靠 `scenes/dev/` 无法兜住已知资源的改目录/缓存名 | `res://assets/animations/protagonist_ual.res`、`.godot/imported/UAL1_Standard.glb-…scn` 被旧检查放行；相同已知文件名的松散 ZIP 资源也漏过 | PCK 与两平台 ZIP 共用已知 UAL/派生 basename 检查；覆盖格式变化、`.import`/`.remap`、`export-`/hash 缓存名和大小写。**不宣称能识别任意重新命名/嵌入/拆分后的内容** |

测试先红后绿：原有 **135 checks** 全过；加入新反例、实现未修改时 **58 / 211 checks 失败，exit 1**；
补强后 **211 checks 全过，exit 0**。没有删、跳过或放宽旧检查，也没有提高任何资源预算。
“good preset”夹具补齐本来已在真实 preset 中的 `.github/*`、`addons/*`，以检验完整隔离契约。
合成 pack writer 只构造目录/大小、不带真实数据；这些测试检验检查器，不能代替 Godot 实际导出。

### 6.3 本地实际验证与证据限制

本地 Python **3.11.2**；图像复现依赖装在 ignored 构建目录，不进入项目或 runtime。
以下结果属于本 PR 所审查的实现/未变更资产；最终 head 和 CI 实际包证据记录在相应 PR 的“验证结果”，
不使用旧 PR 或旧分支的绿灯作本轮证明。

| 实际命令 / 检查 | 本地结果及含义 |
|---|---|
| `python3 tools/model_library.py --check` | **通过**：26 GLB / 11 kinds，四个 runtime 角色结构与 manifest 一致；不是作者/许可审计 |
| `python3 tests/model_library_test.py` | **通过，146 checks**；输出中的坏相机/坏 manifest 是预期负例，不是本仓模型失败 |
| `python3 tools/verify_build.py --preset export_presets.cfg --expect-version 0.1.0` | **通过**，两平台正确排除；不是成品包检查 |
| `python3 tests/verify_build_test.py` | **通过，211 checks**，含本轮新增反例 |
| `python3 tools/build_sample_models.py --check` | **通过**，两个样例字节可复现 |
| `python3 tools/repo_size.py --check` / `python3 tests/repo_size_test.py` | **通过**；测试 18 checks，负例错误输出为预期；无新增大文件或豁免 |
| Pillow 11.3.0 / libwebp 1.5.0 环境下 `python tools/prepare_portraits.py --check` | **通过**，三张均逐字节一致；只读检查，没有重写图片 |
| GLB JSON / 源码引用 / 图片 metadata / SHA-256 | 已读取；具体发现见 §3–5；无作者/AI 平台的新增权利证明 |
| 本地 Godot、runtime tests、PCK/ZIP 导出与 `--package --list` | **本地未运行**：无 Godot；4.7.2 官方二进制下载重定向至当前网络不允许的存储主机而失败。没有改用别的引擎版本，也未声称本地成功 |
| `prepare_teacher_n.py --check`、Blender 审查/重新导出、UAL bake | **未运行**；本轮不重建 N 或动画源。N 优化链来自已有脚本/源 hash/交接，未冒充新的 Blender 实测 |
| Owner 画面签收、真实 Windows/Steam 客户端、Steam Deck 与法律签收 | **未进行**，不能由 headless/CI 代替 |

`model_library.py` 的既有体积提示仍保留：窗帘 **482.6 KiB**、新主角 **852.3 KiB**、旧主角 **513.6 KiB**、
新 Q **980.7 KiB**（旧审计时 Q 为 1008.8 KiB）、N **1334.7 KiB**，均超过 384 KiB 提示线但未过 1536 KiB 模型硬上限。
实际导出包可能另有 packed-category/总包警告，必须在最终 CI 验证节照实列出，不能用本地源文件体积代算。

**成品清单判据（须在最终 head 的 Release build 中读取，不从 preset 推定）：**

- Windows/Linux 均检查 ZIP 外层与嵌入 PCK；确认所有禁发目录、UAL 原名/派生名及其导入缓存名零命中。
- 应能追溯新主角模型和三肖像的 import stub/converted resource；这些 UNKNOWN 资产被包含是当前实现事实，不是许可放行。
- 保存/链接 `Verify both packages` 的 `--list` 日志、文件数、packed bytes、警告、失败/跳过项；如当前环境不能下载日志或 artifact，必须注明“仅核验 CI step/annotations，未独立本地展开”，不要编造完整清单。
- 不对任意新名字的二进制载荷作内容识别保证；后续添加/迁移/转换动画仍须人工来源审查。

## 7. Owner 亲答清单与退出条件

请按上表文件 hash 作答。只需公开最小必要事实；账户凭据、私人生成记录/手稿、个人绝对路径与付款信息不进公开 PR。
涉及私有凭证时，可由 Owner 私下保存，公开记录“核验者、适用条款版本、覆盖文件与明确结论”。

1. **新主角 GLB：** 谁制作了 mesh、rig、blend shape 与五个嵌入动画？Owner 是作者、委托方、下载者还是仅上传者？实际工具/服务及流程是什么，是否使用 AI、第三方 base mesh/rig/motion/纹理/参考输入？如为委托/第三方，请提供可商业用于本游戏、修改、随包分发及计划中源码/营销用途的授权范围。若 Owner 确为本人制作，请对这些组成明确书面确认，不从 header 代答。
2. **主角肖像单独答：** 服务/工具、模型/版本、实际生成日期（无法回溯则写 UNKNOWN）、账户方案及当时条款；谁提示/编辑，输入是否有其他图/人物/受限制作品；输出的商用、修改、游戏/原图再分发、营销、署名/标识/额外许可条件分别是什么？
3. **Q 肖像单独答：** 同上，明确针对 `993a6055…` 源图，不以 Q 模型原创确认代替。
4. **N 肖像单独答：** 同上，明确针对 `2417a5b7…` 源图，不以 N 模型来源代替。
5. **UAL：** 能否提供实际取得时的下载包、许可文件/条款存档、取得日期与 edition/version？是否联系 Quaternius，书面确认该副本与 retarget 输出在项目协作、公开 Git/源码 ZIP、独立 bake artifact 上的分发资格？在此之前维持游戏禁发；不要把本 PR 当作改变决定的依据。
6. **公开分发面处置：** 是否另行授权停止/清理特定开发 artifact、从未来树移除，或评估协调历史清理？这些不是本 PR 已执行事项；历史重写、仓库可见性和已有 artifact/clone 的处置都需独立明确决定。
7. **无法补证或条款不足时：** 由 Owner 决定暂停公开/商店发行，或另开授权清楚的替换任务。替换后重新登记、核对 runtime/营销引用并重跑成品包检查；本轮不擅换资产。

只有对应文件的来源、适用条款和使用范围得到可核对的记录，额外许可/署名义务落实（或经批准替换），
并完成精确发行 head 的双平台包验证，才可考虑解除相应发行阻塞。审计记录可被审阅合并，
**但不据此勾完 #64、认定 Steam 已批准、替 Owner 作法律承诺或自行合并 PR。**
