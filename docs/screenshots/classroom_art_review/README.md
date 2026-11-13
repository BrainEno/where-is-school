# 教室美术草稿：实际运行证据与未完成验证

> **这是暂停实现时保存的证据，不是最终 PR head 的视觉验收。**
> 所有 PNG 都来自 Godot 的真实 viewport，按原字节复制，未重编码、调色、绘制或生成。
> `after-intermediate/` 拍摄后又移除了学生桌椅上不适用的反向外壳描边，并修正了纹理生成器的 UID 编码；
> 这两项之后尚未重新截图、重建 sidecar 或跑完整回归。按所有者要求先以草稿 PR 公开当前工作，不把旧结果算作最终通过。

## 版本与环境

- 修改前：开发基线 `fcafc6d91dd07a703e9448dd7fdecd45dc2a559d` 的 `git archive` 副本；只加入相同的截图／像素测试夹具，未加入新美术或 fader 修复。
- 修改后：本分支的提交前中间工作区；**没有对应的已提交 head SHA**，不能当作最终提交的截图。
- Godot：`4.7.2.stable.custom_build`，由官方 `4.7.2-stable` 标签源码构建，标签提交 `ed1daf0bf001b61586d9930840f2f1394092c079`；不是下载的官方预编译标准版。引擎源码与可执行文件未为测试修改；构建关闭 fontconfig。
- 实际绘制：Forward+、Vulkan 1.3.0、SwiftShader Device (Subzero)，Xvfb 1.20.10 / Xrender 0.11，X11。
- 此环境用仓库外的 Xlib→XCB WSI 适配器连接软件 Vulkan 和 Xvfb。适配器只负责原生窗口接口，不生成画面；工具、驱动、引擎不入库。
- 画面为 1600×900；软件 GPU 不能证明 Windows 目标 GPU 的画质、性能或稳定性。
- Compatibility 初始化实际失败（EGL 版本不足／ANGLE Vulkan 初始化错误），见日志；Mobile 未验证。

## 截图夹具的边界

`tests/capture_classroom_art.gd` 加载真实 `main.tscn`，保留房间布局、碰撞、导航、交互和游戏镜头。
夹具关闭开场自动播放，清除尚未结束的起床黑幕／姿态，将既有 N 节点显示在既有讲台标记处，便于同时查看角色与道具。
**N 在该场景中仍是带名字的占位胶囊，不是教师正式模型的美术验收。**

前三张用游戏 CameraRig，第四张用固定的美术审查相机。它们不是完整剧情 playthrough，也不代表所有者人工验收。
截图夹具会拒绝接近单色的遮挡帧；第一次被起床黑幕盖住的无效截图已排除，未复制到本目录。

| 视角 | 修改前（精确基线） | 修改后（中间态，非最终 head） |
|---|---|---|
| 游戏镜头，主角／Q／N 占位与主要道具 | [01_gameplay.png](before/01_gameplay.png) | [01_gameplay.png](after-intermediate/01_gameplay.png) |
| 南墙遮挡避让 | [02_wall_occlusion.png](before/02_wall_occlusion.png) | [02_wall_occlusion.png](after-intermediate/02_wall_occlusion.png) |
| 离开遮挡后的恢复 | [03_walls_restored.png](before/03_walls_restored.png) | [03_walls_restored.png](after-intermediate/03_walls_restored.png) |
| 黑板、原横幅区域、讲台与 N 占位 | [04_board_and_teacher.png](before/04_board_and_teacher.png) | [04_board_and_teacher.png](after-intermediate/04_board_and_teacher.png) |

逐帧 SHA-256、引擎、适配器和遮挡／恢复材质状态保存在 [修改前清单](before/CAPTURE.txt) 与 [修改后中间态清单](after-intermediate/CAPTURE.txt)。
两个截图命令都退出 0，但修改前有 2 个、修改后有 4 个 ObjectDB 实例泄漏，两者均有 1 个资源未释放的 `ERROR`；不能称为干净运行。

## 墙面根因：实际像素对照

`tests/classroom_wall_render_test.gd` 在两个 256×256 SubViewport 中绘制相同白墙：
一份用 18% 不透明度的单次材质混合做对照，另一份由真实 CameraOccluderFader 的物理遮挡射线触发淡出。
取中央 32×32 像素红通道均值，容差为 0.025。均值是屏幕色值，不直接等同线性不透明度。

