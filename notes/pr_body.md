## 1. 任务信息

- **任务目标：** 第 6 轮：把序章“想象中的生物老师 B”（`expected_b`）做成序章最重要的场面。按所有者在本轮 ask_user 中的决定，**本轮只做模型与美术**：把已有的 teacher_b 模型放进想象场景，用 PR #196 / #200 的现代、后现代实验大胆变形，营造幻想/梦境感；画风明显区别于现在的教室，但不像换了个地方；加一层蒙克式波浪滤镜；截图上传 Google Drive。审问选项、装疯嵌套与“停止想象（损失线索）”出口留待所有者写好 B 的提问选项后再做。
- **关联 Issue / PR：** #196、#200（风格来源），#314（上一轮）
- **目标分支：** main
- **开发基线 SHA：** 26e16504c85463b4411ffdc53ad1686ccb7f2a18
- **最终提交 SHA：** 见 PR head（第 6 轮最终 403a5bd；第 7 轮 3a42306 起）
- **引擎 / 运行环境版本：** Godot 4.7.2（`.godot-version`）
- **Agent 平台显示的模型名称与版本：** 平台未显示，无法核实

## 0. 第 7 轮（本次追加，基线已 rebase 到 main 8eba589）

所有者第 7 轮要求：美术强度可以；B 的审问先搭粗选项与节点（每个选项 2–4 轮，占位文本）；后门逃课 Q 不跟随（检定只属于主角）；U 型锁门叫「上锁的门」；序章从教室摔下受伤后加一个不晕、后现代风格的恍惚滤镜。ask_user 中的决定：想象入口放在 Q 描述 B 之后；「异想天开」现在就加（占位数值）；门只改检视标题；滤镜落地最强、约 10 分钟游戏时间淡出。

- **想象入口：** `q_wake` 的 `q_b_looks` 之后选「待做·去想象B」/「待做·不去想」。选了（`imagine_b_chosen`）就在 Q 的对话结束时、同一个 beat 里立刻进入 `expected_b`；不选则这一步立即记为跳过。作者的分支里只有“继续找书”的走向（`search`，或 `ask` 后 `keep_searching`）会让 Q 描述 B；沉默、抓起书、借书、安静的走向不出现这个选择，想象场景也就跳过（`dialogue_content` 测试按此逐一核对）。序章步骤改为 wake → q_wake → expectation → bag → bell → substitute（`prologue_steps.gd`）。旧存档中“书包已翻、想象未播”的情形不会补播（翻书包已关闭这一步）。
- **审问骨架（53 个节点，中英同构）：** B 的四句作者原句（`b_e_1`–`b_e_4`）各是一个分支点，三个方向：方向正常应对 / 方向荒诞 / 方向跳出幻想。每个方向 2–4 轮“主角–B”占位对话，轮间 B 的一句可选“继续”或“跳出”，其中两处在正常与荒诞之间交叉。各方向汇回下一句作者原句，最后到作者原有的回忆 `rec_1` 和 `b_e_5`。作者的 `expected_b` 原句一字未改，所有新文本都是「待做·…」占位。
- **「异想天开」（`whimsy`，Flight of Fancy）：** 新内心声音，数值 3（占位），还没有被动规则（`max_passive` 1：能力注册表要求每个声音都能被动开口）。荒诞方向在「课本呢」之后掷可见检定（难度 10）：成功走高支（主角主导幻想，3 轮，记录占位线索 `imagined_b_clue_whimsy`），失败走低支（B 的权威占上风，1 轮后回到正常方向）。规则改动：这是唯一允许在主观会话里掷的检定（`DialogueGraph.IMAGINATION_ABILITIES`），只记录它自己的掷骰结果；其他能力的检定仍被校验与运行时双重拒绝。
- **跳出幻想：** 任一分支点或轮间选“跳出”→ 两句占位 → 结束。在 `rec_1` 之前离开会记 `expectation_left_early`，之后 `q_after_dismissal` 里依赖“记得三角尺声音”的台词保持关闭。
- **后门逃课：** `location_flow.gd` 在 `skipped_class` 时不让 Q 加入；`prologue_dialogue_paths_test` 断言 Q 未跟随。
- **「上锁的门」：** `alley_door` 检视标题改为「上锁的门」/ "Locked door"，正文与日志记录仍按作者原句写「铁门」；GLOSSARY 同步。
- **摔伤恍惚滤镜（`ConcussionView`）：** 受伤落到集装箱顶的那一刻开始，`main.tscn` 中的世界滤镜（layer -2，在描边与 UI 之下、操场印刷错版之下）把画面变成一张静止的后现代拼贴：四道带毛边的裁切把画面分成几张“纸”，每张错开几像素并用不同印法（原样 / 粉青双色 / 网点报纸 / 双版 riso）；一侧贴着一张倾斜白边的“引用”——画面中心的放大网点版；边缘有 Memphis 小符号（波浪线、点阵、圆环）。**着色器不使用 TIME，没有任何晃动、脉动或漂移**；画面中心不画裁切线、几乎不错位，主角始终完整清晰。强度 `(剩余/600)^0.6`，十分钟游戏时间内依次退场（引用 → 符号 → 印法 → 最后一点错位）。暂停不计时；剩余秒数存在 `concussion_seconds_left`，读档继续；稳住落地（检定成功）不会触发。每个房间在换场黑屏后换一张拼贴。说明见 `docs/CONCUSSION_VIEW.md`。
- **测试：** 新增 `tests/concussion_view_test.gd`（注册 `run_check concussion_view 200`）与 `concussion-view-capture.yml`（三渲染器，操场与小巷，清晰 / 600 / 300 / 60 秒）；`classroom_anomaly_test` 断言受伤落地开始滤镜、稳住落地不开始；`dialogue_content` 把 `q_b_looks` 加入固定分支点并走两种回答；`b_reveal_timing`、`opening_flow`、`opening_resume`、`prologue_dialogue_paths`、`story_pause_timing`、`subjective_isolation` 等按新顺序与新规则更新（没有删减断言）。
- **字体：** 新增汉字（幻、异、荒、诞、疯、撰、威、主）后重新子集化 `assets/fonts/`。

