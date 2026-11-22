# Q 正式模型迁移记录

## 1. 范围与来源

唯一生产模型为 `assets/models/q/new-Q.glb`，唯一包装场景仍为
`scenes/environment/characters/q.tscn`。课堂 NPC、跟随同伴与开发预览都引用该包装，
不保留旧模型兼容分支或双模型开关。

Owner 已明确确认：**new-Q 是 ChatGPT 为本项目生成的原创 Q，并批准正式使用**。
本次不再次询问来源/所有权；该确认不延伸到主角、肖像、UAL 或 #64 的其他问题。
平台未显示，无法核实本次 Agent 的模型名称/版本；不据此推测资产的生成模型版本。

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| `art/character_models/q/new-Q_source.glb`（原始批准文件，父级 `.gdignore` 排除导入/导出） | 1,187,664 | `4d2d7d5939840bdfcc8b94f111f864e1d080a715380969ec335a7e1e60509f45` |
| 迁移时的无损整理基准（`prepare_base()`） | 1,004,268 | `be670a4056f51db612653a868bff6d701a968d4b1ab19d85cafad55de92b46f1` |
| 首次独立头部精修（历史） | 992,760 | `28c9279e45ffce7e895ae00aadb036bcfa99105c9063d3927bda73122fd01293` |
| 序章近景精修前（`0ac97d7`） | 992,760 | `c290e795e2a48e4bdb8fff78c65b0b12d34b4b93aeb9ed22e7962cb5e784d250` |
| B / Q 局部精修前（`0230efb`，保留 #329） | 992,764 | `274a2da481523189723ee808490295174e11c654e979c6f24a57a5c5987247cc` |
| `assets/models/q/new-Q.glb`（短发与五官局部精修） | 992,760 | `96141f7677de7e3747702ab6dd92687ff0b3870f20d465b3932430ef4f05a7f3` |

[本轮头部编辑](../art/character_models/sculpt/README.md)接在 #329 的近景雕刻之后，仅替换指定头部表面的位置与法线。原始批准文件、绑定、13 个形变的偏移、6 段动作和原游戏镜头不变。

源上传 commit `f9aa19d4fa8ad56b0e4d2e46c48c799d10ffbb42`，blob
`0d71fcf65cf76fa7abe7124cba7f74fbfa02efb9`。初始开发基线为
`580f6f34d3ff4e56f3d00d67cf115a98e63cfdbf`；发现 main 合入 #201 后暂停，
Owner 明确授权改以 **`c4e6bfa450153b84a823eaa5c8ece1ff28964691`** 为新评审基线，
正常 merge 到当前分支，不 rebase/force-push。新的 before 摄影使用此授权基线；
前两轮历史摄影仍标注各自原始 SHA。不使用旧 Q 的 Blender/Python 制作链描述新 Q，
也不将技术准备脚本称作新模型的几何生成器。

## 2. 检查结果：不能直接套用旧骨架

以下来自 GLB JSON/BIN、层级、rest 与 inverse bind 的实测；不是截图验收结论。

| 项目 | 基线旧 Q | 批准的新 Q（去除骨架展示网格后） |
|---|---|---|
| 节点 / 网格 / primitives / 材质 | 25 / 7 / 15 / 14 | 70 / 9 / 16 / 12 |
| 顶点 / 三角形 | 18,031 / 35,432 | 9,841 / 17,918 |
| skin joints | 16 | 60 |
| root / 导入骨架 | `Q_Root` → `Q_Humanoid_Skeleton` | `Q_Armature` → 导入的 `Skeleton3D` |
| 躯干 | Root → Spine → Neck → Head；无独立胸/锁骨 | Root → Pelvis → Spine → Spine_01 → Spine_02 → Chest → Neck → Head |
| 手臂 | `UpperArm.L/R`, `LowerArm.L/R`, `Hand.L/R` | Chest → Clavicle_L/R → UpperArm_L/R → Forearm_L/R → Hand_L/R |
| 手指 | 无独立指骨 | 每手 Thumb / Index / Middle / Ring / Little，各 01–03，共 30 根，全部有权重 |
| 腿脚 | Thigh/Shin/Foot `.L/R` | Pelvis → Thigh_L/R → Shin_L/R → Foot_L/R → Toe_L/R |
| 其他骨骼 | 无 | Eye_L/R 与四个 Root 下的 IK 目标（无新增 IK 解算器） |
| 源动作 / 头部 morph | 0 / 0 | 6 / 13 |
| rest 包围盒（宽×高×深，m） | 约 0.726 × 1.647 × 0.607 | 1.30945 × 1.78449 × 0.37586，宽度包含 A-pose 手臂 |
| 原点 / 朝向 / 缩放 | 足底 / +Z / unit | 足底 y=0 / +Z / unit |
| 旧 posed-limb 守卫 | 右前臂及双手保持旧建模姿态 | 不需要；前臂/手下垂方向 cosine >0.7，双臂均可动画 |

