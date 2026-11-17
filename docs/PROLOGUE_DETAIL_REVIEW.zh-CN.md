# 序章美术细节 review 与调整（2026-11-17）

## 基线与参考边界

- 开发基线及本轮复查的远端 `main`：`57362a25c49ac165a6f323f8857f820625b51d29`。
- 当前仓库 `BrainEno/where-is-school` 的 `gh pr view 296`、`gh pr view 230` 均返回无法找到该 PR；现有列表最高编号为 #205。因此不能声称逐项复刻 #296／#230。
- 实际参考：仓库现有 `visual_experiments` 拼贴实验、生物教室迁移，以及 `ART_BIBLE`、`CONCEPT_DIRECTION` 的手工图形／表现主义方向；对话框依据所有者本轮明确提出的“白底笔记本、左上角三角尺”。
- 本文不是已验收的最终美术规范，也不是游戏截图证据。Agent 模型：平台未显示，无法核实。

## Review 发现与处理

| 发现 | 原实现位置 | 本轮处理 |
|---|---|---|
| 坐着的同学仍使用旧主角模型的原始材质，未接入其他角色的绘制管线；78 个分离表面容易呈现拼装感 | `scenes/environment/characters/classroom_student.tscn` | 接入 `CharacterLookApplier`；独立陶土色版画配色，全部表面使用原有绘画 shader，仅 5 个主要外部形体描边；眼、嘴、手指不单独勾黑边；衣摆做 8 mm 的局部 shader 收形 |
| 三名主要角色虽已有不同媒介，但外轮廓较厚，衣服明暗色温并不统一 | `art/characters/look_experiments.py` | 保留主角炭笔／Q 油彩／N 粉笔的区别；主要外部形体统一淡紫阴影、暖纸色受光，轮廓最多 8 mm，降低部分描画强度 |
| 三角尺不仅位置在左桌，交互支撑路径也绑定左桌；仅移动外观会留下错误拾取／遮挡契约 | `scenes/locations/classroom/classroom.tscn` | 移除左桌完整实例（含椅子和碰撞）；三角尺移到右侧讲台并匹配 8.75° 台面坡度；同步移动交互点、支撑路径和原讲桌检查点；稳定 id 不变 |
| 右讲台顶部原有纸张、点名册，会与三角尺重叠 | `scenes/environment/props/teacher_lectern.tscn` | 将纸张和点名册收入下层隔板，保留模型节点，腾出阅读面 |
| 英文讲桌检查仍描述已移除的椅子、订书机、杯子 | `data/inspections/en/classroom.json` | 中英文均描述现存讲台／三角尺／隔板；英文三角尺位置同步；不改回忆来源、记录 id、剧情旗标或效果 |
| 原对话框为深墨底，旧浅色强调色不能直接移植到白纸 | `scenes/ui/dialogue_panel.tscn`、`scripts/ui/dialogue_panel.gd` | 暖白活页纸、低对比横线、装订孔、叠纸边、左上角木三角尺；正文和选项换成深墨／赭红，角色浅强调色向深墨混合；保留测量布局、肖像、中文长文滚动及输入路径 |
| 场景想象力宜来自普通教学物的媒介越界，而不是在通道中加随机奇观 | 新增 `classroom_art/unbound_herbarium.tscn` | 左前墙加入撕纸生物挂图：错版红线、赭色圆片、叶片离开纸边并折向三维空间；静态场景组合，不增加碰撞、交互或故事结论 |

## 改动边界

- 不改人物 GLB、骨架、坐姿 clip、主角控制、Q／N 剧情、窗帘异常状态机、门和导航算法。
- 坐姿同学是材质／轮廓外观优化，不是重新制作高精度角色模型；旧模型的几何局限仍存在。
- 新挂图是教学美术装置，不是新增超自然事件或物种设定。
- 新绘图及场景均为项目原创代码／基本形体组合，没有下载贴图、外部生成图或新运行时依赖；来源边界见 `ASSET_PROVENANCE.md`。
- 更新中英文美术文档的对话框实现说明。字体子集按当前源码文本及固定 `fonttools==4.58.5` 重新生成，未更换字体源。

## 本地验证

### 已通过

