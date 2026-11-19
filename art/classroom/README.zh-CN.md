# 教室视觉切片：源文件与色彩系统

*English: [README.md](README.md)*

本目录存放教室绘画风格的**源文件**。目录内有 `.gdignore`，Godot 不会导入它；`export_presets.cfg`
也已把 `art/*` 排除在导出之外。

- `paint_classroom_textures.py` 负责绘制 `assets/materials/classroom/textures/` 下的全部 PNG，
  并为每张图写好 `.import` 配置文件。运行环境为 Pillow 11.3.0 + NumPy 2.2.6，重跑得到的文件逐字节一致：
  `python3 art/classroom/paint_classroom_textures.py`。只检查、不写文件可用
  `python3 art/classroom/paint_classroom_textures.py --check`。

教室里没有任何静态背景图。墙、地板、黑板、窗户仍然是原灰盒的 3D 几何体。
绘画以贴图形式画在一组四边形上，墙面四边形在实体前方 4 mm，地面四边形高于实体 3 mm，
并且挂在对应墙体节点下面，因此相机遮挡淡出时会跟着各自的墙一起淡出。

## 识别度：这间教室为什么是“这间”

教室空间扩大为 14 × 10 米，采用低饱和冷灰水泥地面、真正抬高并带上台阶的水泥讲台，以及
箱体结构、明显高于学生桌的站立式教师讲桌。12 组学生桌椅按四列三排布置，留出宽走道以及通往黑板、两扇门和剧情道具的路线。
面向黑板时，两扇门都在右手边的东墙上（#159）：靠近黑板的灰色前门是走廊出口，白色后门从来不会打开。
黑板墙是一整面完整的墙，黑板左半边上方装有一幅可拉下的投影幕，天花板下吊着一台投影仪。
西墙前窗是普通窗户；后窗是一个穿透墙体的洞，挂着一幅从天花板垂到地面的遮光窗帘。黑板上方保留空白，
原来的红色伪文字横幅及其生成代码已经删除。没有全屏“油画”滤镜。
墙和功能性道具保留 `StandardMaterial3D`（toon 漫反射、无高光）。学生课桌把照片式 PBR 表面
替换成教室自有的 `student_wood.tres`，只读引用既有环境颜料 Shader。
不再用透明罩色盖着照片底色／法线／ORM；模型和共享包装场景不变。

## 色彩系统（sRGB）

| 角色 | 颜色 | 用途 |
|---|---|---|
| 墨线 | `#2E2933` | 选定道具轮廓（反向外壳描边，6 mm）、墙面接缝、墙角、地面边线 |
| 剖面 | `#4F4754` | 墙顶和外侧面，让房间看起来像剖开的模型 |
| 灰泥 | `#CEC2BB` / 亮 `#E9D5AB` / 暗 `#9697A7` | 上半墙，宽大的竖向笔触色块 |
| 墙裙 | `#47656F` / 深 `#364555` | 1.05 m 以下的色带、踢脚线、窗框 |
| 地板 | `#7E848C` 基色／冷矿物灰 | 断续抹刀笔触、浅色磨损和柔和水泥斑驳；没有木板纹 |
| 水泥讲台 | 生物课教室实验的现浇水泥，不带地面的横线（`platform_concrete.tres`、`shaders/concrete.gdshader`） | 实际抬高 0.12 m，并带宽大的低台阶 |
| 黑板 | `#243D3F` + 粉笔 `#D6DCCE` | 前黑板（擦过又没擦干净）、后墙的旧黑板报 |
| 牛血红漆 | `#6E3C36` | 黑板框、讲桌前装饰条，也就是代表“权威”的物件 |
| 门灰／门白 | `#7D8287` / `#E6E3D9` | 两扇门的门板（`door_gray`、`door_white`），门框为墨青色（`trim_teal`） |
| 遮光藏青 | `#1B2441` | 后窗落地遮光窗帘（`curtain_blackout`） |
| 幕布哑白 | `#EDE6CC` | 可拉下的投影幕（`screen_matte`） |
| 杏橙 | `#E0A569` / 浅 `#EFCD97` | 不合时宜的傍晚光：窗景、溢到墙上的光、地面上的光斑 |
| 蜂蜜木 | `#A98458` | 讲桌柜体、粉笔槽，以及学生课桌的颜料锚点 |
| 旧木 | `#998775` | 学生椅，刻意压低存在感 |
| 芥末帆布 | `#BE963E` | 书包，玩家第一个要找的东西 |
| 钴蓝 | `#40568C` | 点名册封皮，保持可辨认但不使用亮面高光 |

