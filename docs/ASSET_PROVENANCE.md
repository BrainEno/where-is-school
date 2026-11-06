# Asset Provenance Ledger

Populate this ledger before adding third-party, generated, marketplace, or externally sourced assets. The biology-class prologue adds one third-party item (a CJK font); everything else is original project work.

| Asset/path | Type | Creator/source | Source URL | License / terms | Attribution required | Modifications | Commercial-use checked | Approved by |
|---|---|---|---|---|---|---|---|---|
| `assets/fonts/NotoSansSC-Regular.ttf` | Font (CJK, weighted static instance, 400) | Google Noto Sans SC, distributed via the `@fontsource/noto-sans-sc` package (v5.3.1) | https://fontsource.org/fonts/noto-sans-sc | SIL Open Font License 1.1 — license text committed at `assets/fonts/OFL.txt` | No attribution required in-game; OFL notice kept with the file | None; redistributed unmodified | Yes — OFL 1.1 permits embedding and redistribution | Owner: pending explicit sign-off, see note below |

## Notes

- The font is the only third-party asset in the repository. It is needed because
  the prologue's dialogue is Chinese and the engine cannot render CJK glyphs
  without a font that contains them. The engine itself has no bundled CJK font,
  and the headless validation build has no system font support.
- No audio files, textures, models, or portraits are committed. `RoomTone`
  synthesises its ambience at runtime, and all geometry is generated from engine
  primitives inside the scene files.
- Everything else in `scenes/`, `scripts/`, and `data/` is original project work
  written for this milestone.

## Rules

- Record the exact asset or pack and the individual files included.
- Keep a copy/link to the license version that applied when obtained.
- Check commercial use, redistribution, modification, attribution, and AI-training restrictions where relevant.
- Marketplace purchase does not automatically permit redistribution of source files.
- An AI-generated asset is not automatically cleared for commercial use; record the tool, applicable terms, prompt/source references where appropriate, and the human editing/approval process.
- Do not commit credentials, private user data, or assets with unclear rights.