| 运行版本 | 对照均值 | fader 均值 | 误差 | instance transparency | 材质 alpha / mode | 退出码 |
|---|---:|---:|---:|---:|---|---:|
| 精确基线，旧 fader | 0.46275 | 0.19608 | 0.26667 | 0.82 | 0.18 / 1 | 1（预期暴露缺陷） |
| 修复后的中间工作区 | 0.46275 | 0.45882 | 0.00392 | 0.82 | 1.00 / 0 | 0 |

旧路径在 Forward+ 同时使用实例透明度与材质 alpha，目标 18% 不透明度被叠乘为 3.24%。
最小修复只在 Forward+ 保留实例淡出，不再替换作者材质；Mobile／Compatibility 保留原有材质 alpha 回退。
射线、速度、交互逻辑、全局 Shader 与其他地点场景未改。共享脚本修改是在真实运行确认根因之后，按所有者的条件授权执行。

- 修改前：[对照像素](pixels-before/reference.png)、[旧 fader 像素](pixels-before/fader.png)、[数值](pixels-before/RESULT.txt)、[完整日志](logs/pixels-before.log)。
- 修改后中间态：[对照像素](pixels-after-intermediate/reference.png)、[新 fader 像素](pixels-after-intermediate/fader.png)、[数值](pixels-after-intermediate/RESULT.txt)、[完整日志](logs/pixels-after-intermediate.log)。
- 修复后像素命令虽然退出 0，仍有 2 个 ObjectDB 实例泄漏与 1 个资源未释放的 `ERROR`。

## 已执行命令

下面保留实际命令的参数；`GODOT_BIN` 指向上述本地源码构建，机器绝对路径只用环境变量表示。
在精确基线副本与修改后工作区分别执行；渲染环境变量／显示服务由仓库外工具配置。

```sh
# 基线副本
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 640x480 --script res://tests/classroom_wall_render_test.gd -- --output=build/classroom-evidence/wall-probe-before-forward
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1600x900 --script res://tests/capture_classroom_art.gd -- --output=build/classroom-evidence/before-forward

# 修改后中间工作区，最后两项修正之前
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 640x480 --script res://tests/classroom_wall_render_test.gd -- --output=build/classroom-evidence/wall-probe-after-forward
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1600x900 --script res://tests/capture_classroom_art.gd -- --output=build/classroom-evidence/after-forward

# 更早的整组检查：发生在共享 fader 修复之前，不是当前 head 的结果
GODOT_BIN="$GODOT_BIN" bash tests/run_classroom_checks.sh
```

整组检查当时是 24 项中 23 项给出 PASS，整体退出 1；`classroom_visual_slice` 有 46 条双重 alpha 断言失败。
[完整套件日志](logs/suite-before-fader-fix.log) 与 [引擎噪声统计](logs/engine-noise-before-fader-fix.txt) 保留失败、警告与资源泄漏。
尚未完成基线整组噪声对照，不能把这些错误统称为既有噪声。

## 当前草稿的明确阻塞项

1. 最新 UID 编码修正尚未重建 `.import`。开 PR 时实际运行 `python art/classroom/paint_classroom_textures.py --check`（Pillow 11.3.0 / NumPy 2.2.6）退出 1：`Import settings drift: wall_north.png.import`。未为开 PR 隐藏或修复该失败。
2. 学生桌椅去掉不适用描边之后的最终截图、最终 head 的 24 项回归、真实 `interaction_outline_occlusion_test.gd`、整组基线噪声对照仍未运行。
3. Compatibility 初始化失败日志见 [compatibility-initialization-failure.log](logs/compatibility-initialization-failure.log)；不能以 headless 或 Forward+ 的结果替代。
4. 开发基线仍固定为 `fcafc6d91dd07a703e9448dd7fdecd45dc2a559d`，未 rebase。暂停时的并行 PR #133 已合并；开 PR 时观察到 main 为 `35357848d1361d7b3983ed672742b32e9ab7c776`，较基线前进 47 个提交，并同改 `docs/ART_BIBLE.md`、`docs/ART_BIBLE.zh-CN.md`、`docs/ASSET_PROVENANCE.md`、`scenes/locations/classroom/classroom.tscn`。尚未集成验证，不覆盖这些新变更。
5. 教师正式模型、Windows 目标 GPU 与所有者视觉验收未验证。当前证据不支持“全部验收完成”或“建议合并”。

日志只将本地机器路径前缀规范化为 `$REPO`、`$BASELINE`、`$TOOLS`，并去除两行套件摘要的行尾空格；不删减行、错误或警告。
当前目录仅收录有说明和链接的少量运行帧；完整构建、缓存、驱动、无效帧与工具生成的无关导入元数据不入 Git，遵循 ADR 0007。