新 rig 的 bind × inverse-bind 最大单位矩阵误差约 `6.37e-7`；未发现非法 joint
索引或错误权重和。`Q_Hands` 有 524 个顶点，每个手指关节均影响 18–19 个顶点。
这是“五指有独立加权关节”的结构证据，不等于拇指/掌形/皮肤变形已经人工通过。

语义 `.L` 在共享动作中代表 skeleton −X；新骨架的 anatomical `_L` 在 +X。
因此七对 shoulder/arm/hand/leg/foot 按 rest 位置镜像映射，不能只替换名称：

| 共享语义 | 新骨骼 |
|---|---|
| hips / spine / chest / neck / head | Pelvis / Spine / Chest / Neck / Head |
| shoulder.L / .R | Clavicle_R / Clavicle_L |
| upper_arm.L / .R | UpperArm_R / UpperArm_L |
| fore_arm.L / .R | Forearm_R / Forearm_L |
| hand.L / .R | Hand_R / Hand_L |
| thigh.L / .R、shin.L / .R、foot.L / .R | 对应 `_R` / `_L` |

## 3. 可复现的技术整理与材质适配

`tools/prepare_q.py` 的 `prepare_base()` 固定验证原始 SHA，并且只：

1. 移除 `Q_SkeletonPreview` 展示节点、网格与 `BonePreview` 材质（1,440 顶点 /
   480 三角形）；它们不是角色身体。
2. 从六个动作中删去 831 条恒等于实际 rest 的 LINEAR/STEP 通道，保留每个非 rest
   通道及所有六个动作；不删除手指动画。余下 70 条通道。
3. 给原文件缺少 `baseColorFactor` 的十二种材质补上现有 Q 调色，不添加贴图。
4. 逐字节复制有效 accessor/view 数据并紧凑打包，正确保留 sparse morph。

上述整理阶段没有移动顶点、重拓扑、改变法线/权重/骨架层级/rest/inverse bind/morph 或更改源动作 key。
`tests/q_model_prepare_test.py` 逐数组对照批准源。后续 [Blender 头部精修](../art/character_models/sculpt/README.md)
才调整面部/眼睛位置和法线，并仅更换 `Q_Hair` 拓扑。`prepare()` 安装该独立雕刻层；
骨架、13 个 morph 偏移及六个动作不变。第 2 节数字记录原迁移，精修后为 9,526 顶点、18,310 三角形。

新网格为 `Q_Body`、`Q_Eyes`、`Q_Feet`、`Q_Hair`、`Q_Hands`、`Q_Head`、`Q_Hood`、
`Q_Hoodie`、`Q_HoodieDetails`。`q_look.tres` 的映射迁移到实际
`Q_Mat_{SkinBody,Trousers,Sclera,Iris,Pupil,Shoes,Sole,Hair,Skin,MouthInner,Hoodie,HoodieRib}`。
保留既有 C shader/调色系统，仅调整 Q 的材质名、脸颊 patch 坐标、新眨眼名与局部轮廓：
双手不加会粘合手指的厚外壳，头部共享 skin/hair 表面按材质分别处理。
新源没有 UV/normal map，因此仅 Q 的 `.import` 设 `meshes/ensure_tangents=false`；
否则真实导入报告 `UVs are required to generate tangents`。不伪造 UV，也不改其他模型设置。

