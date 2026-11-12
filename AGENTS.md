# Agent Instructions — where-is-school

You are contributing to a narrative game in pre-production. Read this file and the linked design documents before editing code or game-facing creative content.

## Product intent

where-is-school is a painterly 2.5D surreal narrative exploration RPG. The protagonist wakes in a classroom occupying the role of a student again, without a reliable explanation. The opening follows a school lesson, a brief encounter with classmates and staff, and an exit into nearby everyday spaces. The wider game explores unstable school geography and contradictory recollections.

The primary experience is exploration, environmental observation, and literary dialogue. Combat is not part of the current design. Do not add enemies, weapons, loot economies, crafting, survival meters, procedural open-world systems, or conventional horror chase loops without explicit approval.

## Source of truth

- Product and scope: docs/PRODUCT_BRIEF.md
- Runtime boundaries: docs/ARCHITECTURE.md
- Technical decisions: docs/TECHNICAL_ROADMAP.md
- Game-facing narrative constraints: docs/NARRATIVE_BIBLE.md
- Visual direction (English source of truth): docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md
- Chinese reading copies: docs/ART_BIBLE.zh-CN.md and docs/CONCEPT_DIRECTION.zh-CN.md. Keep each English/Chinese pair synchronized; agents should use the English version as the canonical production instruction.
- First vertical-slice acceptance: docs/PROTOTYPE_BRIEF.md
- Agent comparison protocol: docs/AGENT_EVALUATION.md

If documents conflict, report the conflict instead of silently inventing a new direction.

## Creative-material confidentiality — mandatory

The author's literary manuscripts are private source material and may be intended for separate publication. Repository access is not permission to reproduce them.

- Never copy manuscript paragraphs, extended descriptions, internal monologues, unpublished endings, or distinctive literary phrasing into source files, issues, PRs, commits, screenshots, test fixtures, agent prompts, or generated documentation.
- Do not create a disguised transcript by lightly paraphrasing a manuscript paragraph-by-paragraph. Extract only the minimum game-production facts needed to build a scene.
- Public documentation may contain concise scene beats, location/prop lists, interaction requirements, character-function notes, state transitions, and short dialogue samples explicitly approved for game use.
- If an exact line from a manuscript would help, ask the owner to approve that specific line for game use. Otherwise write new implementation dialogue independently.
- Do not upload manuscripts to public repositories or send complete manuscripts to external coding agents. Give agents only the small, relevant game brief they need.
- Keep the distinction between private literary source material and approved game content explicit in every handoff.
- When uncertain whether material is too close to the manuscript, omit it and ask.

## Narrative fidelity and uncertainty

- Preserve distinctions between a character's claim, the protagonist's recollection, subjective imagination, and events observed in the playable scene.
- The opening biology teacher B is absent from the first lesson; substitute N takes the class. Do not bring B onstage early to deliver exposition.
- Q is an ordinary, talkative, overfamiliar classmate, not a supernatural guide, deliberate liar, or quest terminal. Important context can emerge incidentally from ordinary conversation.
- B is a woman associated with the teacher role and institutional authority. Her character should retain ordinary human pettiness; do not flatten her into a monster, mastermind, harmless comic figure, or simple fraud.
- N is an inexperienced substitute, not automatically the truthful or morally superior counterpart to B.
- A damaged wooden set square is a recurring prop associated with B. Its precise visual state can be defined by the scene asset brief; do not reproduce manuscript description.
- The green-animal encounter is a scene about observation and uncertain classification. Its definitive species and outcome remain undecided.
- A/B/C memory directions remain undecided in their specific content. D means deferring active recollection and following immediate events; it is not a permanently exclusive fourth campaign.
- Do not diagnose the protagonist or explain the school's anomalies as a confirmed psychological condition.
- Keep the elliptical building out of the opening. It is a later spatial structure connecting versions of the school, not a generic portal to unrelated locations.
- Distinguish confirmed owner decisions from provisional implementation proposals. Mark unresolved details as unresolved.

## Technical constraints