**待作者：** 全部「待做」占位文案；两条线索的内容与位置；「异想天开」的数值与说明；滤镜时长与曲线（600 s / 0.6）是提议值。

## 2. 变更摘要

### 实现内容

- **B 的模型进入正式资源：** `teacher_b.glb`（1,545,436 B，49,466 三角形，57 关节）与 look / motion 资源从 `scenes/dev/teacher_b/`（不导出）移到 `assets/models/teacher_b/`；审阅场景、构建脚本、模型库清单（`REQUIRED_RUNTIME_MODELS` 第 5 项）同步更新。
- **包体上限：** 按所有者选择 `raise24`，`tools/verify_build.py` 硬上限 16 → 24 MiB，8 MiB 警告线不变；B 不减面。
- **想象场景 `ImaginedLesson`**（`scenes/locations/classroom/imagined_lesson.{gd,tscn}`，由 `classroom.tscn` 实例化）：
  - 主像 B 站在主角课桌前方，放大到 1.8 倍，讲解/待机动作循环，始终面向主角视线；
  - 两个“回声 B”在讲台和黑板旁，被压成墨色剪影（`echo` = 1），不投影；
  - `dream_figure.gdshaderinc` 的 `dream_shape`：膨胀、拉长、扭转、S 形摇摆、前倾；`dream_figure.gdshader` 做无光照的表现主义重新着色，`dream_ink.gdshader` 是背面描边的墨线外壳；
  - `munch_wave.gdshader`：全屏 canvas_item 滤镜，以 B 的胸口为中心的漩涡（每帧投影），中心有“平静的眼”把 B 完整留在里面；外圈波纹、条纹拖影、《呐喊》色板（约保留 40% 原色）、四角夜色。
- **触发链：** `BPresence._on_subjective_changed` → `ClassroomPresentation.set_b_impression_visible` → `ImaginedLesson.set_active`。只在 `expected_b` 对话显示期间开启（淡入 1.6 s，淡出 0.9 s），不写入存档。`expected_b` 的文本一字未改。
- **测试与 CI：** 新增 `tests/imagined_lesson_test.gd`（注册为 `run_check imagined_lesson 200`）；新增 `imagined-lesson-capture.yml`，在 Compatibility（两组）、Forward+、Mobile 四种渲染器下截图，并以注释发布画面与失败日志。

### 设计原因与行为变化

