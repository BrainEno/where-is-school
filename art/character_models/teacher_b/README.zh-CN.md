# 生物老师 B — 独立角色审看

[English](README.md)

这是**供审看的资产**，不是剧情摆位或发行批准。用户立绘仅作造型参考：没有入库、没有用作纹理，也没有再制成对白肖像。立领、薄窄轮廓、灰白侧梳低髻、冷峻眉眼以及玳瑁框眼镜是本轮对立绘的解读。直筒裤与平底鞋超出立绘范围，暂定。

## 审看与编辑

- 用 Blender 4.5 LTS 打开 [`teacher_b.blend`](teacher_b.blend)。源文件以米为单位，并按皮肤、发型、眼镜、衣装、裤鞋分组；可单独编辑。打开叠加层，选中骨架进入姿势模式。时间轴 **1** 为绑定姿势、**24** 为屈肘和屈指、**48** 为迈步。这些是检查变形的定格，并非正式动作。镜片、镜框、镜腿、铰钉、发髻和耳环是独立几何。
- 在 Godot 打开 [`teacher_b_review.tscn`](../../../scenes/dev/teacher_b/teacher_b_review.tscn)，按 **F6**。打开即播放 B 的专属待机。点底部按钮或按 **7**（待机）、**8**（短步）、**9**（抬手讲解）；**空格**暂停／继续，**R**从头。想看游戏距离时先按 **6**，再选 **7–9**。
- **1–6** 依次为全身、脸、背面、屈肘/手指、迈步定格、游戏镜头。**←/→** 旋转；在第 1、2、6 镜按 **Tab** 可切换 B 与现任主角 `Protagonist_Character`；**M** 切换 B 的哑光绘制材质与 GLB 原材质。两者用相同的站点、教室灯光和镜头尺度，脸部只按身高差上下重构图。
- `scenes/dev/teacher_b/teacher_b.glb` 以米为单位，**+Y 向上 / −Z 朝前**；冠顶 **1.640 m**、鞋底 **0**、原点在左右踝中心线上。一个 **57 关节**骨架，四影响归一化权重、逆绑定矩阵、顶点着色与两个眨眼形变。49,686 三角、13 蒙皮表面、12 材质，透明镜片与镜框分别批组。GLB 没有镜头、灯光、贴图、碰撞或动作。现有面部形变和下颌骨不等于对白表演绑定。Godot 导入设置对原材质启用 GLB 的线性顶点色，审看材质覆盖时也保留这些颜色。

不改正式房间、`BPresence`、对白、主观印象、`q_wake` 或 `b_on_stage`。审看场仅复用原教室的布景与灯光，并移除原场景的角色、互动和导航分支。源文件和审看目录按现有规则排除于发行包之外。三角数只是规格，请用脸、衣装接缝、手势和游戏距离可读性评估效果；对照是**现任主角**而不是已改作坐姿学生的旧 `protagonist.glb`。

## B 专属动画

[`teacher_b_motion.tres`](../../../scenes/dev/teacher_b/teacher_b_motion.tres) 是 Godot `AnimationLibrary`，不是套用主角步态。开发场的 `AnimationPlayer` 定位 B 导入后的骨架，把原生动画轨直接绑定到各关节。剧情不驱动这套动画；GLB 和 Blender 检查定格未改。

| 动作 | 表现 | 播放 |
|---|---|---|
| `idle` 待机 | 重心略偏、轻呼吸，微转头 | 3.8 秒循环 |
| `walk` 短步 | 轻摆手臂，走四个短步后站稳 | 2.9 秒，沿 −Z 前进 0.90 m，单次 |
| `explain` 抬手讲解 | 左肘、手腕和独立指节动作，两次轻点后收手 | 3.2 秒，单次 |

短步是带起步、前进、停步的审看动作，不是原地循环步态，也未接寻路。根骨位移与旋转先按 30 Hz 烘焙后再减关键帧，着地按实测腿长和鞋底几何离线求解。三段动画写入同一组轨道，切换不残留根骨位移或蜷曲手指。动画源为 [`build_teacher_b_motion.py`](build_teacher_b_motion.py)；用 NumPy 2.2.6 执行 `python3 art/character_models/teacher_b/build_teacher_b_motion.py` 可重建，带 `--check` 可校验，无需 donor 或 Blender。

## 来源与权利

造型配方为本项目制作。脸与手的底拓扑、形体偏移、关节位点和初始蒙皮遮罩，仅使用 MakeHuman v1.3.0 固定提交 [`1f508f6083b2f823dab15de924b3bde72e08d77c`](https://github.com/makehumancommunity/makehuman/tree/1f508f6083b2f823dab15de924b3bde72e08d77c) 的 **CC0 1.0 数据**，见[固定版本的许可划分](https://github.com/makehumancommunity/makehuman/blob/1f508f6083b2f823dab15de924b3bde72e08d77c/LICENSE.md)。输入为 `makehuman/data/3dobjs/base.obj`（只取 `body`）、配方中列出的 `targets/` 偏移、`rigs/default.mhskel` 和 `rigs/default_weights.mhw`。没有再分发 MakeHuman 程序、界面、成品角色、头发、衣服、皮肤贴图、眼球或动画。眼镜、头发、衣片、相应蒙皮与着色以及审看姿势与三段动作在本项目中制作。供体 CC0 不代表用户立绘及其公开使用权利已核清。附件和供体包不入 Git；发行使用仍须所有者同意。

## 重建和验证

把[固定数据包](https://codeload.github.com/makehumancommunity/makehuman/tar.gz/1f508f6083b2f823dab15de924b3bde72e08d77c)解压到仓库外。`DONOR` 指向其中的 `makehuman/data`，`PARTS` 指向一个临时 `.glb`。用 Python 3.11、NumPy 1.26.4 在仓库根目录运行：

```sh
SRC=art/character_models/teacher_b
OPENBLAS_NUM_THREADS=1 python3 "$SRC/build_teacher_b.py" --makehuman-data "$DONOR"
OPENBLAS_NUM_THREADS=1 python3 "$SRC/build_teacher_b.py" --makehuman-data "$DONOR" --split-parts --output "$PARTS"
blender --background --python-exit-code 1 --python "$SRC/make_blender_source.py" -- --parts "$PARTS"
```

Blender 源文件脚本使用 Blender 4.5 自带的 `bpy` 与 `mathutils`，不要求把 Blender 装进项目的 Python 工具虚拟环境。

Python 配方生成批组后的审看 GLB；`.blend` 为可编辑的配套源。若直接在 Blender 修改，请回到帧 1，导出时排除审看片段，并重查尺寸、材质、绑定与姿势后再替换 GLB。可用 `--render-dir builds/teacher-b-review/studio` 渲染拆件源的检查图，再用 `compose_review.py --studio-only` 排版（Pillow 11.3.0）。

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/teacher_b_review_test.gd
godot --headless --path . --script res://tests/b_reveal_timing_test.gd
godot --path . --resolution 1120x720 --rendering-method gl_compatibility \
  --script res://tests/teacher_b_review_test.gd -- --capture
```

最后一条命令需要窗口。CI 使用项目锁定的 Godot 标准版与软件 OpenGL，在 `Teacher B asset review` 工件保留原始帧、定格对照、`teacher-b-motion.webp` 动图和日志。测试在审看短步中对实际蒙皮鞋底跨关键帧取样；这不验证导航、坡面、走路混合或剧情进场。美术验收、Godot 眨眼和对白口型需另验。