- Engine: Godot 4.7.2 Stable, standard build. Do not use beta/nightly APIs or silently upgrade the project version.
- Language: GDScript. Do not introduce C#, .NET, a second runtime, or a web backend without approval.
- Presentation: 3D environments with a controlled 2.5D camera.
- Use Godot scenes/resources for composition. Do not build the game as a pure-code renderer.
- Keep dialogue, character data, item descriptions, and location content out of large gameplay scripts.
- Separate world presentation, player control, interaction, dialogue, narrative state, and persistence.
- Keep autoload singletons few and cohesive.
- Evaluate third-party addons before adoption. Record exact version/tag, license, maintenance state, and reason for adoption.
- No mandatory network services, analytics, telemetry, paid APIs, or proprietary runtime dependencies.
- `addons/` holds the narrative editor (`addons/narrative_editor/`), a first-party EditorPlugin.
  It is editor-only: no autoload, no `class_name`, no preload from `scripts/`, `scenes/` or
  `tests/`, excluded from the export preset, and `tools/verify_build.py` fails if anything under
  `res://addons/` is packed. Keep it that way, keep its write surface to text fields (ids,
  branches, conditions, effects, checks and numbers are read-only by construction), and keep the
  file I/O in `core/` so it can be tested headlessly against `user://` fixtures. See
  `docs/ARCHITECTURE.md` §5i and `addons/narrative_editor/README.md`.
- Windows PC is the first target. Keep input, paths, and content portable for later Linux/Steam Deck evaluation.

## Art and asset constraints

- Visual target: expressionist people and independent expressionist dialogue portraits; graphic, hand-made environments; and absurd theatrical negative space, especially outdoors. See docs/ART_BIBLE.md and docs/CONCEPT_DIRECTION.md for the full direction.
- Outdoor spaces may feel like spare stage sets: broad areas of sky and ground, an exposed horizon, isolated objects, simplified distant structures, and a deliberate atmosphere of waiting or disorientation. Do not fill empty space merely to make a scene look complete.
- Environment art may use bold color planes, hand-drawn outlines, rough brush marks, selective graffiti-like gestures, and simplified geometry. Graphic treatment must not obscure walkable space or important interactables.
- In-game 3D characters prioritize silhouette, proportion, posture, clothing identity, and gameplay-distance readability. Dialogue portraits are separate 2D artworks, not renders or screenshots of the 3D models.
- Dialogue UI follows an integrated composition: portrait, text, speaker identity, and choices belong to one visual arrangement. Long Chinese text must remain comfortable to read.
- The currently implemented dialogue surface is a text-led lower-left reading band; treat it as the implementation baseline and evolve it toward the integrated portrait composition when approved portrait art exists. Preserve its tested readability and interaction behavior.
- Do not treat dampness, dirt, rust, or heavy weathering as mandatory atmosphere. Surface treatment is selected according to each scene's composition and narrative purpose.
- Interaction affordances — the cue where a click lands, the cue on the object the player can use, and a refusal — are drawn in code by `scripts/interaction/{world_cue,hover_cue,destination_cue,outline_overlay}.gd` and share one palette: bone for a destination, amber for a target, a duller rose for a refusal. The object the player can use is shown by a thin warm outline traced around its own silhouette (`OutlineOverlay`), never by a ring or disc on the floor beside it; every interactable names the meshes to trace in `outline_paths`, and the pointer finds it where those meshes are drawn. Ground marks are small (a 0.3 m ring and a dot), unshaded, alpha-only and still once they land; do not add gloss, bloom, gradients or ornament. The interaction controller is the only owner of the "highlighted object" state — do not light an object from the pointer code. See `docs/ARCHITECTURE.md` §5f.
- Keep the English art documents canonical for agent execution and update their matching .zh-CN.md reading copies whenever they change.
- Do not add generated or downloaded assets without recording provenance and commercial-use rights in docs/ASSET_PROVENANCE.md.
- Temporary graybox assets are encouraged and must be treated as placeholders.

## Code quality

- Prefer small, cohesive scripts and scenes with explicit responsibilities.
- Use typed GDScript for public methods, exported properties, and non-trivial state.
- Give nodes, signals, resources, input actions, and story flags stable descriptive names.
- Handle missing or invalid narrative data with actionable errors.
- Do not swallow errors, create fake success paths, or use placeholder tests that always pass.
- Do not add dependencies for trivial functionality.
- Do not reformat or rewrite unrelated files.
- Never commit editor caches, local machine settings, exports, credentials, or personal absolute paths.

## Testing and evidence

For every code task:
1. State the exact Godot version used.
2. Run the project in headless/editor mode where applicable and report the command.
3. Run relevant automated checks; if none exist, explain what was manually verified.
4. Check output for parse errors, missing resources, and runtime errors.
5. Include a concise manual test checklist for relevant gameplay paths.
6. Distinguish verified behavior from assumptions and untested behavior.