### 层级规则

1. **大面保持安静**：墙和地面的平均色彩度不超过 0.20（平均 sRGB 颜色的最大分量减最小分量）。
2. **重要物件必须从背景里分离出来**：明度差或色彩度差至少达到 0.15。
   对照组包括：黑板对墙、书包对它挂着的椅子、窗对墙、三角尺和点名册对讲桌面、门框和白色后门对东墙、
   遮光窗帘对西墙、拉下的投影幕对黑板。
3. **重复家具不抢戏**：重复椅子的色彩度至少比书包低 0.15。
4. **墨线只画边，不当纹理用**：墨线只出现在轮廓、接缝和少量涂鸦上，
   不覆盖可行走地面，也不覆盖可交互物。

`tests/classroom_visual_slice_test.gd` 会在实际发布的贴图上测量以上四条规则。

## 图形标记，每一处都有理由

- **前墙**：黑板背后的剪纸式阴影、蹭到墙上的粉笔灰，以及门边有人画了一半就放弃的铅笔身高刻度。
- **窗墙**：前窗周围溢出的杏橙光和画出来的窗洞侧面。后窗是在墙体和墙面贴图上真实切出的洞，周围不画任何东西。
- **东墙**：两个门洞，以及两门之间撕掉通知后留下的浅色印子和残余胶带。
- **南墙**：一块彩色粉笔画的旧黑板报（叶子、鱼骨、小花，没有可读的字）。
- **黑板墙**：自 #159 起是一整面完整的墙；两扇门已移到东墙。
- **前黑板**：板擦弧线下残留的标题和日期栏痕迹，与检视文本一致
  （*LAST TERM — REVISION*，以及一个三周前的日期）。这些字迹刻意保持不可辨认，因此黑板不需要本地化。
- **黑板上方**：有意留白，不用另一组文字或符号装饰替换。
- **画出来的“缺席”（来自生物教室美术实验）**：两处平涂的紫墨色标记，不受光照（`ink_shadow_*.tres`，贴图由 `paint_classroom_textures.py` 绘制），画出来的影子不回应真实的灯光。`WallNorth/InkShadowFigure` 是一个教室里没有人投下的影子：高而佝偻、举着三角尺的人形，从讲台台面上沿前墙升起，位于讲桌旁。`Props/InkShadowSquare` 是三角尺拖长的影子，从讲桌下方的台阶脚一路越过地面，指到你的课桌（B2）前沿。它们只是布景：没有碰撞、不可交互，墙上的人影会随墙一起淡出。

## 检视文本 → 场景