- **为什么“同一个地方”：** 教室几何完全不动，只在屏幕上重绘（波浪 + 色板 + 墨边），所以桌椅、黑板、窗户仍可辨认；变形全部集中在 B 身上。
- **平静的眼（修复 2、3）：** 第一版漩涡太强（swirl 2.2，环绕头部），B 被环纹盖住、教室认不出来。现在把中心移到胸口，`eye = smoothstep(0.1, 0.5, r)` 让漩涡、波纹、条纹和色板在 B 身上衰减，环纹减弱为 `0.6*exp(-r*4.0)`。
- **滤镜层级（修复 5）：** 波浪是“对世界的滤镜”而不是 UI，所以放在 layer -1（`world_filter` 组），在交互描边（layer 0）和游戏 UI（layer 1）之下，描边和对话都保持清晰。`interaction_outline_content_test` 原规则是“所有 CanvasLayer 都在描边之上”，现在对 `world_filter` 组改为要求“必须在描边之下”，UI 层的规则不变。
- **雕刻测试（修复 1）：** 模型移动后 `git show <BASE>:<新路径>` 找不到文件，`tools/character_sculpt.py` 增加 `HISTORIC_PATHS` / `historic_path()`，测试按历史路径读取基线。
- **教室配色检查（修复 4）：** `classroom_visual_slice_test` 的配色系统检查跳过 `ImaginedLesson/`（同已跳过的 Actors/、Interactables/），想象人物的材质由 `imagined_lesson_test` 自己检查。
- **慢渲染器：** lavapipe 上淡入需要的真实时间远多于游戏时间；测试改为等待最多 40 s 真实时间，看门狗 180 s；着色器参数用 `_param()` 读取，缺失时返回 NAN 而不是崩溃。

### 已检索

- **已读模块索引：** 是
- **检索关键词与实际命令：** `grep -rn "b_impression\|expected_b\|BPresence" scripts scenes tests`；`grep -rn "teacher_b" --include=*.py --include=*.gd --include=*.tscn --include=*.yml .`；`grep -rn "CanvasLayer" tests`；阅读 `docs/VISUAL_EXPERIMENTS.md`、`docs/BIOLOGY_CLASSROOM_EXPERIMENT.md`、`scenes/dev/visual_experiments/`
- **已有模块、调用点与相关测试：** `scripts/world/b_presence.gd`（主观对话开关）、`classroom_presentation.gd`（`set_b_impression_visible`）、`tests/b_reveal_timing_test.gd`、`tests/classroom_visual_slice_test.gd`、`tests/interaction_outline_content_test.gd`、`tools/model_library.py`、`tools/character_sculpt.py`
- **复用决定与理由：** 复用 BPresence 的主观对话信号与 ClassroomPresentation 的 B 印象开关，不新增触发逻辑；复用 teacher_b 的 GLB、look 和 motion 资源；PR #196/#200 的实验在 `scenes/dev/`（不导出），所以把手法重写成 `assets/shaders/imagined/` 下三渲染器通用的着色器。

## 3. 文件范围

| 文件路径 | 变更内容 | 所属任务范围 |
|---|---|---|
| `assets/models/teacher_b/*`（自 `scenes/dev/teacher_b/` 移入） | B 的模型、look、motion 进入导出资源 | 模型进入想象场景 |
| `scenes/dev/teacher_b/teacher_b_review.tscn`、`art/character_models/teacher_b/*` | 指向新路径 | 模型移动的连带修改 |
| `tools/model_library.py`、`art/character_rig_audit/runtime_model_manifest.json`、`tests/model_library_test.py` | B 登记为运行时角色 | 模型进入想象场景 |
| `tools/character_sculpt.py`、`tests/character_sculpt_test.py` | `HISTORIC_PATHS`，按历史路径读基线 | 修复 1 |
| `tools/verify_build.py`、`tools/subset_font.py`、ADR 0007、`docs/IMPLEMENTATION_NOTES_BUILD.md` | 硬上限 24 MiB | 所有者决定 raise24 |
| `assets/shaders/imagined/*.gdshader(inc)` + `.uid` | 人物变形、墨线、蒙克波浪 | 美术层 |
| `scenes/locations/classroom/imagined_lesson.{gd,tscn}` + `.uid` | 想象场景节点与控制 | 美术层 |
| `scenes/locations/classroom/classroom.tscn`、`classroom_presentation.gd` | 实例化并接上 B 印象开关 | 触发链 |
| `tests/imagined_lesson_test.gd` + `.uid`、`.github/workflows/godot-ci.yml` | 新测试与注册 | 验证 |
| `tests/b_reveal_timing_test.gd` | 同时检查 `ImaginedLesson.is_active()` | 验证 |
| `tests/classroom_visual_slice_test.gd` | 配色检查跳过 `ImaginedLesson/` | 修复 4 |
| `tests/interaction_outline_content_test.gd` | `world_filter` 组须在描边之下 | 修复 5 |
| `.github/workflows/imagined-lesson-capture.yml`、`teacher-b-review.yml`、`classmates-review.yml` | 四渲染器截图；路径更新 | 验证 / 连带修改 |
| `docs/IMAGINED_LESSON.md`（新）、`docs/README.md`、`docs/MODULE_INDEX.md`、`MODEL_LIBRARY.md`、`ASSET_PROVENANCE.md`、`ARCHITECTURE.md`、`ASSET_PIPELINE.md`、`TECHNICAL_ROADMAP.md` | 记录设计与索引 | 文档 |

