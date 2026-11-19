# Python 维护工具环境

这些脚本用于导入前检查、资源派生与 CI，**不是第二套游戏运行时**。
游戏仍只依赖规定的 Godot standard / GDScript；无遥测、后端或运行时联网依赖。
仓库根目录是下列命令的工作目录。GDScript 测试入口和公共断言见
[tests/README.md](../tests/README.md)。

## 移动构建与调试

移动脚本不需要本页的资产工具依赖。[移动构建、安装与验收](../docs/MOBILE_BUILDS.md)
说明何时点击 Actions 构建、如何配置签名，以及从 **Mac** 的
[`macos/ios/Debug.command`](macos/ios/Debug.command) 或 **Windows** 的
[`windows/android/Setup.cmd`](windows/android/Setup.cmd) / [`Test.cmd`](windows/android/Test.cmd)
开始调试。共用打包工具仍是 [`export_mobile.py`](export_mobile.py)。

## 从干净环境安装

参考环境为 Linux、CPython 3.11 / 3.12。不要依赖系统恰好已经安装 NumPy/Pillow，
也不要对系统 Python 使用 `sudo pip` 或 `--system-site-packages`。
`meshoptimizer` 的既有版本只有源码包，除了 Python 还需要 C++ 编译器与**同一解释器**的
开发头文件（`Python.h`、`pyconfig.h`）。Debian/Ubuntu 系统解释器的准备方式：

```sh
sudo apt-get install python3-venv python3-dev g++
python3 -m venv .venv
.venv/bin/python -m pip install -r tools/requirements.txt
.venv/bin/python -m pip check
.venv/bin/python tests/tool_requirements_test.py
```

如果使用自装 Python，系统 `python3-dev` 不一定匹配它；从该解释器的安装/源码取得
匹配头文件，不要从另一个 Python 版本混用。Windows 的虚拟环境命令为
`py -3.11 -m venv .venv`，后续解释器用 `.venv\Scripts\python.exe`；原生扩展还需
对应 MSVC/CPython 开发环境。本说明不声称已验证 Windows/macOS 的原生资源逐字节重建。

[requirements.txt](requirements.txt) 固定直接依赖及解析器的传递 Python 依赖，
沿用既有版本契约，不在这里升级工具或引擎：

| 依赖 | 使用者 / 原因 |
|---|---|
| `gdtoolkit` | 既有 CI 的 `gdparse`，语法检查全部 GDScript |
| `fonttools` | `subset_font.py`；版本须匹配其 `PINNED_FONTTOOLS`，才能逐字节校验 |
| `PyYAML` | 测试入口检查读取真实 YAML 结构；也是 gdtoolkit 原有的依赖，使用 `safe_load` |
| `numpy`、`Pillow` | 教室贴图绘制、肖像准备；版本沿用教室源文档的重建环境 |
| `meshoptimizer` | `prepare_teacher_n.py` 的既有原生网格简化工具；固定其已用 alpha 版本不是引擎升级 |

编译器、libc、zlib、WebP 和其他原生库没有被这份 Python 清单锁定，不能据此保证
任意操作系统上的产物相同；下述实际字节检查才决定是否可以重建。下载依赖仅发生在
开发/CI 安装阶段。`.venv/`、构建缓存和 Python 包不进 Git，`tools/*` 已被游戏导出预设排除。

## GDScript 增量质量门禁（#229）

```sh
# 新文件先 git add；基线应为 PR 目标分支上要比较的提交。
.venv/bin/python tools/check_gdscript_quality.py --base origin/main
# 只盘点历史问题，不把存量问题当作本次 PR 的新回归。
.venv/bin/python tools/check_gdscript_quality.py --inventory
.venv/bin/python tests/gdscript_quality_test.py
.venv/bin/python tests/gdscript_quality_ci_test.py
```

`gdlintrc` 复用已锁定的 gdtoolkit：默认命名约定、同文件的重复字面路径 `load/preload`、
600 个物理行上限，不要求全库重排格式。检查 `scripts/`、`scenes/`、`addons/` 下受 Git
跟踪的 `.gd`，不把长的测试夹具算入产品脚本预算。`gdparse` 仍独立解析测试和运行时脚本。

- 用目标提交的同文件诊断作存量上限。移动行、减少相同问题不会失败，换一个不规范名字
  或增加相同问题的次数会失败。Git 识别出的重命名继承存量，复制和从范围外移入则不继承。
- 新脚本和原本未超限的脚本不得超过 600 行；已有超限文件增长时打印旧、新行数与告警，
  不因存量阻断并行维护。拆到 600 行以内的文件，后续再跨过上限就会失败；不用维护一张
  按文件名豁免的大表。代码内的 `gdlint` 忽略注释不影响这一比较；规则调整须显式评审。
- Test tooling 在 PR 用目标提交，在 `main` push 用 push 前提交；浅克隆只取缺失基线。
  基线缺失或无效是错误，不会用当前提交和自身比较。手动 dispatch 明确只输出盘点。
  测试用本地浅克隆实际执行工作流步骤，分别证明新增违规失败、合法变更通过、缺基线拒绝。

相邻守卫继续由 Godot CI 调用：`check_ui_literals.py` 按文件和完整 RGBA 约束每一次沿用的
界面字面量；跨行构造、同一行的额外色值和改写旧色都会被识别。白/黑过渡端点与命名色不拦截，
不更改任何现有画面；`check_ui_palette.py`、引擎版本与用例注册检查保持原职责。

## 无写入的工具检查

以下循环包含 `tools/*.py` 中提供独立 `--check` 模式的脚本，不会重写生产资产：

```sh
for tool in \
  build_app_icon build_laboratory build_music_loop build_sample_models \
  check_agent_docs check_test_registration godot_sidecars model_library \
  prepare_portraits prepare_q prepare_teacher_n repo_size screenshot_evidence \
  stamp_release_version subset_font
do
  .venv/bin/python "tools/${tool}.py" --check || exit 1
done
.venv/bin/python tools/check_workflow_action_pins.py
.venv/bin/python art/characters/build_character_looks.py --check
.venv/bin/python art/classroom/paint_classroom_textures.py --check
.venv/bin/python art/laboratory/paint_laboratory_textures.py --check
```

[新 Test tooling 工作流](../.github/workflows/test-tooling.yml) 在 Ubuntu 24.04 的干净
venv 从清单安装后运行这些命令、两组新契约测试和 `gdparse`，不再依赖 runner 预装的
图像/数值库。原有 Godot/发布工作流保留它们只装解析器/字体的窄环境；
`tool_requirements_test.py` 会核对这些内联版本与清单、字体/网格工具的版本守卫及
维护脚本的第三方 import，防止两边静默漂移。

`classroom_render_evidence.py`、`verify_build.py` 等输入驱动的校验器需要真实渲染证据或
实际导出包，并没有可在空目录中声称通过的独立 `--check` 模式。
它们仍由既有 capture/release 工作流带真实输入验证；不要伪造证据来补齐“全通过”。
同样，以上检查通过也不等于执行过 Godot、渲染、听音或双平台导出。

已有 UID、负向存档夹具或引擎错误信息应按其原有报告保留；不降低检查来消除噪声。
若派生产物与来源不同，先核对这份环境、来源指纹和相关 PR，再决定是否应重新生成，
不要在一次依赖维护任务里顺手改美术产物。
