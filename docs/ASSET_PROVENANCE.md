# Asset Provenance Ledger

The biology-class prologue adds two font files. Everything else in the slice is
authored in-repo: geometry is generated from numbers in `.tscn`/generator passes,
materials are plain `StandardMaterial3D` resources, portraits are hand-written SVG,
and all audio cues are synthesised at runtime in `scripts/audio/audio_cues.gd`
(no audio files are stored). Nothing is downloaded at runtime.

| Asset/path | Type | Creator/source | Source URL | License / terms | Attribution required | Modifications | Commercial-use checked | Approved by |
|---|---|---|---|---|---|---|---|---|
| assets/fonts/NotoSansCJKsc-Regular.otf | Font (CFF/OTF) | Google / Adobe (Noto Sans CJK) | https://www.npmjs.com/package/@fontpkg/noto-sans-cjk-sc (v2.4.0, wraps upstream 2.004) | SIL Open Font License 1.1 — see assets/fonts/FONT_LICENSE_NOTICE.md | Not required by OFL; copyright notice retained in the file's name table and in FONT_LICENSE_NOTICE.md | Subset to Latin, punctuation, kana, CJK Unified Ideographs and fullwidth forms; vertical metrics and layout tables dropped; outlines unchanged | Yes — OFL 1.1 permits embedding and redistribution | Pending owner review |
| assets/fonts/NotoSansCJKsc-Medium.otf | Font (CFF/OTF) | Google / Adobe (Noto Sans CJK) | https://www.npmjs.com/package/@fontpkg/noto-sans-cjk-sc (v2.4.0, wraps upstream 2.004) | SIL Open Font License 1.1 — see assets/fonts/FONT_LICENSE_NOTICE.md | Not required by OFL; copyright notice retained | Same subset as Regular | Yes — OFL 1.1 | Pending owner review |
| assets/characters/*.svg | Portrait placeholders | Written for this repository | — | Project copyright (see COPYRIGHT.md) | — | Simple silhouettes; explicitly temporary per ART_BIBLE "temporary graybox assets" | n/a | Temporary |

The font subset keeps the OFL name table intact and does not rename the family, so
the "reserved font name" clause is not exercised.

Everything under `docs/captures/` is generated from this repository's own scene
data by `tools/preview_capture.gd` and `tools/dialogue_transcript.gd`; it contains
no third-party imagery and no manuscript text. It is developer evidence, not
shipped game content.

## Rules

- Record the exact asset or pack and the individual files included.
- Keep a copy/link to the license version that applied when obtained.
- Check commercial use, redistribution, modification, attribution, and AI-training restrictions where relevant.
- Marketplace purchase does not automatically permit redistribution of source files.
- An AI-generated asset is not automatically cleared for commercial use; record the tool, applicable terms, prompt/source references where appropriate, and the human editing/approval process.
- Do not commit credentials, private user data, or assets with unclear rights.