- **白名单检查：** 是（未改动 `data/dialogue/**` 的任何作者文本）
- **超出原定范围的文件：** `tests/classroom_visual_slice_test.gd`、`tests/interaction_outline_content_test.gd`、`tools/character_sculpt.py`：为让新场景通过既有检查而做的最小调整，规则只为新场景放宽或改写，原有对象的检查不变。

## 4. 验证结果

| 验证层级 | 命令 / 工作流 | 实际结果 | 证据 |
|---|---|---|---|
| 静态检查 | `check_gdscript_quality.py --base origin/main`、`check_test_registration.py`、`check_docs_index.py`、`check_commit_messages.py --range origin/main..HEAD`；CI 的 Python tooling | 通过 | 本地输出；PR checks |
| 自动化测试 | godot-ci “Import, smoke test, and gameplay tests”（含 `imagined_lesson`、`b_reveal_timing`、`interaction_outline_content`）；`character_sculpt_test`、`model_library_test` | 通过 | PR checks |
| Godot / 运行时 | “Drive the game under Xvfb”、classroom-art-evidence（classroom motion、render verdict） | 通过 | PR checks |
| Playthrough / 渲染 | `imagined-lesson-capture.yml`：Compatibility a/b、Forward+、Mobile | 通过（4 个渲染器组全部成功） | Drive 截图（见下） |
| 构建 / 导出 | android APK、iOS Simulator / 无签名归档、包体检查 | 通过（Android APK 导出并在模拟器启动；iOS Simulator Debug 与无签名归档；Release build） | PR checks |

