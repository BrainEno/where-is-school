# 显示与输入提示适配（Agent 04）

## 设计决定

- 项目保留 1600×900 设计窗口、1280×720 最小窗口和可调整大小行为。F11 仍绑定原有全屏动作；`DisplayMode` 使用 Godot 的 `WINDOW_MODE_FULLSCREEN`（桌面无边框全屏），退出时恢复进入全屏前的窗口尺寸和位置，并将窗口矩形限制在当前屏幕可用区域内。
- 3D 仍由实际窗口视口以目标分辨率渲染；显示缩放只对 CanvasItem 生效，不改变相机 FOV、相机距离、角色模型或世界坐标。这样 4K 提高 3D 像素密度，但人物在画面中的投影占比不随分辨率变小。
- UI 使用统一、等比的 CanvasItem 缩放：1280×720、1600×900、1920×1080 的自动缩放为 1.0；2560×1440 为 1.25；3840×2160 为 2.0。4K 下 UI 使用 1920×1080 逻辑画布，字体和按钮以 2 倍物理像素呈现。缩放使用 `CONTENT_SCALE_ASPECT_EXPAND`，不是分别缩放宽高；鼠标和 UI 共享 Godot 的画布变换。手动缩放受 1280×720 最小逻辑画布约束。
- 不调整 CameraRig。现有视角是各室内、走廊和室外场景共用的构图基线；本次没有足够的 4K/多地点实机画面来证明一次全局变焦不会破坏边缘可见性、遮挡淡化或点击射线。现有 CameraRig / 遮挡 / 点击测试继续作为相机行为回归保护。

## 输入设备与提示

`Settings` 是唯一输入设备状态源，设备变化通过 `input_device_changed` 通知界面。最近一次有意义的键盘按键、鼠标移动/点击或手柄按键/超过阈值的摇杆输入切换提示族。低于 0.5 的手柄轴噪声不切换；只改变显示状态，不合成或重放游戏动作。当前使用中的手柄断开后，立即回到始终可用的键盘提示；连接手柄本身不会抢走当前输入设备。

`InputHint` 统一从当前 `InputMap` / Settings 重绑结果取得动作标签。基于本项目映射：交互 E / A，继续对话 Space / A，日志 Tab / Y，取消 Esc / B。鼠标操作世界交互或继续对话时显示本地化“单击 / Click”。菜单确认、菜单取消、暂停、HUD、对话和日志复用统一动作标签；Xbox/PlayStation 专属图标尚无资源，当前显示短文本。

## 自动化验证

- `tests/display_resolution_test.gd`：模拟五个 16:9 尺寸，检查 Auto/手动 UI 比例、逻辑画布、字体线性缩放、CanvasItem-only 模式和非拉伸比例。
- `tests/dialogue_layout_test.gd`、`tests/hud_layout_test.gd`：对话、提示、菜单、设置页与中英文布局覆盖五个尺寸；对话长文仍可滚动。
- `tests/input_device_test.gd`：通过 `Viewport.push_input` 注入键盘、鼠标和手柄输入，检查提示实际切换、动作标签来自当前 InputMap、手柄断开回退，以及设备提示变化不会重复触发动作。断开流程调用与 Godot 连接信号同签名的处理器；真实硬件热插拔还需桌面实测。
- `tests/display_mode_test.gd`：保留现有 F11/窗口尺寸状态机测试。物理显示器的边框、全屏和多屏切换须在桌面环境人工确认。
- `.github/workflows/playthrough-capture.yml` 的桌面捕获作业扩展为 3840×2160 虚拟显示器，并从真实游戏画面为五个尺寸及中英文对话输出 PNG，另含一张手柄提示画面；产物由 PR 工作流上传，不提交大量生成图到 Git。

## 本次运行记录

- 当前 Arena 工作区没有 Godot 可执行文件，所以没有本地 Godot 运行；PR CI 使用仓库工作流安装的 Godot 4.7.2 Stable。
- 本地：`gdparse` 解析 `scripts/`、`tests/` 全部 GDScript 通过；`git diff --check`、locale JSON 和两个修改 workflow 的 YAML 解析通过；`bash tests/run_check_test.sh` 为 10 cases / 0 failures。
- PR head `58c2b8791befb2de8cb7e6209af62842ba7e7cb2` 的 Godot CI 全部通过，Godot 4.7.2 Stable：完整 gameplay job 与独立 `Display scaling and input device tests` 均成功；独立 job 为 9/9（display_mode、display_resolution、input_device、dialogue_layout，以及 1280×720、1600×900、1920×1080、2560×1440、3840×2160 HUD 布局）。Run：<https://github.com/BrainEno/where-is-school/actions/runs/43244762891>。
- 同一 head 的 Playthrough capture 全步骤通过，流程抵达已实现内容结尾；验证 job 检查 77 个 frame、result marker present、no failures。截图证据：<https://github.com/BrainEno/where-is-school/actions/runs/43244763012/artifacts/13956821898>。工作流：<https://github.com/BrainEno/where-is-school/actions/runs/43244763012>。CI 记录的 `to_schoolyard` 提示未出现情况仍存在，但脚本继续完成流程；需人工核对相应提示时序。
- Release build 的双平台导出、验证和打包均通过：<https://github.com/BrainEno/where-is-school/actions/runs/43244762878>。此前同一改动在另一轮 CI 出现模型库契约与 teacher 导入资源体积失败；后续完整 Godot CI 和 Release 检查通过，未修改或绕过 Agent 01/02/03 资源约束。
- 必需 PR checks 全部通过：<https://github.com/BrainEno/where-is-school/pull/131>。GitHub 当前报告 PR 与最新 `main` 存在冲突（`.github/workflows/playthrough-capture.yml`），因此 PR 还不能合并；遵循独立 PR 约束，本次没有把 `main` 合并进工作分支，也没有合并 PR。真实显示器的 F11 / 无边框全屏与多屏位置，以及真实控制器热插拔仍需人工验收；CI 使用 Xvfb 和合成输入，不能替代硬件验证。
