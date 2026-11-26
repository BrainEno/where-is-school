# 角色美术：游戏中的主角与 Q

本文覆盖主角与 Q 在运行中的游戏里如何被绘制与承载：审过什么、改了什么、刻意没动什么，以及如何复现、对比与检查。它承接 [ART_BIBLE.zh-CN.md](ART_BIBLE.zh-CN.md)（"游戏内 3D 角色"：轮廓、比例、体态、服装身份与可读性，先于面部细节）与 [NARRATIVE_BIBLE.md](NARRATIVE_BIBLE.md) 中的角色事实。动作由 [CHARACTER_ANIMATION.md](CHARACTER_ANIMATION.md)（"每个角色自己的承载片段方式"）覆盖。

**状态。** 这里的一切都是提案。Owner 尚未审阅。Owner 只决定了简报本身：让两人与教室的手绘风统一；主角颓丧、清冷、疲惫而不安，介于青年与成人之间，不是俊朗主角，不是动漫脸；Q 是普通、话多、微胖、自来熟的同学，不是向导。代课老师 N 与坐着的课堂学生不在范围内，未改动。

**序章美术审阅更新（2026-11）。** 坐着的课堂学生现在也上了色：`assets/characters/classroom_student/student_look.tres`（`art/characters/build_character_looks.py` 中的 `STUDENT`），是主角 look 的炭灰姊妹版，穿梅灰开衫，墨线只画在外轮廓闭合形上（78 个刚性件包含每根手指）。每个出货 look（主角、Q、N、学生）还做了*房间调色*：每个部件的暗部与亮部色调向教室的紫罗兰阴影（`#7E74B0`）与杏色亮光（`FFE0B4`）移动 30 %，使人物看起来与墙面被同一幅画照亮。未出货的实验保留自己的色调。

**角色整合更新。** 下文主角与 Q 的 C 方案调色板现在是出货 look 的*基底*，而非出货 look 本身：角色整合（[CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md)）把主角改为炭灰处理、Q 改为油画处理（肩缝皮肤被盖绘），并给了 N 自己的 look（粉笔）于同一着色器上。C 方案的文件被冻结保存在 `scenes/dev/character_lab/looks/before/` 供对比。坐着的课堂学生仍在范围外。

**V2 头部更新（issue #383）。** §2 的"不加 UV、不改 GLB"规则适用于 look 那一轮，现在**仅对主角的头部**被有意取代：头部有了自己的 V2 构建（`tools/head_v2.py`），带局部 UV 图集、切线基、1024² 反照率与法线贴图，以及保持已批准发型的更密发笼。已批准的 V1 模型逐字节保留为 `art/character_models/sculpt/lead_v1_head.glb`（其 SHA-256 被钉在构建器里，`check` 拒绝用任何其他文件构建）。身体、服装、骨架、权重、动画、材质、节点名与其他所有网格均未改动。合同记录在 §9。

## Q 替换说明

下文 §1–§2 中 Q 专属的测量与审评陈述是**历史性的**：它们描述的是已退役的 16 关节模型，不是今天单独批准的替换件。`assets/models/q/new-Q.glb` 现在是唯一的生产 Q：静止身高 1.78449 m，9 个蒙皮网格 / 16 个表面 / 12 个材质，60 个关节，三十个带权重的手指关节与十三个头部 morph。其来源是 Owner 为本项目明确批准的原创 ChatGPT 生成 Q。该批准不构成对迁移的视觉签核。

出货的 C 着色器、主角模型/发型/look 及所有无关美术保持不变。只有 Q 的材质名映射、面斑坐标、眨眼名与姿态标定被适配：hoodie/hood/rib、身体皮肤、巩膜与口腔使用其实际新名；面斑跟随抬高的脸，双手省去会粘连手指的大外壳，头部共享的皮肤/发型表面被选择性描边。呼吸/后仰与手指手势现在使用 Q 自带的动作而非定住的旧前臂。完整的结构对比、可复现的源准备、实机证据与遗留视觉审阅见 [Q_MODEL_MIGRATION.md](Q_MODEL_MIGRATION.md)。不要重启被否决的角色美术审阅实验来评估本次迁移。

