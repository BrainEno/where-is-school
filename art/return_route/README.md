# Equipment return line — outdoor interaction pass

> Historical design note: the yard return board, marking kit and dependent shed comparison have since been removed. Street and alley details and the tap remain.

English source. [Simplified Chinese reading copy](README.zh-CN.md).

The street, courtyard, alley and yard are one playable loop, not four rooms to fill uniformly. Keep their long sight lines and open middle. Cream enamel, blue-grey iron and a single ochre lip sit against the established palettes. Marks are small and functional: one rail, two unequal ticks at one end, and an arrow. Flipping that pattern makes a bad sign recognizable without adding a new door or asserting anything about how the school works.

| Place | Readable detail | What it does |
| --- | --- | --- |
| Street | Enamel return plate on the school plinth; worn receipt slot further along | The arrow points towards the flats stair; its right-hand ticks become a note. The slot is a short observation, not another objective. |
| Courtyard | Smaller enamel plate at the alley mouth; sweepings under the bench with its replaced slat | Helps find the existing passage and makes an existing bench inspection visible. No new prompt, journal flag or objective here. |
| Alley | Wrong-way version of the same plate; trolley guide with a wooden shim | The left-hand ticks are recorded separately. The shim shows how the lane is used without making it a puzzle or narrowing the path. |
| Yard | Two-sided return board; chalk-line kit; tethered drain cap; matching slip in the shed window | The board gives the two ordinary exits on the very first read. The kit can help interpret the slip. The tap does not have to be used. |

The board replaces the inspection that reused the court-floor description. First reads of the two outside plates and board unlock a **choice**, not an automatic roll, at the existing shed. The chalk-line kit is optional and adds one situational point. A visible Orientation check separates a match from an uncertain comparison; both are written as observations. The directions remain useful without either plate, and failure neither closes a gate nor completes the original shed interaction. Revisiting cannot reroll the comparison. No new inventory, quest scheduler, player input or ability.

## Source and regeneration

Authored in the two existing Python art passes. The mark and arrows are shared mesh geometry, not a texture or font. No downloaded or generated image, model or sound was imported. Materials come from each scene's existing local palette; decorative meshes are non-solid. Wall plates are children of their occluder owners so they do not hang in front of faded walls. The yard board fits two sloping faces below waist height on the original post footprint, to keep the player visible in the follow camera. Spawns, exits and physical collision are unchanged.

```sh
python3 tools/build_outdoor_locations.py street residential alley playground
python3 scenes/environment/props/stage_art/source/build_stage_art.py  # existing numpy/Pillow dependency
python3 scenes/environment/props/playground_art/source/build_playground_art.py
```

The effect and text pairs live in `data/{inspections,dialogue}/{en,zh-CN}/`. The board's close view uses `assets/camera/shots/return_board.tres`. `tests/return_route_test.gd` walks the real route, uses keyboard interaction and mesh clicks, and checks a marginal roll with and without the kit. `tests/capture_locations.gd -- return-route` supplies matched before/after positions to the Location art capture workflow. Review the diagram and text at gameplay distance, not from an unrestricted editor camera.
