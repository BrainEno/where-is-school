# Asset Provenance Ledger

The assets below are **prototype placeholders**, not approved production art or audio. The project's original materials are reserved under [COPYRIGHT.md](../COPYRIGHT.md); that file does not grant a separate open-source license. The owner must review and approve assets and commercial-use rights before production use.

| Asset/path | Type | Creator/source | Source URL | License / terms | Attribution required | Modifications | Commercial-use checked | Approved by |
|---|---|---|---|---|---|---|---|---|
| `scenes/actors/{player/player,classmate,substitute}.tscn`, `scenes/environment/*.tscn`, `scenes/locations/*.tscn` | Graybox actors, furniture, and environments | Created for this prototype with Godot primitive meshes, shapes, colors, and labels; no third-party models or textures | None | Original project materials; see `COPYRIGHT.md` | No third-party attribution identified | Initial implementation and collision/lighting tuning | No third-party source used; owner review pending | Pending owner approval |
| `assets/audio/classroom_roomtone.wav` | 4 s mono, 22.05 kHz placeholder ambience | Numerically synthesized in Python for this prototype; no sampled recording | None | Original project material; see `COPYRIGHT.md` | No third-party attribution identified | Synthesized and imported with Godot WAV settings | No third-party source used; owner review pending | Pending owner approval |
| `assets/audio/lesson_bell.wav` | 1.5 s mono, 22.05 kHz placeholder bell | Numerically synthesized in Python for this prototype; no sampled recording | None | Original project material; see `COPYRIGHT.md` | No third-party attribution identified | Synthesized and imported with Godot WAV settings | No third-party source used; owner review pending | Pending owner approval |
| `docs/screenshots/*.png` | Verification captures | Captured from the running prototype with the Godot 4.7.2 Compatibility renderer and software graphics | None | Project captures; see `COPYRIGHT.md` | No third-party attribution identified | Cropped to the game window by the capture script; no compositing | Owner review pending | Pending owner approval |

Godot's default theme font and available system fallbacks are used at runtime; no external font file is bundled, so Chinese glyph coverage depends on the machine. The WAV import sidecars are committed, while generated `.godot/` caches are not. The placeholder text in `data/dialogue/biology_class.json` was independently written for implementation, not copied from unpublished manuscripts, and also requires owner review before production.

## Rules

- Record the exact asset or pack and the individual files included.
- Keep a copy/link to the license version that applied when obtained.
- Check commercial use, redistribution, modification, attribution, and AI-training restrictions where relevant.
- Marketplace purchase does not automatically permit redistribution of source files.
- An AI-generated asset is not automatically cleared for commercial use; record the tool, applicable terms, prompt/source references where appropriate, and the human editing/approval process.
- Do not commit credentials, private user data, or assets with unclear rights.