## 1. 问题所在

主角与 Q 按导入时的 GLB 材质受光：Godot 的 PBR 路径，平滑 Burley 衰减、高光瓣、每个部件一个平色。他们周围的教室恰恰相反：卡通漫反射、无高光、手绘贴图与墨线（`assets/materials/classroom/*.tres`）。在那个房间里两人读起来像塑料小人：

- 脸是一道平滑渐变，鼻梁与脸颊上有高光；
- 衣服每个部件一个明度，于是外套、长裤与鞋在房间低而暖的光里融成一团，轮廓取决于身后的背景；
- 线条与色彩没有一笔属于那间手绘教室，人物像贴上去的；
- 两个角色以同一节奏呼吸、走路、说话（`CharacterAnimation.CLIPS`），主角站得和 Q 一样直。

## 2. 模型审阅

两个 GLB 在任何改动之前都做了结构解读与多角度渲染（静止姿势与绑定片段，离线，仅作参考；不是验收证据）。

| | 主角（`Protagonist_Character.glb`） | Q（`q.glb`） |
|---|---|---|
| 身高 | 1.767 m | 1.647 m |
| 头 | 下巴到头顶 0.27 m（约 6.6 头身），窄脸宽 0.17 m，大眼 | 0.26 m（约 6.4 头身），宽圆脸宽 0.24 m，颊部丰满，五官小巧 |
| 身体 | 肩窄、四肢细、躯干扁平（厚 0.24 m），A-pose 手臂外张约 35° | 圆肚在脊柱前突 0.32 m，四肢短，右前臂前伸建模 |
| 轮廓 | 高而瘦，刺发是顶部的重音 | 宽而软，碗状发，侧面最宽点是肚子 |
| 服装 | 灰绿外套（立绘：黑色学兰）、衬衫、长裤、鞋 | 绿毛衣（立绘：米白外套）、藏青长裤、棕鞋浅色鞋底 |
| 数据 | 9 网格、15 表面、12 材质、60 关节、无 UV、头部 9 个 blend shape | 7 网格、15 表面、14 材质、16 关节、无 UV、无 blend shape |

**发现。**

- **比例与轮廓本就分开了两人。** 高瘦对矮圆在游戏距离可读，且符合叙事圣经。没有任何几何反对任一角色的身份。
- **主角的问题是体态与完成度，不是形状。** 他直立、手臂张开、头抬平，读作中性自信。简报要的每一种气质（疲惫、微驼、收着）都是姿态与表情，两者都无需碰网格：片段系统摆出脊柱、颈、头与手臂，头部本就带着 `BrowCompress`、`LipTension`、`Frown` 与两个眨眼形。
- **Q 的问题是完成度，以及一具动起来像主角的身体。** 他的轮廓是对的；缺的是更松、更沉、重心后靠脚跟的节奏。
- **手、脚与脸**是简化的，美术圣经在 2.5D 镜头下允许。片段里没有任何手或脚读错；主角的手指有绑定但没有动画。
- **没有 UV。** 两个模型都没有纹理坐标，手绘贴图需要给每个部件新 UV。那是重导出，会破坏钉住的尺寸、绑定审计与蒙皮合同。而且不需要：基于位置的程序化涂绘给出房间有的色块，静止姿势坐标把它们留在布料上（§4）。

**决定（提案）：本轮不改 Blender 源、不改任何 GLB。** 不重命名骨骼、不移动顶点、不加 UV、不重拓扑。每处改动都在模型旁的角色专属资源里。后续轮次仍可以改网格；若改了，保留当前导出为记录源，并在此处与 `docs/ASSET_PROVENANCE.md` 记录该导出。

## 3. 三种处理，在游戏里对比

