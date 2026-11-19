# 角色整合：主角、Q、代课老师 N 融入序章场景语言

英文版 [CHARACTER_INTEGRATION.md](CHARACTER_INTEGRATION.md) 为准，本文件为中文副本。

**这是什么。** PR #203 把教室迁移到生物课教室实验的画面：两段式明暗交界、环境色阴影、冷色墙面、深蓝窗帘、低角度暖色阳光、统一墨线。但教室里的三个人没有跟着迁移。本文记录三部分内容：
- 三个角色对照这间教室的审计；
- 实验：Q 与 N 各至少两套实质不同的方案，主角一套；
- 最终整合的内容，以及在实际游戏中的验证。

本文扩展 [CHARACTER_ART.md](CHARACTER_ART.md)，不取代它：其中的方案 C 配色现在是已发布外观的基础。

**状态。** 已实现的提案，不是所有者视觉批准。第 1–8 节记录此前仅材质工作的历史边界。
所有者随后已要求实际模型精修：**第 9 节仅对 N 和坐椅学生取代此前“不改 GLB／六个双面眼面”的说明**。
剧情、对白及独立 2D 肖像不变；历史截图或结构检查通过不能冒充新美术获批。

模型身份：平台未显示，无法核实。

## 1. 基线审计（main `a3b274b`）

### 1.1 每个角色如何构建与绘制

| | 主角 | Q | N |
|---|---|---|---|
| 模型 | `Protagonist_Character.glb`，1.767 m，约 6.6 头身 | `new-Q.glb`，1.784 m，约 6.7 头身，宽而偏壮 | `teacher-n.glb`，1.654 m，约 6.7 头身，头小而窄 |
| 骨骼 | 60 关节，9 个头部形变 | 60 关节，13 个头部形变 | 16 关节（旧 Q 骨骼名），无形变 |
| 网格与材质 | 9 网格、15 面、12 种纯色材质 | 9 网格、16 面、12 种纯色材质 | 18 网格、28 面、17 种纯色材质，粗糙度 0.15–0.9 |
| 贴图与 UV | 无 | 无 | 无 |
| 动画 | UAL 重定向，配自有动作配置 | 自带六个动作，配 `q_motion.tres` | 自带四个循环，无动作配置 |
| 游戏内绘制方式 | `CharacterLookApplier`，方案 C：上色着色器加墨线外壳 | 同上，方案 C | **GLB 原始 PBR 材质**：无应用器、无上色着色器、无墨线 |
| 肖像 | 独立 2D 作品，不是模型渲染 | 同上 | 同上 |

### 1.2 教室的要求

教室所有物体都经同一套光照模型 `concrete.gdshaderinc` 着色：
- 硬两段式明暗交界（0.12 ± 0.03）；
- 阴影取教室自身的环境色 (0.44, 0.38, 0.52)；
- 破碎的蓝绿与赭色斑驳；
- 无高光；
- 统一墨色 `#292433`。

阳光温暖、低角度、自西射入，地面阴影呈紫色。站立角色身后的背景是深绿近黑的黑板、深蓝窗帘与淡紫墙面。

### 1.3 每个角色三个问题（分类）

依据 `tests/capture_character_integration.gd` 的 before 帧测得。