`q_motion.tres` 将双上臂向内收 14°适配新 A-pose，其余角色不换模型、不换头发、
不改材质或 C 方案。生成器重跑后主角 `.tres` 无 diff。

## 4. 动作完整迁移

没有 AnimationTree；现有 `BoundAnimationPlayer` / `char` AnimationLibrary 与
`CharacterVisualAnimation` 状态机继续使用。生产路径不是裸旧轨道复制。

| 路径 | 迁移方法 |
|---|---|
| idle | 原生 `Q_Idle_Breathing`（7 通道）+ `Q_Slight_Body_Lean`（9 通道），叠加 Q 站姿校准 |
| walk / jog | 共享 rest-relative 语义动作重新解析新 rig；双前臂和双腿活动，不冻结旧守卫骨 |
| sit_idle / get_up | 保留坐下/起身契约，首帧一致、一次性起身与状态交还不变 |
| wave | 保留共享挥手动作，新骨骼路径与语义 frame 重新生成 |
| talk | 原生 `Q_Casual_Hand_Gesture`（21 通道）+ breathing：胸、头、右锁骨、肩、肘、腕及右手全部 15 指关节 |
| head/gaze | 原生 `head_movement` 来自 `Q_Head_Movement`（3 通道）；游戏注视仍由现有 `NpcGaze` 后置骨骼 modifier 实现 |
| hand_gesture / body_lean | 单独保留对应原生动作，供现有动作播放器/开发预览使用 |
| pose_preview | 保留 `Q_Pose_Preview`（29 条非 rest 单 key），仅诊断，不替代动态 idle/walk |
| face_test | 原 `Q_Face_Test` 的 head weights 通道完整保留；是显式开发诊断，不宣称口型同步 |

原生源动作约 4 s，按实际 rest 差值组合；生产 idle 按 Q tempo 0.85 播放为约 3.4 s，
talk 按 tempo 0.8 播放为约 3.2 s，额外原生预览保持源时间。所有 bound clip 补齐“该 library 动画骨骼
并集”的 reset tracks，避免 talk/pose → walk 后指节、骨盆或锁骨滞留。额外动作不删减
共享七状态；不将它们用作静态人体替代品。

真实对话通过独立的 `CharacterDialogueAnimation` 监听已有 `line_presented` /
`presentation_active_changed`。按 `speaker_id` 匹配可见的 `NpcActor.npc_id`，
subjective voice 不让台上 Q 假装发声。仅 Q 的 `dialogue_clip` 非空。
优先级为一次性 action → seated → 移动 walk/jog → 站定 talk → idle；对话行改变/关闭
清除 speech，请求过程中移动仍可行走，停下则恢复当前台词的 talk。

## 5. 游戏位置与交互

- 包装根 `Q` 与 `Model`、`Look`、`InteractionAnchor` 组织/路径保留；模型本身无补偿
  scale/yaw/垂直位移。InteractionAnchor 仍 y=1.2。
- 课堂 `Actors/Q` 仍位于 `(-3.3,0,3.1)`、yaw −56°；`QOpeningTalk` 位于
  `(-2.75,0,1.95)`，`QPresence` 的重入/读档落点逻辑保留。
- 课堂 `QTalk` 仍 `(-3.3,0.8,3.1)`，radius=1.1；同伴 AskAlong 仍 y=0.9、radius=1.3。
- `NpcActor` 的 placement `visual_yaw_degrees=180` 保留以适配 +Z 模型，
  controller 的朝向/导航不另写一套。
- `companion.tscn` 唯一胶囊高度 1.6→1.8 m、中心 y=0.8→0.9，radius=0.34 不变；
  visual 不新增碰撞，导航/interaction layer 不变。
- 动画预览改用同一个生产 wrapper，不再引入开发专用旧 Q 副本；8/9/0/P 可查看
  额外原生骨骼动作，F 显式播放保留的 morph 诊断并临时交接眨眼控制，退出后恢复原值。
  引擎回归实际驱动 F→walk、四个原生诊断及两次 R 重绑；检查 morph 恢复、眨眼控制交还，
  且不销毁 Q 自己的播放器。
