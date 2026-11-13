# 完整教室套件的引擎噪声对照

- 修改后代码：`8f4c314f6ac0f1ad640ce80012b9cc16e91cd816`；24/24，通过，退出 0。
- 批准的 main 基线：`35357848d1361d7b3983ed672742b32e9ab7c776`；24/24，通过，退出 0。
- 两边使用同一个 24 项运行入口和独立 `XDG_DATA_HOME`，避免保存状态互相干扰；main 保留原测试实现。
- 下表从各项完整原始日志计数，不重复统计运行器输出或 import / render 日志。ERROR 不自动等于断言失败；PASS 也不等于无引擎噪声。
- 原始日志中的资源清理、负向测试与导航告警仍未根治；两边数量不完全相同，不能将新增条目一概归为无害噪声。

| 测试 | 修改后 ERROR / WARNING | main ERROR / WARNING | 两边 SCRIPT ERROR / Parse Error |
|---|---:|---:|---:|
| `smoke` | 1 / 1 | 1 / 1 | 0 / 0 |
| `camera_rig` | 1 / 1 | 1 / 1 | 0 / 0 |
| `classroom_visual_slice` | 1 / 1 | 0 / 0 | 0 / 0 |
| `navigation` | 0 / 0 | 1 / 1 | 0 / 0 |
| `navigation_sync_stress` | 1 / 1 | 1 / 1 | 0 / 0 |
| `prop_placement` | 1 / 1 | 1 / 1 | 0 / 0 |
| `imported_placement` | 1 / 1 | 0 / 0 | 0 / 0 |
| `imported_assets` | 1 / 1 | 1 / 1 | 0 / 0 |
| `interaction_occlusion` | 1 / 2 | 1 / 2 | 0 / 0 |
| `interaction_visibility_sweep` | 1 / 2 | 1 / 2 | 0 / 0 |
| `interaction_outline_content` | 1 / 2 | 1 / 2 | 0 / 0 |
| `interaction_hover` | 1 / 2 | 1 / 2 | 0 / 0 |
| `interaction_cue` | 1 / 1 | 1 / 1 | 0 / 0 |
| `automatic_interaction` | 0 / 2 | 1 / 3 | 0 / 0 |
| `pointer_target_switch` | 1 / 2 | 1 / 2 | 0 / 0 |
| `opening_flow` | 1 / 4 | 1 / 4 | 0 / 0 |
| `opening_resume` | 22 / 8 | 21 / 7 | 0 / 0 |
| `free_period` | 1 / 1 | 1 / 1 | 0 / 0 |
| `subjective_isolation` | 1 / 202 | 1 / 202 | 0 / 0 |
| `location_transition` | 13 / 1 | 13 / 1 | 0 / 0 |
| `companion_route` | 1 / 3 | 1 / 3 | 0 / 0 |
| `companion_obstacle` | 1 / 1 | 1 / 1 | 0 / 0 |
| `dialogue_content` | 1 / 1 | 1 / 1 | 0 / 0 |
| `content_integrity` | 1 / 1 | 0 / 0 | 0 / 0 |

套件运行器的逐项命令、退出码、日志尾段与总结果：[修改后](suite-head.log)、[main](suite-main.log)。运行器不是各项全量日志的拼接；上表读取了各项全量日志。
