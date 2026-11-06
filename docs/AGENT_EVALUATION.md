# Coding-Agent Evaluation Protocol

The purpose is to select a primary implementation model based on delivered engineering quality, not confidence, verbosity, or a plausible-sounding summary.

## Fair comparison setup

1. Give every candidate the same task prompt and the same base commit.
2. Use separate branches and clean working copies.
3. Do not let candidates inspect or reuse one another's solutions before submitting.
4. Keep engine version, project files, acceptance criteria, and available time/tool permissions equivalent.
5. Ask each candidate to create a focused PR, not to push directly to main.
6. Run the same clean-clone validation and manual acceptance checklist for every PR.
7. Review the resulting code and the actual diff; do not rely on agent self-report.

Record the agent label, model/version if known, base SHA, branch, PR, changed files, tests, and review outcome. If a model identity is hidden or uncertain, record it as unknown rather than presenting a guess as fact.

## Scoring rubric

| Category | Weight | Evidence |
|---|---:|---|
| Functional correctness | 25 | Reproducible acceptance criteria, edge cases, no broken flows |
| Architecture and integration | 20 | Clear ownership, minimal coupling, fits existing project boundaries |
| Code quality and maintainability | 15 | Typed APIs, naming, readable scenes/scripts, error handling |
| Tests and validation evidence | 15 | Real tests, clean import, honest engine/runtime evidence |
| Narrative/gameplay implementation | 15 | Supports the intended exploration/dialogue experience rather than generic systems |
| Scope discipline and documentation | 10 | No unrelated rewrite, useful docs, clear limitations |

Score each category from 0 to 5 and multiply by its weight. Keep separate notes for blocking defects and non-blocking improvements; a high aggregate score cannot excuse a serious regression or dishonest test claim.

## Review checklist

- Does it open in the pinned Godot version?
- Are scenes and resources properly referenced and reusable?
- Are gameplay state changes explicit and testable?
- Is narrative data separated from control scripts?
- Do interactions and dialogue have clear ownership?
- Are failure paths and missing data handled?
- Are tests meaningful, or do they merely assert constants/always pass?
- Are controls, camera, collision, typography, and long text manually usable?
- Are generated/third-party assets tracked with rights information?
- Does the PR stay within its assigned scope?

## Primary-model decision

Select the model with the strongest combination of correctness, integration quality, maintainability, and verified execution. Do not automatically select the one with the most lines of code or the most ambitious feature list.

If two candidates are close, assign a second task targeting the weakest category of each. Keep the selected primary model provisional until it succeeds on at least two different tasks (for example, one gameplay system and one dialogue/data-integrity task).