- `imported_placement_test.gd` 保留原尺寸/贴地容差，分别验证课堂 Q 与同伴使用批准源的
  实测高度 **1.78449 m**；额外验证胶囊高度/半径与底面，不能将新模型缩回退役模型的
  1.6466 m 来让旧 fixture 通过。

## 6. 资源退役

删除旧生产 `assets/models/q/q.glb{,.import}`、开发 `q_rigged.glb{,.import}`、
旧 Q 的未绑骨输入、`.blend` rig workfile/build report、旧 rig/component audit md/json。
更新共享 audit README、manifest、模型库、资产台账与动作文档。
保留共享动画代码、主角开发 retarget 模型/UAL 验证资源；UAL 及其衍生物始终开发专用，
不从本次 Q 批准中获得生产放行。旧文件只可在固定基线 Git 历史中读出做 before 对比。

`docs/ASSET_PROVENANCE.md` 的 Q 段落与 #199 同文件编辑已获 Owner 明确授权。
#201 后来接替 #199 并由 main 合入；本任务发现 main 移动后暂停，并取得 Owner 的
新基线正常整合授权。唯一文本冲突是相邻的共享 look / rejected-review 台账行：
保留 Q 的新模型路径，逐字保留 #201 的 retired experiment 记录；其余清理及
`capture_playthrough.gd` 修复与新基线一致。不自行合并 #199，不重启被否决实验。

## 7. 验证与实际画面