| 文本描述 | 场景中的对应 |
|---|---|
| 黑板擦过又没擦干净；粉笔槽里有一截断粉笔和一个夹子 | `Board/Face` 贴图、`ChalkBrokenEnd`、`Clip`、粉笔槽上的粉笔灰 |
| 两块玻璃，一块裂了、用胶带补过；窗外是湿水泥地、矮墙、一排垃圾桶；傍晚的光 | `WindowGlass0`（裂纹 + 胶带）、`window_view.png` |
| （窗帘对白）前窗很普通，绳子上晾着衣服；后窗拉着窗帘 | `window_view.png` 只有窗 0 那三分之一（s 3.0–4.5 m）画了晾晒的衣服；`Anomalies/BackCurtain`（程序生成的 `WindowCurtain`，`curtain_blackout`）挂在离西墙 0.18 m 的轨道上，宽 3.3 m，从 3.14 m 垂到地面，遮住 z 0.95–3.45 的墙洞 |
| （窗帘对白）窗帘后面没有玻璃，只有墙的厚度，然后什么都没有 | `WallWest` 上真实的洞，从地面一直到墙顶（y 0–3.2；美术迁移时去掉了窗台和过梁，`paint_classroom_textures.py` 的 `WEST_VOID_OPENING` 只剩 z 范围仍有效）：墙壳和墙面只剩 `MeshInstance3D`（北段墙壳）/`SouthShell` 与 `Paint`/`PaintSouth`，洞后没有玻璃、窗框、窗景或背景板。窗帘拉开后，`Anomalies/VoidOpening/BlankSheet` 用实验里的空白纸（`void_sheet.tres`，不受光的纸面）填满墙洞，`Anomalies/PaperZone`（`scripts/environment/paper_zone.gd`、`paper_zone.tres`）把墙洞 2.6 m 以内的教室变成答题纸上的铅笔画——以覆盖层实现，窗帘复位时会撤掉；人物（`Actors`）永远不会被覆盖。墙的碰撞体保持完整 |
| 另一扇门从来不会打开，除非使用特殊的手段 | `WallEast/RearDoor`（`classroom_rear_door.tscn`，`classroom_door.tscn` 的白色变体），只是普通检视（`classroom_rear_door`）；不会打开，本教室不放置楼梯 |
| 三角尺有前臂长，清漆发白，裂开的角用已经变褐的胶带补过，补过的角朝向教室 | `set_square.tscn` 现在平放（0.55 × 0.42 m；原棱柱的尺寸轴写反了），`TapeRepair` 改为褐色胶带，并加了墨线刻度。低矮教师桌移除后，它放在讲桌倾斜的桌面上（`Props/SetSquare`，随桌面倾斜，压在点名册上） |
| 自己的课桌上有被刮掉的名字、撕了一半的贴纸、前沿一道磨出的凹槽 | `Furniture/DeskB2/DeskMarks` 贴花 |
| 讲台（`classroom_teacher_desk` 检视）：比课桌高很多，上面有塑料封皮的点名册、教案和三角尺 | `Stage/Lectern` 的 `Body/Register`、`Body/LessonPapers` 和放在上面的三角尺。低矮教师桌（`teacher_desk.tscn`）不再放进教室，包装场景仍保留在项目中 |
| 课程表上有咖啡杯印，老师名字被圆珠笔划掉 | `TimetableSheet/Face` |
| 书包是帆布的，只有一根背带 | 芥末色帆布、唯一的 `Strap`、一个侧袋；挂在你的椅背上（`Furniture/DeskB2/Chair/Schoolbag`），不在地上 |

## 材质与复用约束

`docs/ART_BIBLE.md` / `docs/ART_BIBLE.zh-CN.md` 中同步的教室章节记录了材质分级、色彩范围、
轮廓适用对象、笔触密度，以及后续地点的复用方式。墙体默认不透明、背面剔除并写入深度；
只有临时相机遮挡避让才允许淡出。Forward+ 只使用实例透明度，Compatibility/Mobile 则需要材质 Alpha 副本，
不能把两者叠乘。`tests/classroom_wall_render_test.gd` 将实际像素与单次 Alpha 对照比较；
`tests/capture_classroom_art.gd` 记录真实教室。两者在 `.github/workflows/classroom-art-evidence.yml` 中分别以 Forward+ 与 Compatibility 运行，各自独立裁决（#150，见 `docs/screenshots/classroom_art_review/README.md` 第 8 节）。玻璃仍是有意使用表面 Alpha 的例外。同样的任务还会运行 `tests/capture_classroom_clock.gd`（#173）：它从前墙时钟的渲染画面中读回时间，任何视角读不出九点即失败；重绘表盘（`assets/materials/classroom/clock_dial.tres`）或指针材质时，这项检查会如实反映可读性（见 `docs/screenshots/README.zh-CN.md`“教室时钟”一节）。

生成器采用 Godot 4.7.2 的规范 34 字符 UID 编码；真实导入后应再次检查 sidecar，防止编辑器改写。
策展后的实际前后截图、像素数值、基线噪声对照与平台限制见 `docs/screenshots/classroom_art_review/README.md`。
运行证据不能代替所有者美术审查或目标 GPU 验收。

## 空间与玩法契约