| 角色 | 问题 | 类别 |
|---|---|---|
| 主角 | 外套、裤子、头发都接近纯黑（#22–#3B）。在俯视的游戏镜头里，他是阳光地面上最暗的物体，读起来像一块投影而不是一个人 | 材质（明度设计） |
| 主角 | 墨线与衣服同明度，暗面轮廓融进地面的紫色阴影（阴影中平均亮度 0.090） | 渲染（分离度） |
| 主角 | 最具辨识度的刺头内部没有明度层次，俯视时是一团墨 | 材质 |
| Q | 宽脸配小五官，作为表情核心的眼睛与厚眼睑在远处消失 | 材质（脸部明度） |
| Q | 身体皮肤在肩缝处穿出卫衣，每帧两肩尖都有浅色尖刺（`Q_MODEL_MIGRATION.md` §8） | 模型缺陷；源文件已批准，不重塑 |
| Q | 卫衣的苔绿和亮棕罗纹夹在窗帘的蓝与黑板的绿之间，服装与房间争抢而非相融 | 材质（色彩关系） |
| N | 完全不在教室的渲染管线里：PBR 渐变、高光、无明暗交界、无墨线。显得像塑料，像被另一个太阳照亮 | 渲染（管线） |
| N | 服装苍白低对比：衬衫、开衫、裤子都挤在很窄的浅灰区间（平均亮度 0.298，另外两人为 0.18–0.19）。她是讲台上最亮的东西，却没有明度结构，看起来像低精度占位 | 材质 |
| N | 梨形剪影：窄肩（±0.22 m）、开衫下摆外扩到 0.136 m 深、浅色裤子进一步加宽、头盔状带条纹的波波头、面具般的脸 | 模型（剪影）加材质 |

旧 `q_close` 帧里 Q 周围的浅黄描边**不是**他的墨线，而是交互高亮 `WorldCue.OUTLINE_COLOR`：当时玩家站在对话范围内。新的采集脚本只在点击 Q 时打开交互。

**真正原因，一句话：** 教室是由一套光照模型和一个明度规划定义的，而角色不在这个规划里。N 完全不在光照模型里；主角和 Q 在模型里，但明度错了。增加面数、贴图（模型本来就没有 UV）或后处理都解决不了这个问题。

### 1.4 重复、旧版与未使用资产

| 资产 | 状态 |
|---|---|
| `assets/models/protagonist/protagonist.glb` | 旧主角模型；**仍被** `classroom_student.tscn`（坐着的同学）使用，不属于未使用资产 |
| `assets/models/sample/figure.glb` | 由 `sample_figure.tscn` 与模型库测试使用 |
| `art/character_models/{q,teacher-n}/*_source.glb` | 已锁定的源文件；`prepare_q.py` 与 `prepare_teacher_n.py` 需要 |
| `character_pigment.gdshader` | 已否决的方案 B，但仍是可切换的处理方式，`imported_assets_test.gd` 会检查 |

没有任何角色资产被确认未使用，因此**未删除任何文件**。

## 2. 实验

所有实验都是 `CharacterLook`，由 `art/characters/build_character_looks.py` 依据 `art/characters/look_experiments.py` 生成，使用同一套上色与墨线着色器。实验为这两个着色器新增三项可选功能，默认全部关闭：
- **笔触标记**（`mark_*`）：在静止姿态空间里铺设的短而断续的笔触。可以均匀覆盖一个部件（干笔、粉笔颗粒），也可以聚在形体转离视线处（木刻的刻边）。小于一个像素时退为平均色调，游戏距离下不闪烁。
- **剪影塑形**（`shape_*`，上色与墨线共用）：最多两个静止姿态空间里的椭球，沿姿态法线把形体推入或推出几厘米。GLB 不动，网格包围盒与蒙皮不变。
- **墨线抖动**（`wobble`）：手刻般的线宽。
- **双面上色**（`two_sided`，`character_paint_two_sided.gdshader`）：关闭剔除的同一套上色，用于三角面朝内的部件（见下文 N）。

在任何外观设置新参数之前，同一个生成器会逐字节生成 main 上原有的方案 C 外观。冻结副本存放在 `scenes/dev/character_lab/looks/before/`。

