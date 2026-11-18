# Agent collaboration and reporting protocol — mandatory

Read this entire protocol before editing. It is part of [AGENTS.md](../AGENTS.md), not optional reference material. Public module discovery starts at [MODULE_INDEX.md](MODULE_INDEX.md).

This protocol applies to **every coding agent, regardless of provider, model, Arena session, or task domain**. It supplements the technical, narrative, asset, testing, and Git rules in AGENTS.md; it does not replace them.

## 1. Language policy

- **All human-facing work reports must be in Simplified Chinese.** This includes progress updates, blocker reports, GitHub issue comments, PR descriptions, review replies, final handoff reports, and explanations to the repository owner.
- **Every pull request title and body must be written in Simplified Chinese.** Keep code identifiers, file paths, API names, command lines, test output, commit hashes, and official product names unchanged where precision requires it; explain them in Chinese.
- The same Chinese reporting rule applies to draft PRs. A draft is not an exception.
- **Commit messages must be in English** and must follow the exact format in §3. Do not put Chinese prose in commit subjects or bodies.
- Code, identifiers, API names, source-code comments, and executable output should follow the conventions of the file and subsystem being changed. Do not translate identifiers or alter existing language conventions merely to satisfy the PR language rule.
- If an English canonical design/technical document is changed, update its paired Chinese reading copy when one exists, following the source-of-truth rules in AGENTS.md. This documentation rule does not change the language required for PR reporting.
- Do not claim a model identity from Git author, co-author, branch name, or generic agent metadata. Report the exact model name/version shown by the agent platform. If the platform does not expose it, write 平台未显示，无法核实; never guess.

## 2. Branch and pull request naming

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

## 3. Commit message format — English only

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

## 4. Mandatory PR description structure — Chinese

Every PR must use the repository template at [.github/pull_request_template.md](../.github/pull_request_template.md). Do not remove sections. If a section does not apply, write 不适用 and briefly explain why. Do not leave required sections blank.

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

## 5. Standard work-report format

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

## 6. Evidence and honesty rules

- Always distinguish **implemented**, **locally tested**, **CI tested on the exact PR head**, and **manually verified by the owner**. These are different evidence levels.
- A passing check on an earlier commit does not prove the final PR head passes. Re-run checks after the last code change.
- Report failures, warnings, leaked objects/resources, skipped tests, missing hardware access, and environment limitations. Do not hide them because the workflow's final conclusion is green.
- Never weaken, delete, skip, or rewrite an existing test to conceal a regression. A test change must preserve or strengthen the behavior contract and explain why.
- Do not invent screenshots, CI links, test results, hardware measurements, model names, asset provenance, licenses, or owner approvals.
- Do not include private manuscripts, credentials, personal absolute paths, or unrelated personal information in branches, commits, issues, PRs, logs, or evidence.
- Before opening a PR, compare the branch with the exact requested base, inspect the full diff, confirm no unrelated files changed, and rebase/refresh only when doing so is safe and authorized.

### 6.1 Flaky tests

- **A test that fails intermittently is a bug in the test until proven otherwise.** Report it; do not re-run CI until it goes green and call that a pass.
- **Never loosen an assertion to make a test pass.** Widening a tolerance, deleting a case, or adding a retry changes the contract the test was written to hold. If the behavior is genuinely allowed to vary, say which variation is legitimate and why, in the PR.
- **A test seen failing three times on the same commit gets an issue**, with the assertion text, the commit, and the CI run. Do not leave it as folklore.
- **Time-sensitive assertions must not wait a fixed number of frames.** `Engine.time_scale` speeds up the clock, not the machine: `await _frames(2)` under a scaled clock waits for whatever the runner delivers, so the assertion races the frame rate. Use `TestHarness.wait_until(condition, limit_seconds)`, which counts real seconds and polls the condition. `tools/check_flaky_waits.py` refuses a new fixed wait in an accelerated test; its baseline lists the files still to convert and only ever shrinks.
- A fixed wait is still correct for letting an input event propagate, or when the code under test is known to have finished. Prefer a condition anyway: it costs nothing when the condition is already true.

## 7. Ownership and merge boundary

- Agents implement and provide evidence; the repository owner reviews and decides whether to merge.
- Agents must not merge their own PR, merge another agent's PR, push directly to main, force-push, rewrite shared history, or change repository protections.
- If another PR changes the same file or a required base SHA has moved, stop and report the conflict in Chinese. Do not silently broaden the allowlist or overwrite another agent's work.
- If a requirement conflicts with this file, the task-specific owner instruction may override it only when the override is explicit. Report the conflict and the chosen scope in the PR.

## 8. Agent entry point

`AGENTS.md` is the sole repository instruction entry point. Issue #221 removed the singular `AGENT.md` redirect with owner approval after searching tracked files (including `.github/`, `tools/` and tests) found no in-repository tool dependency on it. External agent/tool configurations cannot be verified from this checkout; point any such configuration at `AGENTS.md`, not at a copied rule set.

Before treating a document under `docs/` as current, read [docs/README.md](README.md): it is the centralized status, ownership and archive index. [MODULE_INDEX.md](MODULE_INDEX.md) remains the public-type index. An implementation note, migration record or archived audit is historical evidence, not a current contract, unless the central index says otherwise.