对比在运行中的游戏里进行：真实的教室、走廊与街道，各自的光、环境与 tonemapping，用游戏自己的镜头与近景。帧在哪见 §7。模型预览窗口不是验收证据。三种处理可在运行时于一个节点上切换（`CharacterLookApplier`），同一帧可以拍三次。

| | A — 原始 | B — 颜料 | C — 手绘（出货） |
|---|---|---|---|
| 是什么 | 导入时的 GLB 材质 | `assets/shaders/painterly/character_pigment.gdshader`，每个 GLB 材质一个实例携带其基色 | `assets/shaders/characters/character_paint.gdshader` 配每部件自绘调色板，加 `character_outline.gdshader` |
| 光 | PBR，平滑衰减，高光 | 带轻摆的 Lambert | 三档（阴影、中间调、亮部）带笔刷边缘，每部件一个手绘影色，无高光 |
| 色 | 每部件一个明度 | 每部件一个明度加轻微斑驳 | 每部件两种颜料的色阶化色块，加手绘面斑（眼下、脸颊） |
| 线 | 无 | 无 | 外轮廓形上的墨壳，随距离缩放 |
| 与教室同框 | 塑料；低光下部件相融 | 光泽少了但仍平滑扁平；部件仍相融 | 用房间自己的语言：档、块、墨 |
| 身份 | 可辨 | 可辨 | 可辨：同样的形，同样的色族 |

**B 评估过但未采用。** 它去掉了高光油亮，但每个部件仍是单一明度：外套与长裤照样相融，没有线把轮廓钉在深色黑板前，斑驳在游戏距离太细读不出。它也没有影色的概念，而房间的性格大半在影色里。`character_pigment.gdshader` 与其 `.tres` 保持原样，只供绘画实验室与其测试使用。

**C 出货**，因为它是唯一在三点上（档位光照、粗色块、墨）全部匹配教室、同时保住每个角色身份的方案：与模型和立绘同样的色族，没有任何部件被改色成另一种身份。

## 4. C 方案细节

### 4.1 手绘表面（`character_paint.gdshader`）

- **三档光。** `light()` 把 N·L 切成阴影 / 中间调 / 亮部，边缘柔软（`shadow_edge`、`light_edge`、`edge_softness`）。颜料噪声在切档之前把 N·L 推移最多 `edge_break`，于是档边缘像笔触边缘一样游走，而不是贴着网格的棱面。
- **亮部压在满值以下。** 全亮档是 `light_strength`（默认 0.76，主角皮肤 0.70，Q 0.72），不是 1.0。Lambert 只在光正打处到 1.0；整档上 N·L 平均约 0.75。第一次截帧用了平 1.0，教室的暖主光把主角的苍白脸烤成奶油色，于是眼睛与眼下的瘀伤读不出来了。主角皮肤还把 `light_edge` 移到 0.55，让大半张脸坐在中间调。他的中间调更暗（0.5 对 0.62），皮肤颜料块更粗（scale 15、value 0.14），于是颧骨、鼻子与眉脊保住体面。用默认值的第二次截帧，从眉到下巴是一片平的苍白。
- **手绘影色。** 暗侧保留 `shadow_fill` 的光，由 `shade_tint` 染色：主角冷紫灰，Q 橄榄。单灯下不会死黑，并给每个角色一份自己的影中之色。
- **颜料块。** 一次色阶化的双八度数值噪声（`pigment_steps` 档）把基色拉向 `pigment_a` 或 `pigment_b`，并按 `pigment_value` 变化明度。色块被轻微拉伸（`pigment_stretch`），读作笔触。
- **静止姿势坐标。** 噪声在顶点的绑定姿势位置采样，`CharacterLookApplier` 每网格一次复制进 `CUSTOM0`（w = 2 标记）。蒙皮顶点自身位置随骨骼走，由它定位的色块会滑过摆动的裤腿。重建的网格原样保序携带 GLB 自己的顶点、索引、法线、骨骼与权重；只新增 `CUSTOM0`（`tests/imported_assets_test.gd` 逐数组比对）。带 blend shape 的网格（主角的头部）保留自身网格并回退到对象空间位置，于是他脸上的色块在点头时移几毫米。
- **手绘面斑。** 每部件两个椭球，跨脸镜像，边缘不规则：主角的瘀青眼下与凹颊，Q 的泛红脸颊。
- **无高光、无边缘光、无反射**（`specular_disabled`、`SPECULAR = 0`、`ROUGHNESS = 1`）：高光无处滑动。