| 角色 | 方案 | 思路 | 游戏内结果 | 决定 |
|---|---|---|---|---|
| 主角 | **炭笔** | 学生服由近黑提到能接住阳光的石板灰，肩背受暖光；每条转折边上有浅色"擦出"的笔触；头发用发丝笔触 | 肩背在游戏镜头里可读，轮廓与紫色阴影分离（阴影中亮度 0.090 → 0.110）。v1 的发丝笔触使脸部杂乱，v2 减半；v3 再压暗，因为这么细的笔触会平均成一层灰纱，盖在每根刺上 | **整合** |
| Q | **油画** | 大块拉长色块；橄榄色中间调承载宽脸的面；上眼睑凹陷对应他的厚眼睑；厚涂衣褶；卫衣移向赭橄榄，罗纹压暗 | 远处表情保留，卫衣与地面、黑板相融而不相争。v1 眼部色块糊在鼻梁上，v2 离中线 1.4 cm | **整合** |
| Q | **蚀刻版画**（`q_paper`） | 两段硬明暗，几乎无色彩漂移，深一阶的长斜线排线，纯黑头发配浅色发丝 | 卫衣像针织，但排线在皮肤上像疤痕，并在脖子上画出等高线圈（v1）。去掉后（v2）脸部扁平如海报，与房间的颜料不是同一种媒介 | 仅实验 |
| N | **粉笔** | 灰纸上的色粉：较柔的明暗交界，取自房间环境色的淡紫阴影，提亮的鼠尾草绿开衫上有浅色粉笔笔触，深色窄裤，肖像中的苍白脸与深色波波头，开衫下摆收 8 mm | 一个处在房间光线里的人。明度回到同一家族（0.241，另外两人 0.186 与 0.189），梨形消失，年轻柔和而不威严。v1 与 v2 的眼睛空白、带圈，像戴眼镜。原因在模型而非外观：teacher-n.glb 的眼球朝内，单面上色剔除了虹膜与瞳孔，露出的是眼球后壁的内侧。现在这三个部件改为双面上色 | **整合** |
| N | **木刻**（`n_woodcut`） | 白线木刻：硬明暗、深紫阴影，近黑石板色开衫的边缘刻出浅色刀痕，手刻抖动轮廓，下摆收 12 mm，发顶放出 1 cm | 很有冲击力，但她变得和主角一样暗重（阳光下 0.158），融进黑板，显得严厉威严。这与叙事圣经冲突：她是没有经验的代课老师，并不更高一等。它较宽且抖动的墨线外壳还会在眼窝与鼻梁的凹褶处画出一道眼镜般的细线（反转外壳描边在凹褶处的已知瑕疵）；该方案不发布，因此未修 | 仅实验 |

Q 的两套方案、N 的两套方案，区别在于媒介（颜料与版画、粉笔与木刻）、明度规划与线条，而不只是强度不同。

## 3. 已整合内容

| 角色 | 外观文件 | 一句话 |
|---|---|---|
| 主角 | `protagonist/protagonist_look.tres` | 仍是穿黑色学生服、灰肤、刺头的男孩，现在用炭笔画在房间的纸上：接住阳光的石板灰，边缘擦出的光，用发丝读出的头发 |
| Q | `q/q_look.tres` | 仍是普通、宽脸、自来熟、穿绿卫衣的同学，现在是厚油画，用房间的橄榄与赭色，厚眼睑清晰可读，肩缝露出的皮肤已涂盖 |
| N | `teacher_n/teacher_n_look.tres`，`teacher_n.tscn` 新增 `Look` 节点 | 仍是深色波波头、鼠尾草绿开衫的年轻代课老师，现在处在房间的光与线里：柔和的色粉，纤细而迟疑，不再苍白、梨形 |

**异质但同一世界。** 三人共享房间的光照模型、阴影色系、统一墨色与纸面，但用三种媒介：炭笔、油画、粉笔。各自也有不同的明度基调：暗（主角）、中而暖（Q）、浅而冷（N）。

**未改动：**
- 所有 GLB、骨骼、蒙皮与动画片段；
- 动作配置，以及 N 自带的待机层；
- 台词与肖像；
- 交互锚点与碰撞；
- N 在入场前的隐藏放置、`NEntryPath`、`NPresence` 与剧情标记；
- Q 的镜头 `q_talk` 及其聚焦逻辑；
- 玩家控制器与镜头装置。

## 4. 游戏内验证

所有画面都由 `tests/capture_character_integration.gd` 生成，在 `Character integration capture` 工作流中运行。它启动 `main.tscn`，进入真实教室，在教室自己的阳光与环境下拍摄真实的角色包装场景（玩家的主角，以及房间里的 `Actors/Q`、`Actors/N`）。各列之间只有应用器所用的外观不同。任何地方都没有用 Blender 或离线渲染作为证据。