- `python3 tests/prologue_details_test.py`：7 项离线契约测试；检查移桌与拾取支撑、讲台坡度和三角尺高度、78 个同学表面的调色表覆盖、选择性轮廓、资源可复现、文字颜色对比度、装饰不阻挡导航及资源引用存在性。
- `python3 art/characters/build_character_looks.py --check`：生成资源与调色表一致。
- `.venv/bin/python tools/subset_font.py --check`：两种字体覆盖及字节一致性通过。
- `.venv/bin/gdparse` 检查 `scripts/ scenes/ tests/ addons/` 下全部 244 个 GDScript 文件：通过，工具版本 `gdtoolkit 4.5.0`。这是独立语法解析，不是 Godot 的类型检查或资源加载。
- `.venv/bin/gdlint scripts/ui/notebook_paper.gd`：通过。
- `python3 tests/workflow_action_pins_test.py`：176 项检查通过。
- `python3 tools/godot_sidecars.py --check`：`UID_AUDIT=success`，仅检查已跟踪文件；仓库原有非规范 UID／缺少 sidecar 提示仍在，新增纸面脚本的 `.uid` 待引擎首次导入生成，未手工伪造。
- `python3 tools/repo_size.py --check`、`git diff --check`：通过。

### 未通过／未运行

- 对现有大型 `dialogue_panel.gd` 和 `dialogue_mode_bar.gd` 运行默认 `gdlint` 仍失败。与基线逐文件对照，报告类别及数量一致（脚本体量、声明顺序、既有超长行）；未为本轮任务重构整个 UI 子系统。
- **Godot 实际使用版本：无，未成功启动引擎。** 项目固定版本仍为 **Godot 4.7.2 Stable，standard**，没有降级或升级。
- 环境未安装 Godot。尝试从官方 GitHub release 下载 `Godot_v4.7.2-stable_linux.x86_64.zip`，以及 GitHub release asset API，均在跳转到 `release-assets.githubusercontent.com` 时出现 SSL 连接错误，受当前出站网络限制。
- `godot --headless --editor --path . --quit`、Godot 引擎测试、真实渲染截图、Windows 导出及 playthrough 均**未运行**，不推断通过。
- 已增强原有 `classroom_visual_slice_test.gd`、`imported_assets_test.gd`、`dialogue_layout_test.gd`，同步 `opening_flow_test.gd` 的三角尺取景位置；保留旧的行为保护，不再断言被用户要求删除的讲桌存在。新增 Python 测试接入既有 CI；远端最终 head 的状态以 PR 检查页为准。

## 引擎可用后的验证入口

```sh
godot --version
godot --headless --editor --path . --quit
python3 tools/godot_sidecars.py --after-import
# 按原 CI 的 run_check 规则审查日志，不只看进程退出码。
godot --headless --path . --script res://tests/imported_assets_test.gd
godot --headless --path . --script res://tests/classroom_visual_slice_test.gd
godot --headless --path . --script res://tests/dialogue_layout_test.gd
godot --headless --path . --script res://tests/dialogue_pointer_test.gd
godot --headless --path . --script res://tests/opening_flow_test.gd
# 有显示设备时，从真实游戏机位采集：
xvfb-run -a godot --path . --resolution 1600x900 --rendering-driver opengl3 --script res://tests/capture_prologue_art.gd -- only=start,front,q_close
```

## 所有者人工验收清单（尚未执行）

- [ ] 在 4.7.2 编辑器导入，确认新场景、CSG 叶片、纸面绘图及角色材质无资源／运行错误，补入引擎生成的脚本 UID。
- [ ] 开新局，比较游戏常规镜头中的四个人物；坐着的同学应保留坐姿、脚与椅子的关系，不应变成眼球／手指满是黑边的拼装玩具。
- [ ] 走过左侧原讲桌位置，确认桌、椅及不可见碰撞均已消失；前墙挂图不挡通道，不抢过 Q、门和窗帘的视觉重点。
- [ ] 从右讲台前方和两侧点击三角尺，确认人物能到达、轮廓只描三角尺，并打开原检查内容；点击讲台显示讲台内容，没有隔空操作原左桌的现象。
- [ ] 观察三角尺与斜台面接触，确认没有穿模、悬空及与纸册重叠；在 N 入场后复查。
- [ ] 与 Q、N 对话和检查物品，确认暖白纸、左上三角尺、深色文字、肖像和来源标签可读；三角尺不挡姓名。
- [ ] 1280×720、1600×900、1920×1080 和最大字体下检查中文长句、四个选项、滚动、键盘数字选择、鼠标点击、自动／快进及回看。
- [ ] 拉开窗帘并离开教室，复查原异常、过场、导航与存档回访；本轮不应改变这些剧情路径。

## 合并建议

**暂不建议合并。** 本轮已实现并通过离线检查，但美术任务必须补齐目标引擎导入、实际游戏帧和所有者视觉验收。若要求精确对照 #296／#230，还需要所有者提供可访问链接或截图。