- **Godot / 运行时确切版本：** 4.7.2.stable.official.ed1daf0bf
- **CI 是否在最终 PR head SHA 上运行：** 是（403a5bd）
- **CI Run 链接及 Run ID：** 最终 head 403a5bd 上 13 个工作流全部成功（PR checks：31 项通过、0 失败）：Godot CI [44867139837](https://github.com/BrainEno/where-is-school/actions/runs/44867139837)、Imagined lesson capture [44867139821](https://github.com/BrainEno/where-is-school/actions/runs/44867139821)、Classroom visual evidence [44867139796](https://github.com/BrainEno/where-is-school/actions/runs/44867139796)、Playthrough capture [44867139918](https://github.com/BrainEno/where-is-school/actions/runs/44867139918)、Prologue art capture [44867139893](https://github.com/BrainEno/where-is-school/actions/runs/44867139893)、Classroom anomaly capture [44867139949](https://github.com/BrainEno/where-is-school/actions/runs/44867139949)、Teacher B asset review [44867139963](https://github.com/BrainEno/where-is-school/actions/runs/44867139963)、Release build [44867139931](https://github.com/BrainEno/where-is-school/actions/runs/44867139931)、Test tooling [44867139880](https://github.com/BrainEno/where-is-school/actions/runs/44867139880)、Mobile build tooling validation [44867139989](https://github.com/BrainEno/where-is-school/actions/runs/44867139989)、Mobile input regression [44867139941](https://github.com/BrainEno/where-is-school/actions/runs/44867139941)、Agent documentation [44867139892](https://github.com/BrainEno/where-is-school/actions/runs/44867139892)、Classmates asset review [44867139895](https://github.com/BrainEno/where-is-school/actions/runs/44867139895)
- **未运行的检查及原因：** 本地无法下载 Godot（SSL_ERROR_SYSCALL），所有 Godot 检查都在 CI 上运行。
- **警告、错误、资源泄漏或跳过项：** Android 包体检查对 `teacher_b.glb` 导入后 851 KiB 给出模型警告（超过 384 KiB 警告线，低于 1.5 MiB 硬上限；与 teacher-n、new-Q 等现有模型同级）。上一个 head 25e78b1 上 Android 模拟器启动一次 `adb shell failed`；APK 内容与此前通过的提交相同，在最终 head 上已通过。

**截图（Google Drive，第 6 轮截图文件夹）：**

- [01 对照：普通教室](https://drive.google.com/file/d/16x8kASn6jTPEYhUDLf2QHbKibsTbNRwi/view)
- [02 Forward+ 游戏镜头](https://drive.google.com/file/d/1uWBoT0rdJZKmlYA5MvAxKejpziXKi-xg/view)
- [03 Forward+ 近景 B](https://drive.google.com/file/d/1yi3Iel3dLSkGyrH933wj04dwp5TQ8HPD/view)
- [04 Compatibility 游戏镜头](https://drive.google.com/file/d/1sCkc7_DkCvAUaFzQ2UKGYJs_eJaPHgs0/view)
- [05 Mobile 游戏镜头](https://drive.google.com/file/d/12f5RGyi_DIlLkHDybk4hrxR-SXHi7MjQ/view)

## 5. 人工验收清单

- [ ] 新游戏，与 Q 交谈直到他描述 B（`q_b_looks`）之后进入 `expected_b`：画面淡入波浪滤镜，B 放大站在课桌前，讲台和黑板旁有两个墨色“回声 B”。
- [ ] 想象期间教室仍能认出（黑板、窗户、桌椅），B 本人在漩涡中心清晰可读，对话框文字清晰。
- [ ] `expected_b` 最后一句结束后，滤镜与三个 B 在约 1 秒内完全消失，教室恢复原样；读档后不会残留。
- [ ] 分别在 Forward+、Mobile、Compatibility 渲染器下看一遍，波浪与配色一致、无黑屏或闪烁。
- [ ] 主观判断：变形是否“够大胆”、色彩是否过强或过弱（参数集中在 `munch_wave.gdshader` 顶部的 uniform）。

## 6. 回归与兼容性

- **本次重点保护的既有行为 / 契约：** `expected_b` 的作者文本与节点顺序；BPresence 对 npc_id `b` 角色的强制隐藏；教室的配色系统；交互描边在 UI 之下；包体 8 MiB 警告线；雕刻测试的基线比对。
- **已运行的相关旧测试：** `b_reveal_timing`、`classroom_visual_slice`、`interaction_outline_content`、`runtime_character_animation`、`imported_placement`、`character_sculpt_test`、`model_library_test`，以及完整 godot-ci 套件。
- **回归风险：** 低。想象场景平时隐藏且不处理输入（滤镜 `mouse_filter = IGNORE`）；包体增加约 1.5 MiB。
- **与其他开放 PR 或并行任务的文件冲突检查：** #316 同改 `docs/ASSET_PIPELINE.md`、`docs/ASSET_PROVENANCE.md`、`docs/MODULE_INDEX.md`、`docs/README.md`；#318 同改 `docs/README.md`。都是索引表的新增行，合并时可能需要简单的文本冲突处理。

## 7. 已知限制与未完成事项

- **已知限制：** `compatibility-a` 组的 dream 截图因 CI 注释额度只发布了 19/20 段（该帧可选，其余帧完整）。
- **尚未验证的行为：** 真机（Android / iOS）上的帧率与观感，只有 CI 模拟器启动验证。
- **依赖的后续工作：** B 的审问选项、主角的装疯/正常回应与嵌套想象、随时可选的“停止想象”出口（损失部分线索）——等所有者提供 B 的提问选项文本后实现；`ImaginedLesson` 的 `dream`/`reach` 控制已为嵌套加深留好接口。
- **需要所有者明确决定的事项：** 第 7 轮的占位文案与线索；恍惚滤镜的强度与时长。（第 6 轮的问题已在第 7 轮答复并实现：美术强度可以；后门逃课 Q 不跟随；U 型锁门叫「上锁的门」。）

## 8. 合并建议

**建议：** 建议合并

**依据：**

- 最终 head 上全部 CI 通过，四个渲染器的截图都显示 B 清晰可读、教室可辨认。
- 作者文本零改动，想象场景只在 `expected_b` 期间开启。

**Agent 自检声明：**

- [x] 未直接向 main 推送。
- [x] 未自行合并本 PR。
- [x] 未删除、跳过或弱化既有测试来掩盖问题。（两处测试调整只针对新场景：配色检查交给专门测试，描边层级对世界滤镜改为反向约束。）
- [x] 已检查完整 diff，未包含无关文件。
- [x] 已按仓库 AGENTS.md 的中文汇报和英文 Commit Message 协议执行。

