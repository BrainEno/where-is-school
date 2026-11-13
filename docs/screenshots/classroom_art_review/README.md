# 教室美术：真实运行对照与回归证据

所有 PNG 均来自 Godot 的真实 viewport，按原字节复制，未重编码、调色、绘制或生成。当前帧已替换开草稿时的中间态截图；无效的起床黑幕帧从未作为验收证据收录。

## 1. 版本与集成范围

- 原开发基线：`fcafc6d91dd07a703e9448dd7fdecd45dc2a559d`。
- 经所有者明确授权后，将 `main` 的 `35357848d1361d7b3983ed672742b32e9ab7c776` 合入当前分支，未 rebase。保留了教师模型接线、英中视觉多元性章节，以及所有非教室来源条目；唯一的文本冲突仅以本任务的两行教室来源更新替换 main 中对应的旧行。
- 本次修改前截图：上述批准的 main 的 `git archive` 副本，只加入相同的截图／像素夹具，未加入本任务美术或 fader 修复。
- 本次修改后截图与完整教室套件：代码提交 `8f4c314f6ac0f1ad640ce80012b9cc16e91cd816`。后续证据整理只改文档；`SOURCE_CODE.txt` 记录场景、fader、截图夹具及环境 Shader 的实际哈希。最终 PR head 的 CI／复测状态以 PR 正文为准，不将历史结果冒充最终 head。
- 最早基线与中间态证据仍可从提交 `2305d00ea713cb24b7d2aa5118267ab0bceb0293` 的 Git 历史查看，当前目录不累积重复帧。

## 2. 环境与证据边界

- Godot `4.7.2.stable.custom_build`，由官方 `4.7.2-stable` 标签提交 `ed1daf0bf001b61586d9930840f2f1394092c079` 的未修改源码构建，关闭 fontconfig；不是下载的官方预编译标准版。
- 实际绘制：Forward+、Vulkan 1.3.0、SwiftShader Device (Subzero)、Xvfb 1.20.10 / Xrender 0.11 / X11，1600×900。
- 仓库外 Xlib→XCB WSI 适配器仅连接原生窗口接口，不生成像素。工具、驱动、引擎和构建缓存不入 Git。
- 夹具加载真实 `main.tscn`，关闭开场自动播放，完成起床黑幕／姿态的清除，将既有 N 显示在既有讲台标记处。主角、Q 与 N 使用批准的 main 中相同的正式场景接线；本任务没有修改角色模型。
- 前三张使用真实 CameraRig，第四张使用固定美术审查相机。它们不是完整剧情 playthrough，也不是所有者人工验收。
- 软件 GPU 不能证明 Windows 目标 GPU 的性能／稳定性。Compatibility 在本地仍无法初始化，Mobile 与目标 Windows GPU 的实际像素仍未验证；不要用 headless 或 Forward+ 代替这些结果。

## 3. 实际游戏画面对照

| 视角 | 修改前：批准的 main | 修改后：最终代码形态 |
|---|---|---|
| 主角／Q／N 和主要道具 | [01_gameplay.png](before/01_gameplay.png) | [01_gameplay.png](after/01_gameplay.png) |
| 南墙遮挡避让 | [02_wall_occlusion.png](before/02_wall_occlusion.png) | [02_wall_occlusion.png](after/02_wall_occlusion.png) |
| 离开遮挡后的恢复 | [03_walls_restored.png](before/03_walls_restored.png) | [03_walls_restored.png](after/03_walls_restored.png) |
| 黑板、原横幅区域和讲台 | [04_board_and_teacher.png](before/04_board_and_teacher.png) | [04_board_and_teacher.png](after/04_board_and_teacher.png) |

逐帧 SHA-256、材质状态：[修改前 CAPTURE](before/CAPTURE.txt)、[修改后 CAPTURE](after/CAPTURE.txt)。
源版本及哈希：[修改前 SOURCE_CODE](before/SOURCE_CODE.txt)、[修改后 SOURCE_CODE](after/SOURCE_CODE.txt)。8 张图片均已逐一校验清单哈希。

实际可见变化：原横幅和 pin 已从源场景删除；黑板粉笔痕迹、时钟、讲台功能道具仍在；暖赭与蓝灰／紫灰色块取代过亮色面；学生桌椅去掉照片 PBR 及旧透明罩色，不在硬法线网格上强行扩大反向外壳描边。没有改变房间布局、碰撞、导航或剧情。

截图命令均退出 0，但不是无引擎噪声：修改前有 4 个、修改后有 2 个 ObjectDB 实例泄漏，两边都有 1 个资源未释放的 `ERROR`。见 [修改前日志](logs/capture-before.log)、[修改后日志](logs/capture-after.log)。

## 4. 墙面根因：实际像素对照

`tests/classroom_wall_render_test.gd` 在两个 256×256 SubViewport 中绘制相同白墙：一份用 18% 不透明度的单次材质混合做对照，另一份由真实 CameraOccluderFader 的物理射线触发淡出。
取中央 32×32 像素红通道均值，容差 0.025。均值是屏幕色值，不直接等同线性不透明度。

| 版本 | 对照均值 | fader 均值 | 误差 | instance transparency | 材质 alpha / mode | 退出码 |
|---|---:|---:|---:|---:|---|---:|
| 批准的 main，旧 fader | 0.46275 | 0.19608 | 0.26667 | 0.82 | 0.18 / 1 | 1，预期负向对照 |
| 本分支修复后 | 0.46275 | 0.45882 | 0.00392 | 0.82 | 1.00 / 0 | 0 |