已提交的对照图：
- `docs/screenshots/character_integration/final/`（before / 第二方案 / after）；
- `docs/screenshots/character_integration/round1/`（before / v1 实验）。

| 要求的对比 | 对照图 |
|---|---|
| 主角在生物教室 | `final/protagonist_gameplay__before_after.jpg`、`final/protagonist_body_sun__before_after.jpg`、`final/protagonist_body_shade__before_after.jpg` |
| Q 特写与对话 | `final/q_face__before_q_paper_after.jpg`、`final/q_face_three_quarter__before_q_paper_after.jpg`、`final/dialogue_dialogue_q__before_after.jpg` |
| N 特写与场景 | `final/n_face__before_n_woodcut_after.jpg`、`final/n_lectern__before_n_woodcut_after.jpg`、`final/dialogue_dialogue_n__before_after.jpg` |
| 三人同一光照 | `final/lineup_lineup_sun__before_after.jpg`、`final/lineup_lineup_shade__before_after.jpg`、`final/lineup_lineup_game__before_after.jpg` |
| 动作 | `final/q_talk__before_after.jpg`、`final/q_walk__before_after.jpg` |

对话帧走的是游戏自己的点击路径和镜头（`q_talk` 聚焦），以及 `play_conversation(&"n_class")`，显示的是未改动的 2D 肖像。before 与 after 两列在同一会话中拍摄，因此可能停在同一段对话的不同台词上。

每个角色绘制像素的平均亮度，取自采集运行 43918819332（即已提交的 `final/` 对照图）的 `ARTNOTE` 行：

| 画面 | 主角 before → after | Q before → after | N before → after |
|---|---|---|---|
| 并排，阳光 | 0.177 → 0.186 | 0.193 → 0.189 | 0.298 → 0.241 |
| 并排，阴影 | 0.135 → 0.151 | 0.147 → 0.144 | 0.239 → 0.175 |
| 单人，阴影 | 0.090 → 0.110 | — | 0.223 → 0.174（木刻 0.108） |

## 5. 测试与检查

- `tests/imported_assets_test.gd` 用与另外两人相同的外观约定检查 N：
  - 28 个面全部上色，有墨线的面多于零且少于全部；
  - ORIGINAL 与 PIGMENT 可切换、可还原；
  - 重建的网格只在 `CUSTOM0` 上不同，包围盒与骨骼数不变。

  她恰好有六个面（双眼的巩膜、虹膜、瞳孔）使用双面着色器，另外两人一个也没有。她的包装场景必须**不带**动作配置（`"motion": ""`），因为她播放自带的循环。
- `build_character_looks.py --check`（Godot CI）现在也覆盖 N 的外观和保留的两套实验。
- 没有跳过、削弱或删除任何测试。

## 6. 改动与新增文件清单

见英文版第 6 节。模型、贴图、动画文件均未改动，模型本身也没有贴图。所有外观都是手写参数，不是生成资产，因此 `ASSET_PROVENANCE.md` 无需新增条目。

## 7. 未解决问题与所有者决定

1. **Q 的肩缝**只是涂盖，没有修复。皮肤仍穿出卫衣几毫米，现在是卫衣的颜色且无墨线。真正的修复需要在已批准源文件上做局部服装补丁，需要你授权（`Q_MODEL_MIGRATION.md` §8）。
2. **主角提亮到什么程度。** 炭笔外观有意保持学生服偏暗：这是他的身份。再提亮会让俯视更易读，但会离肖像更远。
3. **N 的开衫色相。** 保留鼠尾草绿系。木刻方案提示了更暗更强的服装；本任务没有采用，因为会使她显得威严。若她的角色之后要变得强硬，由你决定。
4. **N 的模型**眼球朝内，已在外观中绕过；在源文件中翻转只需一行，可留到下次模型修订。模型仍是 16 关节骨骼，没有面部形变（不能眨眼、没有表情），波波头网格呈头盔状。条纹已由统一的发色掩盖。如需重建模型，另开任务。
5. **手部。** Q 的手套状手和 N 的简化手部未改动。
6. 坐着的同学不在上述集成的原始范围内；下文后续要求的表面细化已将其纳入，模型与坐姿放置保持不变。