本节区分证据层级并保留失败记录。独立草稿 [PR #202](https://github.com/BrainEno/where-is-school/pull/202)
的「验证结果」列出最终 head SHA 及对应的最新 CI；下列历史 run 不冒充最终 head 通过。

### 已执行的静态检查

- `python3 tools/prepare_q.py --check`：通过。
- `python3 tests/q_model_prepare_test.py`：7 项通过（源 SHA、可复现、网格/skin/morph
  保真、六动作所有非 rest 通道、双手 30 加权指骨、材质修复、旧 Q 退役）。
- `python3 tools/model_library.py --check`：通过；26 个模型 / 11 类，Q 为 980.7 KiB，
  超过 384 KiB 提示线但低于 1536 KiB 硬上限；另有既存模型大小提示。
- `python3 tests/model_library_test.py`：146 项通过，包含预期拒绝的损坏 fixture 输出。
- look 生成检查、UID audit、仓库 12 MiB 上限、action SHA pins 及 diff 空白检查通过；
  初始树 233 份 GDScript grammar parse 通过，新基线清理后现存 228 份重新检查。
  UID audit 的已有非规范值仅报告不冒充本次清理目标；本次新增脚本均带规范 sidecar。
- `tools/subset_font.py --check` 在固定 fonttools 4.58.5 下通过；第二轮新诊断文字曾使
  Sans 缺少「擎」，已将该脚本的控制台输出恢复为其惯用英文，而非改游戏字体或跳过检查。

### 本地源码引擎，不是官方 standard/图形验收

官方二进制在本地下载遇 EOF；精确 `4.7.2-stable` 源码构建完成，实际版本输出
`4.7.2.stable.custom_build`，为 dummy-renderer/无 fontconfig 的环境构建。
本地 Q、已有角色动画、主角、导入资源、双位置、运行时动画、门口注视、QPresence、
同伴路线/障碍、自动交互、导航、场景切换、smoke 共 14 项通过。
`q_model_test.gd` 的新增预览 F/morph/眨眼/反复重绑及真实课堂/同伴对话均实际执行。

不能隐去环境/既有噪声：首次导入的字体顺序错误、缺 fontconfig 的编辑器错误与旧资产
导入提示均在本地日志；小 viewport 的 Q/主角肖像空间不足 warning 仍出现。
`opening_resume_test.gd`（其内部注册了 Q intro lifecycle）另实际通过、Q 生命周期
0 problems，但输出既有 missing settings key / invalid UI polygon 等引擎 ERROR，
不能写成「无错误运行」。误把 Node 型 `q_intro_lifecycle_test.gd` 当 SceneTree
单独运行曾失败；正确入口是 `opening_resume_test.gd`，未修改测试继承来掩盖误用。
该辅助库现已按 #216 更名为 `tests/q_intro_lifecycle_support.gd`，仍由上述入口调用；
这里的旧文件名只记录当时的误用，不是运行指令。

### 官方 Godot 4.7.2 Stable standard 的阶段性 CI

| 源 head / run | 实际结果，不扩大结论 |
|---|---|
| `a71aa5f…` [Godot CI 43830355329](https://github.com/BrainEno/where-is-school/actions/runs/43830355329) | 导入、Q/native/reset/真实对话及其他多数检查通过；总 job **失败**：`imported_placement` 仍断言退役 Q 身高；`destination_cue_lifecycle` 三项点击标记断言失败。前者已按批准源更新精确期望、保留容差并加强胶囊检查，后者未改/未跳过。 |
| `a71aa5f…` [Playthrough 43830355289](https://github.com/BrainEno/where-is-school/actions/runs/43830355289)、[Release build 43830355510](https://github.com/BrainEno/where-is-school/actions/runs/43830355510)、[Character art capture 43830355352](https://github.com/BrainEno/where-is-school/actions/runs/43830355352) | 流程、双平台导出/校验/打包、既有五组摄影通过；仅 tag 发布步骤跳过。不是发行授权，也不是本次 Owner 美术签收。 |
| `a71aa5f…` [Q evidence 43830355346](https://github.com/BrainEno/where-is-school/actions/runs/43830355346) | before/after 实际导入/编译成功，各取得 12 张预览；严格日志门失败，编码器缺失 exit 127。首轮不是完整成功证据集。 |
| `f574509…` [Godot CI 43833137106](https://github.com/BrainEno/where-is-school/actions/runs/43833137106) | display/input 通过；gameplay job 在字体 coverage 处失败，后续 headless **未运行**，不可借用上一轮通过。 |
| `f574509…` [Q evidence 43833137147](https://github.com/BrainEno/where-is-school/actions/runs/43833137147) | 两阶段导入/编译与脚本断言通过：before 15 张、after 20 张 full-size still，分别恢复了 12 / 13 张真实预览；实际连续行走视频编码成功。但总体仍 **失败**：`ERROR: Condition "status < 0" is true. Returning: ERR_CANT_OPEN`，匹配固定引擎 ALSA 初始化在无声卡 runner 上的失败。本次将取证命令显式设 `--audio-driver Dummy`，保留真实 OpenGL 渲染、运动及严格 ERROR 门，不过滤错误冒充通过。 |

`destination_cue_lifecycle_test.gd` 在本地固定基线只读 archive 与工作树中各运行两次，
都重现相同三项 floor-click mark 失败。这个结果仅证明本地源码引擎上的基线重现；
摄影 workflow 还在两个源 SHA 上原样运行该测试以取得官方 standard 对照。
它独立于 render/encoder 步骤、照常产生失败结论，不忽略、不降级、不改无关输入实现。

### 可复现的真实画面与证据位置

`tests/capture_q_migration.gd` / `.github/workflows/q-model-capture.yml` 使用同一摄影脚本：

- before：固定开发基线的只读 `git archive`，仅复制摄影脚本；
- after：PR head，而非 GitHub 合并预览树；同一真实 `main.tscn`、课堂/走廊、原有灯光，
  不修改主角资产/C 方案、不使用生成图片冒充画面；
- 正/侧/背 idle、掌面五指、颈肩正侧、真实 `NpcActor.walk_along()` 连续 48 帧，
  实际说话人对话、与未修改主角同框及游戏相机；
- 原生转头/手势、坐下/起身/挥手、供应的 pose preview，以及清除骨骼动画的
  **supplied-rest 肩部诊断**（明确是诊断，不替代动态测试）；
- 真实 `LocationHost` 进入走廊，由 `CompanionController.join()` 生成第二个生产位置；
  摄影其实际游戏相机同框与 `q_after_dismissal` 对话，不在摄影棚复制另一个 Q；
- ffmpeg 仅编码实拍序列，ffprobe 强制检查 **48 帧 / 24 fps**，另保存视频 SHA-256；
- full-size still、48 个原始行走帧、`walk.mp4`、manifest 和全部日志保存在对应 CI
  的 `q-migration-before-*` / `q-migration-after-*` artifact（保留 30 天），不提交生成大文件。
  manifest 标明源 SHA、官方引擎/renderer、每张原图 SHA-256；API notices 是有损缩小预览，
  不能当作 full-size 原图，也不以“有图”覆盖日志失败。

第二轮真实 artifact：[before](https://github.com/BrainEno/where-is-school/actions/runs/43833137147/artifacts/14210440396)、
[after](https://github.com/BrainEno/where-is-school/actions/runs/43833137147/artifacts/14208844139)。
它们是 `f574509…`/固定基线的阶段性证据，不包含后续新增的同伴摄影/视频帧数断言。
当前沙箱无法下载 Actions 的 signed-storage 日志/完整 artifact（EOF）；已通过 check-run
annotations 恢复真实预览，Owner 可在 Actions 页面下载原图/视频，不能声称本地看过不可访问的视频。

## 8. 结构缺陷、限制与人工验收

**尚无 Owner 人工视觉签收，暂不建议合并。** 自动骨骼/track/数值检查不能证明
五指美观、肩颈连接自然、完全无穿模、脚底不滑或主角同框协调。

### 实际发现的源模型问题（未擅改几何）

1. **肩顶/袖身接合处露出皮肤、小缺口/硬折线。** 第二轮 `06_neck_shoulders_front`
   与 `19_supplied_rest_shoulders` 对比：清空骨骼动画、恢复 supplied rest 后仍存在。
   因而不能归结为“旧骨名套错”或仅调 posture 就宣称修好；保真准备脚本没有移动顶点，
   C 主着色器也不位移身体表面。Body/Hoodie 各自重复位置顶点的 skin 权重一致
   （最大 L1 差为 0），未找到该类 seam-weight mismatch；这不等于所有权重均完美。
   **影响：** 肩部近景、抬手/侧身时像开肩缺口，不满足自然连贯的完整卫衣预期。
   **可行后续：** 若 Owner 授权，单独修补服装肩部覆盖/接合并重新核对 skin/deformation；
   不是冻结手臂、强制遮挡相机或把皮肤随意改成绿色。本任务不擅自重塑批准源。
2. **双手是低多边形简化掌形。** 新掌面照片能分辨每手五指，拇指从掌侧伸出；
   原生手势确实驱动右手 15 个指节，pose/reset 覆盖双手。
   这不证明指根皮肤、拇指对掌、握拳弯曲已经自然；需看 full-size 与连续动作。
   首轮侧缘手照不能用于五指判定，已换按真实掌面法向拍摄。
3. 站姿/脚底正面照片已改用真实中央通道，避免旧摄影位置被桌面挡住；行走经过
   课堂家具时仍保留真实遮挡。没有通过删家具/换舞台来制造“贴地通过”。

### Owner 可复现清单

- [ ] 固定版本打开真实游戏，检查 Q 前后左右、足底贴地、头身比、灯光材质及主角同框。
- [ ] 近看双手五指、拇指方向、手腕及所有指节弯曲，观察 talk 手势与复位。
- [ ] 对照 supplied-rest / idle / 转头 / 抬手的肩部缺口，决定是否另行授权局部服装修补。
- [ ] 检查 idle / walk / jog / talk、talk→walk→talk→idle、挥手、坐下/起身，确认无异常拉伸扭转。
- [ ] 开场 Q 走到玩家、门口注视、对话说话人切换、同伴跟随/暂停/重入/存读档及走廊同框。
- [ ] 查看相同相机 before/after 原图与实际行走视频，区分脚本通过与人工审美签收。
- [ ] 解决/另行跟踪未改动的点击标记基线失败；本 PR 不将红色 CI 写成整体绿色。

现有局限保留：无 foot IK/planting、无 root motion/AnimationTree、无语音口型同步；
共享坐姿不会自动下降到任意座椅。此任务不扩大到主角美术、其他角色重构、#199 合并
或 #64 关闭。未获本任务合并、发布、打 tag 或关闭 issue 的授权。
