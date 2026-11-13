# Location art: before and after

Frames from the game's own follow camera (1600×900 window, saved at 800 px wide), taken in
CI by `.github/workflows/location-art-capture.yml` with `tests/capture_locations.gd`.

- `before/`: `main` at `6cdf037` (the pull request's base), with this branch's capture
  script copied in so both sides stand the player on the same spots.
- `after/`: commit `f41d02a`, the last commit that changes a scene, a material or a
  texture. Later commits on the branch change only tests, CI and documents.
- Run: Location art capture `43253807325` (all ten capture jobs succeeded). The frames
  were read back from the run's annotations and committed unchanged.

Per location there is one wide view of the whole set (`<location>_wide.jpg`) and the
player standing at each arrival spot (`<location>_<nn>_<spot>.jpg`):

| Location | Frames |
|---|---|
| corridor | `wide`, `00_from_classroom`, `01_from_schoolyard` |
| street | `wide`, `00_from_corridor`, `01_from_residential`, `02_centre` |
| residential | `wide`, `00_from_street`, `01_from_stair`, `02_from_alley` |
| alley | `wide`, `00_from_courtyard`, `01_from_playground`, `02_centre` |
| playground | `wide`, `00_from_alley`, `01_from_corridor`, `02_centre` |

The classroom is not here: it is outside this round's scope and unchanged.
