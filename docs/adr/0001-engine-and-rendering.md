# ADR 0001 — Engine, Language, and Renderer

- **Status:** Accepted for prototype foundation
- **Date:** 2026-11-06

## Context

The project needs a lightweight authoring environment for a single-player 2.5D narrative game with 3D spaces, environmental lighting, reusable scenes, and long-form dialogue. The owner prioritizes maintainability, no mandatory service costs, and the ability to delegate isolated implementation tasks to multiple coding agents.

## Decision

- Use Godot 4.7.2 Stable.
- Use the standard non-.NET build and GDScript.
- Use Forward+ as the initial Windows PC renderer.
- Build a 3D environment with a controlled 2.5D camera.
- Keep dialogue content separate from gameplay scripts and evaluate dialogue tooling in a bounded spike.

## Consequences

- GDScript and Godot scenes/resources are the common implementation language and artifact format for all agents.
- Forward+ supports the intended desktop visual direction, but performance must be measured on representative lower-end hardware before large-scale art production.
- No plugin is made a core dependency before its compatibility, license, maintenance, and workflow have been tested.
- A future renderer or engine change requires a measured technical reason and a migration plan, not personal preference.

## Revisit when

- A required target platform cannot support the current renderer.
- Profiling shows unacceptable performance on the minimum target hardware.
- A dialogue or content workflow cannot be delivered reliably in the selected engine.
