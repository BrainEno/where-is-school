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
| `assets/models/q/new-Q.glb`（唯一生产整理版） | 1,004,268 | `be670a4056f51db612653a868bff6d701a968d4b1ab19d85cafad55de92b46f1` |

源上传 commit `f9aa19d4fa8ad56b0e4d2e46c48c799d10ffbb42`，blob
`0d71fcf65cf76fa7abe7124cba7f74fbfa02efb9`。开发基线固定为
`580f6f34d3ff4e56f3d00d67cf115a98e63cfdbf`。不使用旧 Q 的 Blender/Python
制作链描述新 Q，也不将技术准备脚本称作新模型的几何生成器。

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

`python3 tools/prepare_q.py` 固定验证原始 SHA，并且只：

1. 移除 `Q_SkeletonPreview` 展示节点、网格与 `BonePreview` 材质（1,440 顶点 /
   480 三角形）；它们不是角色身体。
2. 从六个动作中删去 831 条恒等于实际 rest 的 LINEAR/STEP 通道，保留每个非 rest
   通道及所有六个动作；不删除手指动画。余下 70 条通道。
3. 给原文件缺少 `baseColorFactor` 的十二种材质补上现有 Q 调色，不添加贴图。
4. 逐字节复制有效 accessor/view 数据并紧凑打包，正确保留 sparse morph。

没有移动顶点、重拓扑、改变法线/权重/骨架层级/rest/inverse bind/morph 或更改源动作 key。
`tests/q_model_prepare_test.py` 对每个相关数据数组逐一与批准源比较，而非只看文件大小。

新网格为 `Q_Body`、`Q_Eyes`、`Q_Feet`、`Q_Hair`、`Q_Hands`、`Q_Head`、`Q_Hood`、
`Q_Hoodie`、`Q_HoodieDetails`。`q_look.tres` 的映射迁移到实际
`Q_Mat_{SkinBody,Trousers,Sclera,Iris,Pupil,Shoes,Sole,Hair,Skin,MouthInner,Hoodie,HoodieRib}`。
保留既有 C shader/调色系统，仅调整 Q 的材质名、脸颊 patch 坐标、新眨眼名与局部轮廓：
双手不加会粘合手指的厚外壳，头部共享 skin/hair 表面按材质分别处理。

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

## 6. 资源退役

删除旧生产 `assets/models/q/q.glb{,.import}`、开发 `q_rigged.glb{,.import}`、
旧 Q 的未绑骨输入、`.blend` rig workfile/build report、旧 rig/component audit md/json。
更新共享 audit README、manifest、模型库、资产台账与动作文档。
保留共享动画代码、主角开发 retarget 模型/UAL 验证资源；UAL 及其衍生物始终开发专用，
不从本次 Q 批准中获得生产放行。旧文件只可在固定基线 Git 历史中读出做 before 对比。

`docs/ASSET_PROVENANCE.md` 的 Q 段落与 #199 同文件编辑已获 Owner 明确授权；
不合入 #199，不覆盖其无关清理，不重启 rejected review 实验。

## 7. 验证与实际画面

### 已取得的证据

- `python3 tools/prepare_q.py --check`：通过。
- `python3 tests/q_model_prepare_test.py`：7 项通过（源 SHA、可复现、网格/skin/morph
  保真、六动作所有非 rest 通道、双手 30 加权指骨、材质修复、旧 Q 退役）。
- `python3 tools/model_library.py --check`：通过；26 个模型 / 11 类，Q 为 980.7 KiB，
  超过 384 KiB 提示线但低于 1536 KiB 硬上限；另有既存模型大小提示。
- `python3 tests/model_library_test.py`：146 项通过，包含预期拒绝的损坏 fixture 输出。

### 当前尚未取得的证据（不得与以上 Python 结果混淆）

固定 **Godot 4.7.2 Stable standard** 的导入、场景/动作/交互/headless 回归、最终 head CI
与真实渲染结果待补充。当前环境无法取得官方二进制；精确版本源码的本地 dummy-renderer
构建仍在进行，它不能产生视觉验收。未以旧提交绿色 CI 代替本次证据。

新增 `tests/q_model_test.gd` 进行真实引擎导入/材质/track/reset/指骨运动及 `q_wake`
对话切换测试。新增 `q-model-capture.yml` 在同一标准引擎、真实 `main.tscn` 下分别渲染：

- before：固定开发基线的只读 `git archive`，只复制同一摄影脚本；
- after：最终 PR head，不使用 GitHub 的合并预览树冒充 head；
- 正/侧/背 idle、双手近景、颈肩正侧、真实 `NpcActor.walk_along()` 连续 48 帧与视频、
  真实对话、与未修改主角同框及游戏相机、坐下/起身/挥手和额外原生动作；
- full-size 图像/行走帧/manifest/日志保存在 CI artifact，预览以标明 phase 的 annotation
  输出。manifest 记录源 SHA、引擎/renderer 与每张原图 SHA-256。

尚未运行成功前，上述是**验证实现**，不是“已生成画面”的声称。

## 8. 限制与人工验收

**尚无 Owner 人工视觉签收。** 自动骨骼/track/数值检查不能证明手掌/拇指/五指外观、
肩颈连接、穿模、脚底滑动或主角同框时的自然程度。没有用大规模几何修改遮掩问题；
如画面揭示源模型结构缺陷，应明确记录问题/影响/可行方案，而非冻结动画。

- [ ] 固定版本打开真实游戏，检查 Q 前后左右、足底贴地、头身比、灯光材质及主角同框。
- [ ] 近看双手五指、拇指方向、手腕及所有指节弯曲，观察 talk 手势与复位。
- [ ] 检查 idle / walk / jog / talk、talk→walk→talk→idle、挥手、坐下/起身，确认无异常拉伸扭转。
- [ ] 开场 Q 走到玩家、门口注视、对话说话人切换、同伴跟随/暂停/重入/存读档。
- [ ] 查看同相机 before/after 原图与行走视频，区分自动测试通过与人工审美签收。

现有局限保留：无 foot IK/planting、无 root motion/AnimationTree、无语音口型同步；
共享坐姿不会自动下降到任意座椅。此任务不扩大到主角美术、其他角色重构或 #64 关闭。
在实际引擎与视觉证据补齐前，**暂不建议合并**。
