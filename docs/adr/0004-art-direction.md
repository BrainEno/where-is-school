# ADR 0004 — Art direction, spatial logic, and camera

- **Status:** Proposed — owner-confirmed artistic direction; camera and implementation details remain open.
- **Date:** 2026-11-11
- **Depends on:** ADR 0001 (engine and renderer)
- **Blocks:** #54 (rendering pipeline), the classroom vertical slice, and later environment / character asset decisions.

## Context

The project is a literary 2.5D narrative exploration game. Its world is not required to obey ordinary physical geography or realistic perspective. The school is experienced from within: play begins in a classroom, and exploration gradually moves outward through spaces whose relationships may become increasingly unstable.

The visual target is not clean flat shading, a generic cartoon look, or a photographic PBR presentation. The owner selected the painterly character-portrait direction in *Disco Elysium* as the closest reference among the references reviewed. The intention is to carry a related painterly language across both character imagery and environments, while developing an identity specific to this game rather than copying another game's assets or compositions.

This ADR separates owner-confirmed artistic intent from technical choices that still need a playable comparison. A visual direction can be accepted before the exact Godot rendering pipeline is known.

## Decision 1 — Spatial logic and exploration

**Owner-confirmed direction:** the game begins inside the school, in a classroom. Exploration proceeds from the inside toward other school spaces; it is not structured around entering the school from the street.

The geography is allowed to become progressively dreamlike and unreliable:

- A route need not form a consistent, physically plausible floor plan.
- Corridors, stairs, rooms, and thresholds may connect in spatially contradictory ways.
- The same door or entrance may lead to different places at different story moments.
- Loops, discontinuities, and changes in spatial adjacency are valid narrative devices.
- The player should still be able to understand the immediate playable space and operate the controls; local legibility is not the same as globally realistic geography.

**Not decided here:** the exact level graph, transition rules, trigger conditions, scene-loading architecture, and whether any particular spatial contradiction is authored as a one-off event or driven by reusable data. Those belong to implementation design and later level-specific decisions.

## Decision 2 — Camera and perspective

**Owner-confirmed constraint:** camera composition does not have to reproduce realistic human vision or obey consistent real-world perspective. The dream framework permits deliberate distortion and visual misalignment.

**Provisional direction:** investigate an orthographic or orthographic-like camera first, because it may support authored compositions and spatial ambiguity. This is a preference for the first visual experiment, not a final commitment to orthographic projection.

The classroom vertical slice must compare at least:
- an orthographic composition; and
- a perspective composition with restrained convergence / a long-lens feel.

Judge the comparison in motion and in representative gameplay views, not from a technical table alone. Evaluate character readability, room depth, occlusion, navigation, and whether the result supports the intended dreamlike space. The final projection, field of view, camera distance, offset, and framing values remain open until that comparison is reviewed.

Do not choose perspective merely to preserve realism, and do not choose orthographic merely because the game is dreamlike. The image and play experience decide.

## Decision 3 — Painterly visual language for characters and environments

**Owner-confirmed direction:** both character imagery and environments should pursue a painterly visual language broadly comparable to the character portraits and environments of *Disco Elysium*. This is the clearest decision made in this discussion.

The target is painterly color construction rather than clean, uniform flat shading:

- Forms are built from expressive color masses, layered color relationships, and deliberate light / shadow.
- Brushwork, uneven edges, softened transitions, and visible surface character may remain present.
- Color can be emotionally motivated rather than physically accurate.
- The image may feel dense, muddy, atmospheric, and hand-worked rather than polished, sterile, or plastic.
- Character portraits and environment imagery should belong to the same broad visual world, while retaining different compositional needs.
- The reference is a starting point for visual principles, not a request to reproduce *Disco Elysium* literally.

This must not be reduced to placing a generic oil-paint filter or noise texture over otherwise conventional assets. The painterly quality should come from the organization of shape, color, value, edges, lighting, and marks.

**Scope clarification:** the owner explicitly confirmed character portraits and environments. The exact treatment of in-game 3D character meshes, including shader model, texture workflow, UV requirements, and how closely they should match the portraits, remains a technical and art-production question for the classroom / character prototype.

## Consequences

- Art reviews should assess portraits and environment images against the same painterly intent, rather than approving clean flat-shaded characters beside unrelated environment treatments.
- The art team may use non-naturalistic color, deliberate perspective shifts, irregular contours, and atmospheric transitions when they strengthen the image.
- Gameplay readability remains mandatory: interactive objects, exits, walkable surfaces, and character silhouettes must remain understandable at the actual camera distance.
- A rendering implementation must be tested against representative assets. This ADR does not mandate a specific shader, post-processing stack, texture library, or 3D-to-paintover workflow.
- The classroom is the first useful comparison space because it can test the camera, the painterly environment treatment, and character readability together.
- Do not start a broad asset-production pass or lock model UV / normal-map requirements solely on the basis of an untested shader recommendation.

## Open questions intentionally left unresolved

1. Final camera projection and numeric camera settings.
2. The technical method for painterly rendering of in-game 3D characters and environments.
3. How portrait assets are produced and integrated with the dialogue UI.
4. The reusable implementation model for changing door destinations and other non-Euclidean transitions.
5. The exact palette and the balance between painterly density and readable negative space.

## Revisit when

- The classroom vertical slice can be judged in motion with representative character and environment assets.
- The chosen camera makes navigation, occlusion, or character readability worse than the alternative.
- A rendering prototype looks like a generic filter or loses the intended painterly character.
- The spatial-transition implementation begins constraining narrative design rather than enabling it.