### 4.2 墨线（`character_outline.gdshader`）

一个反转外壳，作为外部部件的 `next_pass` 绘制，用教室的墨色（#292433，序章美术迁移以来生物教室实验的笔色）。教室的壳固定长 1.6 cm；人在近景里从一米内看、在游戏中从六米看，所以这个壳随视距生长（`width` 在 4 m 为 10 mm，钳制 ×0.55–×1.7）。它细到近景不吞掉眼睛，粗到能把轮廓钉在黑板前。眼、嘴、眉、纽扣、领口、衬衫与鞋底不带壳。作为材质 pass，它不新增节点、网格或表面：wrapper 的计数与包围盒不变。

### 4.3 调色板

主角冷而收；Q 暖而放。两者在色相（冷石板灰绿对苔绿与赤陶）、明度结构（苍白脸上的深外套对红润脸上的中绿毛衣）与影色上分开。

| 部件 | 主角 | Q |
|---|---|---|
| 皮肤 | #B4A58C（身体 #A99A83），苍白萎黄（颜料 #98A088 / #C2A68E），影 #9AA6C6 | #CE9A70，红润，影橄榄 #B5B88E |
| 面斑 | 眼下 #665570（瘀青），颊凹 #98997F | 脸颊 #C9634C（泛红） |
| 头发 | #221E21，近黑 | #18151B，近黑 |
| 上装 | 石板外套 #37414A（趋近立绘的学兰，由墨线与更亮的影填充同深色黑板分开） | 苔绿毛衣 #516F4C（模型自己的绿，不是立绘的外套：游戏中模型才是身份） |
| 长裤 | 暖炭 #3B3836，使外套与腿分开 | 藏青 #313D52 |
| 鞋 | 深色，描边 | 棕色，浅鞋底（鞋底不描线） |

完整表格连同每种颜料、影色调与面斑都在 `art/characters/build_character_looks.py`，它写出 `assets/characters/protagonist/protagonist_look.tres` 与 `assets/characters/q/q_look.tres`。改脚本而不是 `.tres` 文件，然后运行它（stdlib Python，无依赖）：

```bash
python3 art/characters/build_character_looks.py          # 重写两个 look
python3 art/characters/build_character_looks.py --check  # 过期则失败
```

### 4.4 主角的脸

头部自己的 blend shape 给出他的休息表情：`BrowCompress` 0.45（眉心紧蹙、忧虑），`LipTension` 0.35，`Frown` 0.15，眼睑略低且不齐（`Blink_L` 0.10、`Blink_R` 0.15）：疲惫、不安，不是悲伤卡通。他每 1.8–4.2 秒眨眼一次，种子来自 look 的标签，于是同一场景的两次截帧眨眼相同。他的眼睛始终是脸上最亮、对比最高的点，由瘀青面斑框住，这使眼睛成为第一读点。Q 的脸按建模原样：他的笑是他的身份。

## 5. 体态与节奏

每个 wrapper 携带一个 `CharacterMotionProfile`（`assets/characters/{protagonist/protagonist_motion.tres, q/q_motion.tres}`），交给 `CharacterAnimation.bind()`。它改变共享片段写就时的键：速度、幅度、站姿与小图层。它不改片段、名字、骨骼或状态机。细节与数字在 [CHARACTER_ANIMATION.md](CHARACTER_ANIMATION.md)；简言之：