Never claim a test passed unless it was actually run.

The narrative editor's data layer is tested headlessly (`tests/narrative_editor_test.gd`,
`tests/ability_validation_test.gd`) against a `user://` copy of the shipped content. The
dock itself needs a window: its frames come from `tests/capture_editor_dock.gd` under Xvfb,
and anything the plugin adds to the editor shell needs a manual checklist in the pull
request. Do not add a test that saves into `res://data/`.

## Git and collaboration

- Work on a dedicated feature branch. Do not push directly to main.
- Keep pull requests focused.
- Before editing, inspect branch, working tree, project structure, and relevant code.
- Do not overwrite another agent's work.
- Do not force-push, rewrite history, merge your own PR, or change repository protections.
- Do not commit a file over 12 MiB, and do not add an exception to the check that says
  so (`python3 tools/repo_size.py --check`). Sources belong in `art/` or outside the
  repository; runtime weight is judged as shipped by `tools/verify_build.py`. The rule
  and its reasons are `docs/adr/0007-large-binaries-and-repository-size.md`.
- PR descriptions must include purpose, implementation summary, files changed, exact validation commands/results, and known limitations.
- If blocked, report the blocker and the smallest decision needed.

## Prototype priorities

1. Launchable Godot project, input, player movement, and camera.
2. One compact classroom with collision and readable navigation.
3. Interactable objects and one NPC.
4. Dialogue presentation with name, portrait, body, choices, and story flags.
5. One transition from the classroom toward school grounds or another authored space.
6. Basic save/load and usability settings after the core loop is stable.

Do not build all chapters, complex skill trees, voice acting, cinematic facial animation, or final production art during the first prototype.

## Definition of done

A task is done only when acceptance criteria are met, the changed path works in the target engine, relevant checks are honestly reported, no known regression is concealed, and the PR contains only approved game-production material.
---

## Agent collaboration and reporting protocol — mandatory

This protocol applies to **every coding agent, regardless of provider, model, Arena session, or task domain**. It supplements the technical, narrative, asset, testing, and Git rules above; it does not replace them.

### 1. Language policy

- **All human-facing work reports must be in Simplified Chinese.** This includes progress updates, blocker reports, GitHub issue comments, PR descriptions, review replies, final handoff reports, and explanations to the repository owner.
- **Every pull request title and body must be written in Simplified Chinese.** Keep code identifiers, file paths, API names, command lines, test output, commit hashes, and official product names unchanged where precision requires it; explain them in Chinese.
- The same Chinese reporting rule applies to draft PRs. A draft is not an exception.
- **Commit messages must be in English** and must follow the exact format in §3. Do not put Chinese prose in commit subjects or bodies.
- Code, identifiers, API names, source-code comments, and executable output should follow the conventions of the file and subsystem being changed. Do not translate identifiers or alter existing language conventions merely to satisfy the PR language rule.
- If an English canonical design/technical document is changed, update its paired Chinese reading copy when one exists, following the source-of-truth rules above. This documentation rule does not change the language required for PR reporting.
- Do not claim a model identity from Git author, co-author, branch name, or generic agent metadata. Report the exact model name/version shown by the agent platform. If the platform does not expose it, write 平台未显示，无法核实; never guess.

### 2. Branch and pull request naming

- Use one dedicated branch per task and per PR. Never push task work directly to main.
- Branch names use lowercase English kebab-case, preferably:
  - agent/<issue-or-pr-number>-<short-task-name> when there is a related issue or PR;
  - agent/<short-task-name> otherwise.
- PR titles use one of these Chinese category prefixes, followed by a specific summary:
  - [功能]：
  - [修复]：
  - [重构]：
  - [测试]：
  - [构建]：
  - [文档]：
  - [资源]：
- Keep one PR focused on one independently reviewable task. Do not bundle unrelated changes just because the agent is limited to one branch.
- Target main unless the task owner explicitly instructs otherwise. Do not stack on another agent's unmerged branch unless explicitly authorized.

### 3. Commit message format — English only

Every commit must follow:

~~~text
<type>(<scope>): <imperative summary>
~~~

Rules:

