# ADR 0002 — Dialogue Layer and Narrative Knowledge State

- **Status:** Accepted for the first playable milestone
- **Date:** 2026-11-06

## Context

The biology-class prologue needs conversations, inspections, choices with
observable consequences, a backlog, and a hard boundary between what a character
claims, what the protagonist remembers, and what the protagonist imagines.

`docs/ARCHITECTURE.md` §5 asks for a bounded Dialogic 2 spike before adopting a
dialogue addon, and for narrative text to stay out of gameplay scripts.
`docs/TECHNICAL_ROADMAP.md` keeps the addon decision open. Installing an addon
without that spike — and without a review of its current Godot compatibility,
license, and maintenance state — would violate the repository policy, and no
approved third-party content may enter the tree before the provenance review.

The slice also needs a place to store knowledge categories. `GameState` is
deliberately limited to named gameplay flags and must not become a dumping ground.

## Decision

1. Implement a small project-owned dialogue layer:
   - `DialogueGraph` parses and validates JSON content, reporting file and node.
   - `DialogueRuntime` walks the graph and emits presentation events; it knows no
     UI nodes and is unit-testable headlessly.
   - `DialogueController` binds the runtime to `DialoguePanel` and owns inspection
     presentation.
   - `DialogueLibrary` is the single seam a future Dialogic adapter could replace.
2. Keep content in `data/dialogue/*.json` and `data/inspections/*.json`, with
   speaker metadata in `data/characters/*.tres`.
3. Add exactly one autoload, `NarrativeState`, for append-only knowledge entries
   tagged `observed` / `reported` / `recalled` / `imagined`, de-duplicated by id and
   serialisable for a future save system.
4. Enforce the imagination boundary in the runtime: a conversation marked
   `subjective` cannot set flags, cannot change the objective, and cannot record
   `observed` or `reported` knowledge. Attempts are rejected and reported.

## Consequences

- No third-party runtime dependency is introduced; the dialogue technology
  decision stays open and evidence-based.
- Content can be reviewed and diffed as text, and a content test can fail a PR
  that breaks a node link or removes a choice.
- Story facts and knowledge categories are separate concerns: gameplay scripts
  read flags, while presentation and future journal features read entries.
- Two autoloads now exist. Both are small, documented, and independently
  testable, which is the condition `docs/ARCHITECTURE.md` §3 sets for adding one.
- If Dialogic (or another addon) is adopted later, `DialogueController` and the
  content files are the affected surface, not the scenes or the director.

## Revisit when

- The bounded Dialogic 2 spike is run and its results justify a migration.
- Localisation requires tooling this layer cannot provide.
- Mid-conversation saving becomes a requirement (the runtime does not serialise
  its position yet).