## 8. N 与坐椅同学的表面细化（2026-11-18）

**范围/状态。** 相对基线 `42b25b29adc53bfb36d2c6f5be7fcf4ee948b6b6` 已实现的材质提案，
不等于所有者视觉批准。这不是已退役的 #188 叠层实验。两人的生产外观已经接入绘画管线，
这里的“粗糙”是色块与描边过粗、头发通用排线、衣料种类缺乏区分，不是要求降低 PBR
粗糙度或增加油亮皮肤。N 没有 UV，学生主要衣料表面也没有；放大一张位图不能为它们补上细节。

### 实现与边界

- 在现有 `character_paint.gdshaderinc` 内新增可选的 `pigment_blend`（色阶间连续罩染）、
  `patch_feather` 与 `detail_kind/strength/scale/tint/origin`。类型 1 为细 V 形针织、
  2 为经纬斜纹、3 为角向弯曲发束。仅改变漫反射颜色：粗糙度仍为 1，金属度/镜面仍为 0；
  不新增法线、纹理采样、几何、绘制 pass 或材质槽。
- 衣料复用现有静止坐标的三向投影，混合权重来自静止位置导数，而非姿态/视角法线，避免
  肩膀运动时织纹在衣服上转动。用 `fwidth` 在纹理变成亚像素前淡出对比度；这是抗锯齿措施，
  不是已经实测的 FPS 提升。
- `refined_teacher()` 保留 N 的鼠尾草绿开衫、米色衬衣和深色裤子，收敛大块粉笔笔触，
  加入细针织/斜纹及弯曲棕色发束，减弱面部色块对比并柔化罩染。
  `refined_student()` 保留灰紫/米色/藏蓝，缓和皮肤明暗插片与眼下对比，按材质角色分配
  针织、斜纹和发束。两人描边改为 5.5 mm，减少摇摆；手指、面部插片与细小衣片仍不单独套描边壳。
- 新参数默认关闭；仅两个生产外观在 `room_keyed()` 前启用。主角、Q 和保留的木刻/纸感
  实验不重新定风格。用 `python3 art/characters/build_character_looks.py` 重生成，
  `--check` 检查漂移；不要手改生成的 `.tres`。
- 不改 GLB、法线、权重、骨骼、动画、形变、包装场景变换、碰撞、交互、对白或肖像。
  N 的六个内向眼面仍使用现有双面 shader；这不是修复源模型，也没有新增面部表情。
  学生模型原有的棱角仍属于模型几何。

**表面来源。** 修改的现有 `.tres` 资源由仓库内 Python 调色参数表确定性生成，shader 是
在 Arena 编程辅助下编写的一方代码；不新增下载、描摹、图像生成作品或运行资源文件。
模型权利仍以 `ASSET_PROVENANCE.md` 原有记录为准，材质参数变更不为其他模型/肖像确立
权利。该共享台账保持原样，以免与并行环境美术 PR #245 交叉修改。

### 可复现对照与回归覆盖

`capture_character_integration.gd` 现在纳入真实的 `Actors/SeatedStudent`，不把它站起来：
提供正面/四分之三脸部、衣料、原位桌椅和游戏距离画面，N 增加衣料近景。
`baseline` 明确区别于历史 `before`：用 `--baseline-dir` 加载**本次变更基线**的
n.tres 和 student.tres。缺目录/资源会失败，不会偷换成更老或 raw 外观。
`--freeze-pose` 固定已绑定的 idle/sit 姿态和眨眼，供材质 A/B；不能据此声称验证了运动。

```sh
baseline="$(mktemp -d)"
base=42b25b29adc53bfb36d2c6f5be7fcf4ee948b6b6
git show "$base:assets/characters/teacher_n/teacher_n_look.tres" > "$baseline/n.tres"
git show "$base:assets/characters/classroom_student/student_look.tres" > "$baseline/student.tres"
for group in n student; do
  xvfb-run -a --server-args="-screen 0 1600x900x24" \
    godot --path . --resolution 1600x900 --rendering-driver opengl3 \
    --script res://tests/capture_character_integration.gd -- \
    --group="$group" --variants=baseline,after --baseline-dir="$baseline" --freeze-pose
done
```