- Use one of these lowercase types: feat, fix, refactor, test, build, ci, docs, perf, chore.
- scope is required, lowercase kebab-case, and names the affected subsystem (for example: interaction, narrative-editor, settings, model-library, release, agent-protocol).
- The summary is English, imperative, specific, and has no trailing period. Keep the subject at or below 72 characters where practical.
- Use a body only when context is needed; the body must also be in English and explain the reason or important implementation constraint.
- Use BREAKING CHANGE: <description> in the footer only when the change truly breaks a public/runtime contract.
- Do not use vague subjects such as update files, fix stuff, changes, or agent work.
- Do not add Co-authored-by or model attribution unless the identity and attribution are explicitly verified and authorized.

Examples:

~~~text
feat(interaction): add depth-aware outline occlusion
fix(narrative-editor): prevent external edit overwrites
test(settings): cover persistence and input rebinding
build(model-library): validate runtime character manifests
docs(agent-protocol): standardize Chinese PR reporting
~~~

### 4. Mandatory PR description structure — Chinese

Every PR must use the repository template at .github/pull_request_template.md. Do not remove sections. If a section does not apply, write 不适用 and briefly explain why. Do not leave required sections blank.

The PR body must contain, in this order:

1. **任务信息** — task goal, related issue/PR, exact base SHA, final head SHA, engine/runtime version, exact platform-displayed agent model name/version (or the explicit unavailable statement).
2. **变更摘要** — what changed and why; separate implementation facts from intended outcomes.
3. **文件范围** — every changed path grouped by subsystem, and confirmation that the task's allowlist was respected. Explain every necessary exception.
4. **验证结果** — exact commands, actual results, Godot/runtime version, CI workflow/run links, and evidence tied to the final PR head. Mark unrun checks as 未运行; never infer a pass from a previous commit or another branch.
5. **人工验收清单** — concise reproducible owner-facing steps for behaviors automated tests cannot prove.
6. **回归与兼容性** — existing behavior/contracts that were checked, relevant prior tests, and any suspected or confirmed regressions.
7. **已知限制与未完成事项** — known limitations, unverified behavior, dependencies, and explicit owner decisions still required. Write 无 only after checking.
8. **合并建议** — 建议合并 or 暂不建议合并, with evidence-based reasons. This is a recommendation only; agents must not merge their own PRs.

PR descriptions, progress comments, and review replies must be written in Chinese. Preserve exact test output and commands verbatim when needed as evidence.

### 5. Standard work-report format

When reporting progress or a blocker in an issue/PR comment, use this compact format:

~~~markdown
### 工作进展
- **当前状态：** 未开始 / 进行中 / 已完成 / 已阻塞
- **本次完成：** ...
- **验证情况：** 已运行 ...；结果 ...（附证据）
- **尚未完成/风险：** ... / 无
- **下一步：** ...
- **需要所有者决定：** ... / 无
~~~

The final handoff must link the PR and report its title, base/head SHA, changed-file count, test/CI evidence, known limitations, and merge recommendation in Chinese.

### 6. Evidence and honesty rules

- Always distinguish **implemented**, **locally tested**, **CI tested on the exact PR head**, and **manually verified by the owner**. These are different evidence levels.
- A passing check on an earlier commit does not prove the final PR head passes. Re-run checks after the last code change.
- Report failures, warnings, leaked objects/resources, skipped tests, missing hardware access, and environment limitations. Do not hide them because the workflow's final conclusion is green.
- Never weaken, delete, skip, or rewrite an existing test to conceal a regression. A test change must preserve or strengthen the behavior contract and explain why.
- Do not invent screenshots, CI links, test results, hardware measurements, model names, asset provenance, licenses, or owner approvals.
- Do not include private manuscripts, credentials, personal absolute paths, or unrelated personal information in branches, commits, issues, PRs, logs, or evidence.
- Before opening a PR, compare the branch with the exact requested base, inspect the full diff, confirm no unrelated files changed, and rebase/refresh only when doing so is safe and authorized.

### 7. Ownership and merge boundary

- Agents implement and provide evidence; the repository owner reviews and decides whether to merge.
- Agents must not merge their own PR, merge another agent's PR, push directly to main, force-push, rewrite shared history, or change repository protections.
- If another PR changes the same file or a required base SHA has moved, stop and report the conflict in Chinese. Do not silently broaden the allowlist or overwrite another agent's work.
- If a requirement conflicts with this file, the task-specific owner instruction may override it only when the override is explicit. Report the conflict and the chosen scope in the PR.
