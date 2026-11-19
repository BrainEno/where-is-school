# 测试入口与公共断言

先读 [AGENTS.md](../AGENTS.md) 与 [公共模块索引](../docs/MODULE_INDEX.md)。
测试需要项目规定的 **Godot 4.7.2 Stable standard**；Python 维护检查的安装方式见
[tools/README.md](../tools/README.md)。测试代码和依赖不进入游戏导出。

## 可独立运行与辅助库是两种角色

- `tests/*_test.gd`：可用 `godot --path . --script res://tests/<name>_test.gd`
  独立启动的 `SceneTree`，有 `_initialize()` 或 `_init()` 入口，并在 CI 登记。
  涉及像素、窗口、输入或真实渲染的测试仍需它们原有的 Xvfb/渲染器参数，不能一律加
  `--headless` 来替代；从工作流复制完整命令。
- `*_support.gd`：由其他测试 `preload` 并调用的辅助检查，不要拿它们当 `SceneTree` 启动。
  保留辅助库的节点生命周期，由宿主收集失败并给出最终退出码。
- `capture_*.gd`、证据读取器和契约辅助件不是按名字批量运行的普通测试。
  它们需要的真实显示、内容、构建与证据参数仍由各自工作流负责。

已更名的两个辅助件（`.uid` 身份保留）：

| 辅助库 | 唯一运行入口 |
|---|---|
| [player_get_up_support.gd](player_get_up_support.gd) | [runtime_character_animation_test.gd](runtime_character_animation_test.gd) |
| [q_intro_lifecycle_support.gd](q_intro_lifecycle_support.gd) | [opening_resume_test.gd](opening_resume_test.gd) |

`narrative_editor_fail_writer.gd` 本来就没有 `_test.gd` 后缀，是故障注入辅助件，
仍由叙事编辑器测试加载，不为符合错误的旧清单而再次重命名。

## 新断言复用 TestHarness.Checker

[现有 TestHarness](test_harness.gd) 继续统一 watchdog、autoload、状态清理与 `finish`。
新增的 `Harness.Checker` 是它的内部 `RefCounted` 类，不是新的 `class_name`、autoload
或运行时依赖。每个测试或子用例各建一份：

```gdscript
extends SceneTree

const Harness = preload("res://tests/test_harness.gd")
var checks := Harness.Checker.new()

func _initialize() -> void:
    Harness.arm_watchdog(self, 60.0, "entry_scene_test.gd")
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://scenes/main/main.tscn") as PackedScene
    if checks.expect(packed != null, "The main scene could not be loaded."):
        checks.expect(packed.can_instantiate(), "The main scene cannot instantiate.")
    Harness.finish(self, checks.failures, "entry scene resource checked.")
```

- `expect(condition, message) -> bool`：原样返回条件；失败时按顺序记录消息。
- `fail(message)`：无条件记录失败，供提前返回或异步错误路径使用。
- `failures: Array[String]`：每个实例独立，不去重、不共享静态状态。
- 记录本身不输出日志；由 `Harness.finish(tree, checks.failures, success_message)`
  输出 `TEST FAILURE` / `FAIL` 或 `PASS`，并设置退出码。故意构造失败的局部 Checker
  可以检查其结果，而不污染负向夹具的引擎日志；真实测试失败必须交给宿主 `finish`。
- 支持库使用 `checks` 收集断言，宿主用 `append_array(support.checks.failures)` 汇总，
  不允许遗漏子检查的结果。

`smoke_test.gd` 对 Checker 的成功/失败返回、顺序、重复消息、显式失败和实例隔离做
回归检查；它刻意使用独立的原有失败数组判断 Checker 自身，避免坏的断言器替自己报绿。
两个更名的支持库已复用 Checker，其余旧测试不做无关批量重写。

## 新测试必须登记，不能只在注释里出现

1. 新增有真实行为断言和有界退出的 `SceneTree` 脚本，使用 Checker，不再复制 `_expect`。
2. 在合适的工作流 `run` 步骤中写出完整、字面量的
   `godot ... --script res://tests/<name>_test.gd` 命令，继续复用
   [ci_run_check.sh](../tools/ci_run_check.sh) 的严格运行判定。
   也可以由工作流调用仓内根目录相对路径的 `.sh`，再由该脚本写出上述命令。
3. 将新文件加入 Git 索引，再在已安装 Python 工具依赖的环境运行：

```sh
git add tests/<name>_test.gd tests/<name>_test.gd.uid
.venv/bin/python tools/check_test_registration.py --check
.venv/bin/python tools/check_test_registration.py --list
.venv/bin/python tests/test_registration_test.py
```

[Test tooling 工作流](../.github/workflows/test-tooling.yml) 在每个 PR 检查已跟踪入口。
它解析 YAML 的 `jobs.steps.run`，跟随字面量仓内 shell 调用，并识别现有的
`run_check`、`measured`、`timeout`、`xvfb-run`、`env` 前缀；已存在的可选环境变量数组
前缀只作结构识别，不求值。注释、路径过滤器、`echo`、heredoc 数据、明确 `if: false`
和 `--check-only` 都不能充当注册。

这不是 shell 执行器或 CI 覆盖率证明：动态脚本名、`bash -c`、复合 action 和任意条件
表达式不会展开，条件分支是否实际运行、测试是否超时/报错仍由运行时 CI 证明。
需要这些间接形式时，也保留一条可静态发现的真实字面量运行命令。

[legacy_expect.txt](legacy_expect.txt) 只允许迁移边界已有的 `_expect` 定义。
不要追加条目；按需迁移旧测试后删除对应行，检查会拒绝失效条目和新增的自定义断言器。

## 加速时钟与固定帧等待（#207）

`python3 tools/check_flaky_waits.py --list` 列出当前识别的位置。守卫按文件限制存量数量，
不是整文件放行：只消除部分等待也要下调该文件的计数，全部消除则删除条目。
测试仍应使用 `TestHarness.wait_until` 等待可观察的完成状态，而不是按机器能交付的帧数猜测。

静态守卫只跟踪文本顺序中直接赋给 `Engine.time_scale` 的数字与约定的固定帧 `await`，
包括多行参数和限定的帧信号；不会模拟调用顺序、计算常量或读懂断言。相同数量的替换、
输入传播帧是否必要，仍需代码审查和运行时验证。不要把守卫通过当成没有不稳定测试。