教室外壳为 14 × 10 米，墙高 3.2 米。每面墙都保留一整块碰撞体，洞口只切在可见部分上。北侧黑板墙是一整面 14 米的墙。
东墙有两个 1.2 × 2.2 米门洞，中心分别在 z −3.55（前门 `WallEast/FrontDoor`，灰色）和 z +3.55（后门 `WallEast/RearDoor`，白色），
都是所有者的门模型换上教室材质，门后有墙面；墙壳和墙面被切成长墙段、两端墙段和两块门楣，各自采样 `wall_east.png` 中对应的一段。
`classroom_door` 保留原 ID、受阻检视文本和走廊转场，位于前门前方。走廊在对应门位复用同一套灰色前门和白色后门变体。
只有前门触发转场，白色后门从两侧都只能检视。西墙以同样方式围绕后窗墙洞切分。
`WindowCurtainMount0` 与 `WindowCurtainMount1` 标记窗帘挂点（后者即遮光窗帘轨道）。投影幕（`WallNorth/ProjectorScreen`）在进入教室时是卷起的；
`Interactables/ProjectorScreenPull` 可以把它拉下、再卷上去，其状态不会存档。
书包挂在主角椅背上（`Furniture/DeskB2/Chair/Schoolbag`）；玩家在这把椅子上醒来（`PlayerStart`），Q 从过道稍远处出发，在第一句台词前走到玩家左手边的 `QOpeningTalk`（开场 Q 段落，#160）。讲台和台阶都有真实碰撞体：
抬高 0.12 米，低于玩家 0.25 米步高和导航网格 0.25 米爬升上限。低矮的普通教师桌已从教室移除，讲台上的站立式讲桌是唯一的教师家具；原教师桌检视（`front_desk` / `classroom_teacher_desk`）移到讲桌上（`Interactables/LecternInspect`），三角尺放在讲桌的倾斜阅读面上。
Q/N 状态、检视 ID、`Sun`、`WorldEnvironment` 和教室到走廊的转场均保留。

### 教师讲桌（#172）

`Stage/Lectern` 是 `scenes/environment/props/teacher_lectern.tscn` 的实例，替换了所有者否决的
“细柱顶圆盘”蘑菇形讲桌。新讲桌是大学教室常见的站立式讲桌：蜂蜜木柜体从地面向上
（两块侧板、朝向学生的封闭前板及牛血红装饰条、深色踢脚），教师一侧是两层开放储物格和
上方挡板；顶部是向教师一侧倾斜的阅读面，带挡书条、两侧围边和后沿，放着一叠教案和蓝色点名册。
只使用 Godot 基本网格和教室自有材质。

| 项目 | 数值 | 依据 |
|---|---|---|
| 柜体 | 0.80 宽 × 0.44 深 m；面板 0.90 × 0.52 m | CSULB Freedom One 讲桌 36.25 in 宽 × 30 in 深，略浅一些，让讲台后方留出通行空间 |
| 工作面 | 讲台面以上，教师一侧 0.96 m、学生一侧 1.04 m（倾斜 8.75°） | 现实讲桌 36–42 in（0.91–1.07 m，CSULB、MSU、UConn）对应约 1.75 m 成人；按 N 的 1.65 m 缩放后为 N 身高的 0.58，正好在肘部下方 |
| 碰撞 | `Body` 盒体 0.84 × 0.96 × 0.54 m | 会切出导航网格并挡住玩家；旧讲桌没有碰撞体。盒体顶部停在倾斜阅读面的低边，不会高出放在上面的三角尺，镜头到三角尺的视线保持通畅 |

讲桌自带两个挂点，其他地方不再保存它的坐标：`TeacherStand`（中心后方 0.54 m，位于讲台面）和
`WorkSurface`（阅读面教师一侧边缘）。`NEntryPath` 现在终止于此：先经过讲桌右侧（`BesideLectern`），
再沿讲桌后方（`BehindLectern`），最后一小步走到 `AtFront`，即 `TeacherStand` 所在位置。
`NpcActor.walk_along` 会让 N 朝向最后一段的行进方向，所以这一步朝向学生，N 最后面对全班而不是黑板。
`classroom_visual_slice_test.gd` 把 `AtFront` 固定在 `TeacherStand` 上，并检查工作面与 N 身高的比例、
N 不与讲桌重叠、头肩露出讲桌上方，以及行走路线不穿过讲桌。

`tests/classroom_visual_slice_test.gd` 保留此前颜色、贴图、检视、墙体淡出、相机和导航检查，并新增
尺寸、12 个座位、东墙两扇门、完整黑板墙、投影幕和投影仪、实体台阶/讲台、站立式讲桌及 N 的站位、窗帘标记及剧情初始位置验收。
`tests/capture_classroom_art.gd` 会生成十四张真实 1600 × 900 游戏视图，包括建筑构图、拉下的投影幕、后窗墙洞，以及四张讲桌画面（正面、侧面、教师一侧、游戏镜头）；
headless 画面会被拒绝。`Classroom visual evidence` PR 工作流用 Godot 4.7.2 Stable 渲染这十四张画面，
并将它们发布为可下载的 CI Artifact。