在仅材质修订中，截图工作流的 `refinement-n`、`refinement-student` 作业从**实际 PR base SHA**
提取外观，记录 SHA 并发布双列图。当前几何修订改用第 9 节的两次真实引擎运行，同时替换实际 GLB；
仅上面的旧命令并不更换几何。手动 dispatch 时基线就是
所 dispatch 的修订自身，不能作为历史改善证据。每列共享场景、灯光、镜头和姿态；基线使用
当前 shader 但关闭新增选项。

`tests/imported_assets_test.gd` 额外锁定细节材质角色与克制的强度，确认皮肤/眼睛及主角/Q
所有材质不启用细节，主角/Q 也不启用新的罩染选项；现有几何/静止坐标、材质切换可逆性、
坐椅包装场景、六个双面眼面的合同继续有效。实际执行结果与环境警告在 PR 中报告，
不能在这里预先认定视觉验收通过。

**所有者清单：** 对比日照/阴影下的脸和头发；检查两套衣料近景；查看讲台上的 N 与原位
坐椅学生；移动/缩放游戏镜头观察闪烁和轮廓可读性；用未冻结的正常 idle、walk、sit 路径
检查细节是否泳动。目标显卡 Forward+ 与 Windows 性能仍需目标硬件验证，软件/OpenGL 截图不等于该验证。

## 9. N 与坐椅学生的实际几何精修（2026-11-18）

**要求／状态。** 所有者本轮明确允许修改模型（棱角、简化手型），以《极乐迪斯科》人物的
选择性精细度和区分性为质量参照。这不是复制其资产的许可，也不能宣称已达到同等商业成品质量。
本轮基线 `7379ff7239bee6254ab3242901be9705488e282d`，先精修此前已处理外观的两个 NPC。
已检查主角、Q，但不改变其 GLB、肖像、外观和动作；主角来源权利未因此获得澄清。

### 几何与人物区分

- **两人的手：** 四根长短不同的手指加拇指，每只手是一块闭合、连通的流形表面，不是把带盖
  圆柱插进手掌。保留自然弯曲、渐细掌骨、虎口、不同指长；指根以上的轮廓切片仍分出四指。
  仍用原 Hand 骨骼，并未增加可独立活动的手指骨骼。
- **N：** 保留窄脸、原有及颌波波头、鼠尾草绿／奶油／深灰服装及略不确定的气质，不改成
  权威式剪影。原头发仅局部柔化棱角、毫米级不对称发尾，不换成通用头盔；脸颊／下颌也是
  毫米级调整。新增翻卷袖口遮接缝。新手部顶点在埋入袖口的腕部使用**新设**手／前臂过渡权重，
  不能说保留了旧手权重。GLB 中修正六个眼面的绕序、法线；生产 `refined_teacher()` 移除双面
  补丁，历史木刻实验保持不变。
- **学生：** 更宽的下颌／颧骨／太阳穴和连续鼻部，与 N、瘦高内收的主角区分。较小杏仁形
  眼面沿真实眼窝起伏，不再使用原先凸出的眼球／脸颊贴块。短斜梳发型、肩／袖放样、带厚度的
  曲面领片／翻领／口袋、选定原形体的圆角修正替代灰盒棱角，同时保留梅灰／奶油／海军蓝身份，
  不变成主角复制品。手仍刚性绑定原 Hand；删除 14 个过时网格节点：独立手指／拇指、脸颊／
  眼下贴块及两个分离鼻部组件。

N 仍由 `prepare_teacher_n.py` 唯一生成。学生新增此前缺失的源→运行文件 owner
`prepare_classroom_student.py`；原 525,912 字节运行模型原样保存为哈希锁定的
`art/character_models/classroom_student/student_source.glb`。共享建模代码是
`tools/character_geometry.py`，NumPy 和 N 原有简化器均只用于构建；不虚构旧学生的 Blender
生成源。来源、原／新哈希及权利边界见 [ASSET_PROVENANCE.md](ASSET_PROVENANCE.md)。