- **主角：**脊柱、胸、颈前倾（4° / 5° / 6°），头低下，手臂向身体收 14°，肘微屈。待机慢一倍，胸里有一声叹、头落下又抬起。走路保持步幅、手臂轨道克制（见当前的[动作档案](CHARACTER_ANIMATION.md#per-character-motion-resources)）；说话手势半大，起身更慢（2.0 s）。
- **Q：**后仰（脊柱 −4.5°），头歪，站得更宽，空着的手从肚子伸出。更快的带摆待机、脊柱与手臂摆幅更大的走路、半大而更快的说话。

## 6. 文件在哪

| 路径 | 是什么 |
|---|---|
| `assets/shaders/characters/character_paint.gdshader` | 手绘表面（§4.1） |
| `assets/shaders/characters/character_outline.gdshader` | 墨壳（§4.2） |
| `assets/characters/protagonist/protagonist_look.tres`、`assets/characters/q/q_look.tres` | `CharacterLook`：每个 GLB 材质（或 `mesh/material`）一个手绘 `ShaderMaterial`，休息表情与眨眼。生成物（§4.3） |
| `assets/characters/protagonist/protagonist_motion.tres`、`assets/characters/q/q_motion.tres` | `CharacterMotionProfile`（§5） |
| `scripts/actors/character_look.gd` | `CharacterLook` 资源 |
| `scripts/actors/character_look_applier.gd` | `CharacterLookApplier`：把 look 应用到旁边模型、切换处理、以静止坐标重建网格、驱动眨眼 |
| `scripts/actors/character_motion_profile.gd` | `CharacterMotionProfile` 资源 |
| `scenes/environment/characters/protagonist.tscn`、`q.tscn` | wrapper：根上的 `motion_profile`、`Model` 旁的 `Look` 节点 |
| `art/characters/build_character_looks.py` | 调色板表与两个 look 的生成器 |
| `tools/head_v2.py`、`tools/head_v2_textures.py` | V2 头部构建器与其贴图生成器（§9） |
| `assets/characters/protagonist/textures/head_albedo.png`、`head_normal.png` | 头部局部 1024² 贴图（§9.2） |
| `scripts/actors/character_detail_maps.gd` | look 指名贴图时手绘着色器包含的细节贴图绘制（§9.2） |
| `tools/head_preview.py`、`tools/head_preview.c` | 复现证据帧的离线渲染器（§9.3） |
| `tests/capture_character_art.gd`、`.github/workflows/character-art-capture.yml` | 游戏内截帧（§7） |

模型目录仍然只有 `.glb` 与其 `.import`（有测试）。教室或任何其他地点场景、以及显示系统都未改动：唯一被碰的场景是 wrapper，所以每个实例化它们的地方都得到新 look。

## 7. 检查

**无头，在 `godot-ci.yml`：**

- `tests/imported_assets_test.gd`：两个 wrapper 都带其档案与 `Look`；15 个表面全部用 `character_paint.gdshader` 绘制（没有一个保留 GLB 材质）；部分、但不是全部带墨线；ORIGINAL 与 PIGMENT 可达可回退；重建的网格保有 GLB 的顶点、索引、骨骼与权重并新增静止坐标；骨架骨骼数不变；主角有休息表情。
- `tests/protagonist_model_test.gd`：上色后的玩家网格仍蒙皮到 60 骨骨架，头部保有九个 blend shape。
- `tests/character_animation_test.gd`：档案不新增轨道、不把轨道移到别的骨骼；每个片段是 `CLIPS` 长度 × 速度；`get_up` 仍从 `sit_idle` 姿势开始；站姿在站立姿势里；两角色的待机、走路与说话长度不同。
- `tests/runtime_character_animation_test.gd`：在运行的游戏中，两角色都绑定其档案、以 PAINTED 绘制且什么都不保留、不共享一个速度；应用档案后所有既有待机、走路、手高、腿部与起身限制仍成立。

**离线，在引擎之外：**

- `python3 tools/head_v2.py check`：从钉住的 V1 源重建头部，要求已安装 GLB 逐字节是该构建的输出，并断言 §9.3 合同（图集、接缝、眼睑、眼裂、发束、预算）；
- `python3 tests/model_library_test.py`：每个模型仍可解析、符合预算、不携带相机或灯光，运行时角色仍匹配其清单。

**在游戏里，`Character art capture` 工作流**（`tests/capture_character_art.gd`、Xvfb、OpenGL、1600×900），每组一个任务：

| 组 | 帧 |
|---|---|
| `bodies` | 头到脚，A / B / C，每个角色独自在西侧过道靠黑板 |
| `faces` | 脸部近景 A / B / C，以及游戏自己镜头下的 A 与 C |
| `clips` | 待机、走、慢跑、sit_idle、get_up、挥手、说话、上色，各一帧 |
| `posture` | 有无档案的待机与走路，侧面；正面、¾、侧面、背面剪影 |
| `light` | 上色两人在教室（房间前后）、走廊与街道，游戏镜头与近景 |

每个任务把印相表以通知发布（base64 JPEG 分 4000 字符段）并把全尺寸帧与日志作为 artifact 上传。当角色不绘制、未绑定、或在上色 look 下保留了 GLB 材质时任务失败。名牌（开发辅助）对这些帧隐藏。

## 8. 限制与开放点

- 主角脸上的颜料在对象空间采样（他的头部网格有 blend shape，静止坐标重建不携带），所以点头时会轻微移动。携带 blend shape 是可能的，但先放着，直到能在引擎里检查。
- 着色器在 `light()` 里对每盏灯重算噪声。比 GLB 材质略贵，且只有两个角色；教室有两盏灯加太阳。
- 立绘与模型在服装上不同（主角的黑色学兰、Q 的米白外套）。调色板只在模型身份允许处向立绘靠（更深的石板外套）；不把 Q 的毛衣改色成外套。模型是否应跟随立绘是 Owner 的决定。
- B 与 C 方案可随时在运行场景里比较：`$Look.apply_treatment(CharacterLookApplier.Treatment.PIGMENT)`。

## 9. V2 头部（issue #383）

### 9.1 构建是什么

主角头部与头发的确定性重建，只从钉住的 V1 源运行（`art/character_models/sculpt/lead_v1_head.glb`，SHA-256
`2b24d063bee3044dac8b9eb11945ead8cf001b6decd045c48e1e0b2ee7c40e6e`；`check` 拒绝任何其他文件）：

```bash
python3 tools/head_v2.py build     # V1 -> build/head_v2/Protagonist_Character.glb
python3 tools/head_v2.py install   # 把该构建复制到运行时 GLB
python3 tools/head_v2.py check     # 重建、要求已安装 GLB 逐字节是该构建的输出、
                                   # 断言 §9.3 的合同
```

- **皮肤**细分一次（每个原三角四个），在静止空间雕塑——眼窝、包裹眼球的眼睑、鼻翼与鼻底、嘴唇及其周围、颧骨、加宽的下颌、前推的下巴、眉脊、颈——然后给一张连续的以脸为中心的 UV 图集（背缝在网格里切开）、一个切线基，九个稀疏 morph target 经细分映射重采样（小于五分之一微米的 delta 置零，以保持稀疏 target 诚实）。
- **头发保持 Owner 的发型**：同样的 96 束、发根、发梢与轮廓——包围盒与 V1 完全相同。每束的五个环就地细分：插入每条环边的中点（5 → 10 列、每束 45 → 90 三角；整体 2 799 → 5 199 顶点、4 880 → 9 200 三角，比它取代的分股草稿更小），按发束自身轴向把中点半径收到 0.82，发束再取一次至多 `min(2 mm, 3 % 长度) · sin(πt)` 的轻柔外弯，`t` 为环心的轴向参数。根环与发梢不弯，头皮盖帽不碰，网格保持流形、无退化三角。
- **眼睛**被找平（V1 的右眼高 2.5 mm）、扁平的虹膜与瞳孔圆片被拱起、虹膜通过顶点色获得巩膜环；眉毛以锥形管重新挂上眉脊；耳朵获得耳碗、耳轮、耳甲与耳垂；口腔内部随嘴唇。重建的面部部件对新的静止姿势重述头部的九个 morph target；眼睛网格本身不带，与 V1 一致。
- **身体、服装、骨架、权重、动画、材质、节点名与所有其他网格**从运行时 GLB 逐字节复制。

### 9.2 贴图与接线

头部的细浮雕与局部色彩住在 1024² 贴图里，而不是更多三角里：`assets/characters/protagonist/textures/head_albedo.png`（嘴唇、眼下瘀斑、胡青）与 `head_normal.png`（褶皱与皮肤纹理），由 `tools/head_v2_textures.py` 生成。`CharacterLook.detail_maps` 指名它们，`CharacterLookApplier` 绑定它们，`scripts/actors/character_detail_maps.gd` 是 look 指名贴图时手绘着色器包含的绘制。该通道是 **opt-in**：主角的 look 启用它，其他每个角色的 look 都不启用，且那些模型都没有 UV，旧路径原样未动。A/B 只是一个旗标：

```bash
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --out build/head_v2/look
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --no-detail-maps \
    --out build/head_v2/look_nodetail
```

### 9.3 `check` 断言的合同

| | |
|---|---|
| V1 源 | SHA-256 钉住；任何其他文件拒绝构建 |
| 头 | 11 332 顶点、22 064 三角、9 个 morph target、图集在 [0, 1] 内、无三角跨越背缝（最大 U 跨度 0.49999）、4 个眼睑壳、眼裂 13.4 mm |
| 头发 | 5 199 顶点、9 200 三角、96 束 + 盖帽、包围盒与 V1 相同 |
| 眼 | 眼睛网格 0 个 morph target |
| 预算 | 已安装 GLB 1 199 412 B，低于 1 536 KiB 模型预算 |

证据帧可用 `tools/head_preview.py` 复现（灰模 = 不带 `--look`，接通 = 出货 look，`--views front,quarter,side,close`，`--no-detail-maps` 做 A/B）。在本 head 上，离线 check、离线渲染与 Python 测试（`verify_build_test`、`model_library_test`、`character_geometry_capture_test`、`agent_docs_test`）均在本地运行；§7 的引擎测试在 CI 运行；Owner 的灰模与贴图验收记录在 issue #383。

### 9.4 限制

- §4.1 的脸部颜料对头部仍在对象空间采样（静止坐标重建不携带 blend shape），所以点头时那些色块移几毫米；新贴图在 UV 空间，不移动。
- 头发的弯与收是静止姿势几何，不是模拟。
- `tools/head_v2.py extract` 只从 V2 之前的运行时重建 V1 源；`build` 读的是提交在库里的 V1 文件，不是某次 extract。

## 10. V3 头发（issue #386）

### 10.1 构建是什么

同一条确定性管线（`tools/head_v2.py`），仍只从钉住的 V1 源构建、仍被 `check` 逐字节比对——只是在 V2 的环细分与写盘之间多了一道头发 pass。issue 规定的工作顺序就是 pass 的执行顺序：

1. **发旋与发际线。** 帽壳内部沿头顶取螺旋浮雕，并向后脑引出同心弧（`whorl_cap`，至多 1.3 mm，沿各顶点自身外向，距帽壳边界 18 mm 内淡出到零）。帽壳边界就是 Owner 的发际线，逐顶点钉死——剪裁线不动。
2. **剪影被钳制。** V2 头发包围盒作为常量钉住；V3 的每次位移都钳在盒内，`check` 把成品的包围盒对回钉值。已批准的外剪影——束尖、模型高度、测试量到的宽度——不会漂移。
3. **大组走向，从根部开始。** 每束的根环沿自身轴回潜 8 mm，受头骨钳制：雕刻后皮肤的极坐标半径场（4° × 4 mm 分箱，外扩一箱）把每个位移后的顶点推到离头至少 1.2 mm，所以埋根进入体积却永不刺穿皮肤。根环在自身平面加宽 1.28–1.56 倍（环 1 跟随 45%），直到相邻根部相接——刘海束之间的三角缺口从下面合拢，而不是挪动束尖。随后每根轴受重力弯 5–11 mm——逐束偏航、根尖为零——并带轻微 S 摆，向上的束倾斜、侧面的束垂落，如同一副头发。宽于 22 mm 的板束在环 2–3 之间取一道内凹刻痕，把板拆成束组。
4. **束的节奏。** V2 实测断面 (1.0, 1.14, 1.04, 0.88, 0.55)——中段鼓起，这正是每束读作"尖锥带掐尖"的原因。V3 把环重映射为干净的收势 (1.0, 0.94, 0.82, 0.66, 0.55)，每束取自己的宽度（0.86–1.12 倍，哈希得出——无随机，每次构建相同）、沿轴 ±16% 的宽薄调制、至多 0.15 rad 的断面扭转。相邻两束不再共享同一组"宽度-相位-弯"，克隆阵列的读感就此打破。

无透明、无 groom、无新几何：顶点数、三角数与拓扑都是 V2 的（5 199 顶点、9 200 三角、96 束 + 盖帽），皮肤权重不动，帽壳边界与每根束尖都留在 V2 放置的位置。

### 10.2 头发的贴图

头发网格现在携带 UV 图集（`hair_uv`）：帽壳按方位角与高度映射进 3 × 3 块，96 束各占一格——U 绕环走、V 从根到尖，无岛回绕、无顶点复制，网格保持精确的 V2 顶点数与拓扑。look 通过与头部相同的 `detail_maps` 通道（§9.2）向图集里画两张新图：

- `hair_normal.png`（1024²）：每束格两道闪烁的束沟——被噪声打断的暗线，读作分开的发丝而不是挤出的条纹——加上网格浮雕用的同一发旋场（按纹素分辨率采样）与一缕发丝颗粒。
- `hair_albedo.png`（512²）：两道偏亮的束釉放在束沟旁边（颜色与浮雕并排，绝不叠在上面）、更暗的发根、一层冷色噪声，以 `albedo_mix` 0.75 作为 look 发色的乘法层。

贴图走与头部相同的 UV 门槛：applier 只把贴图绑到真正带 UV 的面上，眉毛——在头部网格上共享发色材质但没有 UV——保持原样绘制。`detail_maps_enabled` 是头部与头发贴图共同的 A/B 开关，预览加 `--no-detail-maps` 做对比：

```bash
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --out build/head_v2/look
python3 tools/head_preview.py assets/models/protagonist/Protagonist_Character.glb \
    --look assets/characters/protagonist/protagonist_look.tres --no-detail-maps \
    --out build/head_v2/look_nodetail
```

### 10.3 `check` 新增的断言

| | |
|---|---|
| 头发 UV | 头发 primitive 携带 `TEXCOORD_0` |
| 包络 | 成品头发的包围盒与钉住的 V2 包络一致（0.1 mm 内） |
| 数量 | 5 199 顶点、9 200 三角、96 束 + 盖帽——与 V2 相同 |
| 预算 | 已安装 GLB 1 199 412 B，低于 1 536 KiB 模型预算 |

### 10.4 限制

- 发旋、重力弯与扭转都是静止姿势几何，同 §9.4——不是模拟。
- 束沟画在每束自己的图集格里，跟着它所属的那束走；头发不带 morph target，没有任何东西会移动它们。
- 包络钳制是绝对的：V3 重塑的是根与尖之间的体积，永远不碰剪影的极值。