旧 Forward+ 路径将 18% 实例不透明度与 18% 材质 alpha 叠乘为 3.24%。真实运行确认后，才按所有者条件授权修改共享 fader：Forward+ 不再替换作者材质，Mobile／Compatibility 保留原材质 alpha 回退。射线、速度、交互控制器、全局 Shader 和其他地点场景均未修改。

- 修改前：[对照](pixels-before/reference.png)、[旧 fader](pixels-before/fader.png)、[数值](pixels-before/RESULT.txt)、[日志](logs/pixels-before.log)。
- 修改后：[对照](pixels-after/reference.png)、[新 fader](pixels-after/fader.png)、[数值](pixels-after/RESULT.txt)、[日志](logs/pixels-after.log)。
- 修改后像素命令退出 0，仍有 2 个实例泄漏和 1 个未释放资源 ERROR，未将其隐藏。
- 墙体运行契约实测 8 个站位 × 3 个朝向，46 个实际淡出状态；离开后 instance transparency 为 0，恢复精确的作者材质。六面墙／门楣的法线、4 mm 分离、opaque/depth/back-cull 契约也已检查。

## 5. 完整回归与独立正反对照

- 修改后 24/24 教室回归通过，整体退出 0；批准的 main 基线也为 24/24、退出 0，保存目录彼此隔离。
- [修改后套件运行器输出](logs/suite-head.log)、[main 套件输出](logs/suite-main.log)、[24 项 ERROR/WARNING 对照](logs/engine-noise-comparison.md)。运行器输出包含每项命令、退出码和日志尾段，并非各项全量日志的拼接；噪声表从每项全量日志计数。
- 保留失败定位证据：[更新旧判定前的交互日志](logs/interaction-before-oracle-update.log)。当时交互测试把所有渲染器都视为“只能靠材质 alpha 淡出”，产生 11 条不符合已实测 Forward+ 行为的断言。生产 InteractionController 已正确区分渲染器，未修改。
- [更新后的交互回归](logs/interaction-head.log) 保留 Compatibility 原断言，新增 Forward+ 的作者材质身份检查，并用“仅实例淡出 → 恢复不透明 → 仅 alpha 淡出”验证正反对照；不是删除失败测试或放宽数值阈值。
- [真实 Forward+ 轮廓回归](logs/outline-forward.log) 通过 91 项像素检查：无遮挡全轮廓 100%、0 游离像素；完全遮挡最大变化 0；半遮挡可见 100%／被挡 0%；运动镜头最差覆盖 100%、最差游离 0。测试还检查切换／释放与作者 overlay 的恢复。该测试与生产轮廓代码未改；仍有 2 个实例泄漏和 1 个资源 ERROR。
- 模型管线在集成批准的 main 后已通过；教师模型的缩减和 sidecar 来自 main，不是本任务新增的范围外修复。
- UID 生成器采用 Godot 4.7.2 的 34 字符编码；18 份 sidecar 已重建。纹理 `--check` 在真实导入前后均通过，像素文件没有因 UID 修复而改变。

## 6. 精确运行命令

`GODOT_BIN` 指向上面的源码构建；显示／驱动环境由仓库外工具提供。基线在批准 main 的 archive 副本执行，同一个夹具只用于测试。

```sh
# 修改前（批准的 main 副本）；旧 fader 像素检查预期退出 1
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 640x480 --script res://tests/classroom_wall_render_test.gd -- --output=build/classroom-current/pixels-before
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1600x900 --script res://tests/capture_classroom_art.gd -- --output=build/classroom-current/before-forward

# 修改后
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 640x480 --script res://tests/classroom_wall_render_test.gd -- --output=build/classroom-current/pixels-after
"$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1600x900 --script res://tests/capture_classroom_art.gd -- --output=build/classroom-current/after-forward
OUTLINE_REQUIRE_RENDERER=forward_plus OUTLINE_EVIDENCE_DIR="$PWD/build/classroom-current/outline-forward" "$GODOT_BIN" --path . --rendering-method forward_plus --rendering-driver vulkan --audio-driver Dummy --resolution 1600x900 --script res://tests/interaction_outline_occlusion_test.gd

# 独立 XDG_DATA_HOME，防止两边保存状态串扰；基线使用 checks 目录
CLASSROOM_LOG_DIR=build/classroom-current/checks-final bash tests/run_classroom_checks.sh
```

## 7. 剩余限制与噪声

- Compatibility 本地初始化失败：[日志](logs/compatibility-initialization-failure.log)。Mobile／Windows 目标 GPU 尚未实际渲染验收；最终 head 的 CI 状态另见 PR，不从软件 Forward+ 推断其他平台通过。
- 自编译引擎的 import 虽退出 0，仍报告关闭 fontconfig 的错误及重建缺失 UID 的警告：[head](logs/import-head.log)、[main](logs/import-main.log)。没有 Parse Error／SCRIPT ERROR，但不能称为干净导入。
- 资源清理、负向测试与导航告警在两边仍存在，数量并不完全相同；没有为合并而过滤错误、降低断言或改全局测试工具。这些噪声尚未根治。
- 本地观图检查不等于所有者视觉验收；主角／Q／N 的正式美术与目标硬件审查仍由所有者确认。

日志只规范化机器路径前缀为 `$REPO`、`$BASELINE`、`$TOOLS` 并去除行尾空白；不删减日志行、错误或警告。完整构建、缓存、驱动、无效帧及无关自动导入元数据不入 Git，遵循 ADR 0007。