两套 16 关节的层级、顺序、节点 rest 变换、逆绑定矩阵完全不变；N 四个循环及每个有效移动
关键帧不变，学生仍没有内嵌动画。不改包装场景偏移／yaw、碰撞、教室位置、运行控制器、
材质／静止坐标 owner、剧情或肖像。学生加宽约 6 mm，高度和脚底基准不变。**1536 KiB**
运行文件硬上限不放宽：N 1439.0 KiB、学生 1475.0 KiB。学生三角面 12,388→64,604，
N 57,460→62,340；明确披露这项成本，不把面数增长说成性能改善或美术质量证明。

### 重建与检查

```sh
python3 -m pip install -r tools/requirements.txt
python3 tools/prepare_teacher_n.py --check
python3 tools/prepare_classroom_student.py --check
python3 tests/character_geometry_test.py
python3 art/characters/build_character_looks.py --check
python3 tools/model_library.py --check
```

15 项几何测试检查确定性字节／源哈希、闭合连通五指表面、法线／索引／权重有效性、
骨架／rest／逆绑定相同、N 移动动作完整保留、N 头发是局部改动而非替换、眼部浮雕／绕序、
既有体积与脚底合同。`imported_assets_test.gd` 有意更新为学生 64 个材质面、生产外观
**零个双面眼面**，不放宽其静止坐标／着色蒙皮／坐姿包装检查。结构变化由重建的清单审查，
并不能豁免形变或视觉回归。

### 真实几何对照，而非仅给新网格换旧材质

单独 `--variants=baseline,after` 仍然**只换外观**。工作流两个精修作业现用
`tools/capture_character_geometry.sh`：两段均为精确 PR head 的代码／场景／镜头／shader，
一次 Godot 真运行用当前 GLB／外观，另一次用实际基线 GLB／外观；两次进程间重新导入基线
GLB，退出时恢复当前模型字节。独立 manifest 记录 base／代码 head SHA、模型／外观 SHA-256、
引擎与后端。仅把真实渲染面板拼成带标签的“左基线／右 head”对照，不用离线渲染或模型截图
冒充肖像。静帧固定相同 idle／sit 相位；N 的 walk 静帧仍不证明动态网格质量。

```sh
baseline="$(mktemp -d)"
base=7379ff7239bee6254ab3242901be9705488e282d
git show "$base:assets/models/teacher-n/teacher-n.glb" > "$baseline/n.glb"
git show "$base:assets/models/protagonist/protagonist.glb" > "$baseline/student.glb"
git show "$base:assets/characters/teacher_n/teacher_n_look.tres" > "$baseline/n.tres"
git show "$base:assets/characters/classroom_student/student_look.tres" > "$baseline/student.tres"
printf '%s\n' "$base" > "$baseline/base-sha.txt"
# 在可丢弃的证据 checkout 中运行；PATH 上需有 Godot，且安装 Xvfb。
bash tools/capture_character_geometry.sh n 'body_sun,face,face_three_quarter,hands,cloth,lectern,walk' "$baseline"
bash tools/capture_character_geometry.sh student '' "$baseline"
```

证据工作流先检出精确 PR head，再安装仓库锁定版本的 Godot。`workflow_dispatch` 默认基线
仍为派发修订自身；模型 base/head 相同不是历史改善证据。实际结果、失败尝试、诊断／泄漏
数量和最终 head 链接在 PR 记录，不在本文假定通过。离线排查图明确不属于 Godot 证据。

**仍须分开验收：** Agent 静态画面复查；不冻结的 idle／walk／转身／sit 中腕／肩接缝、
手指剪影、衣领／桌／椅穿插与颜料泳动；所有者美术批准；Windows 生产 Forward+ 目标 GPU
质量／性能。软件 OpenGL 截图和相同骨架输入都不能替代最后两项。
