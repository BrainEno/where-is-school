# Asset Provenance Ledger

No third-party, marketplace, downloaded, or AI-generated production assets are
present in this repository. Everything committed so far was authored inside the
repository from Godot primitives, plain data files, or the project's own
synthesis script.

| Asset/path | Type | Creator/source | Source URL | License / terms | Attribution required | Modifications | Commercial-use checked | Approved by |
|---|---|---|---|---|---|---|---|---|
| `scenes/environment/props/*.tscn`, `scenes/locations/**`, `scenes/ui/**` | Graybox 3D scenes and UI layouts | Authored for this repository from Godot primitive meshes and Controls | — | Project-owned placeholder, see COPYRIGHT.md | No | — | n/a (no third-party source) | Pending owner art review |
| `assets/materials/*.tres` | Placeholder StandardMaterial3D colours | Authored for this repository; colours follow docs/ART_BIBLE.md palette anchors | — | Project-owned placeholder | No | — | n/a | Pending owner art review |
| `assets/audio/room_tone_classroom.wav` | Ambient room tone (6 s, mono 22.05 kHz) | Synthesised by `tools/generate_placeholder_audio.py` (sine hum + white noise, in-repo algorithm) | — | Project-owned placeholder | No | — | n/a (no external samples) | Pending owner audio review |
| `assets/audio/room_tone_walkway.wav` | Ambient walkway tone (6 s) | Same script, different level/air parameters | — | Project-owned placeholder | No | — | n/a | Pending owner audio review |
| `assets/audio/bell_second.wav` | School bell one-shot (2 s) | Same script, additive sine bell with tremolo envelope | — | Project-owned placeholder | No | — | n/a | Pending owner audio review |
| `assets/audio/wake_thud.wav` | Low thud and breath for the wake beat (1.6 s) | Same script | — | Project-owned placeholder | No | — | n/a | Pending owner audio review |
| `data/dialogue/*.json`, `data/inspections/*.json`, `data/characters/*.tres` | Placeholder game text and speaker metadata | Written for this prototype; not derived from the private manuscript | — | Project-owned | No | — | n/a | Pending owner writing review |

## Notes

- The audio files are regenerated deterministically by
  `python3 tools/generate_placeholder_audio.py`; the script is the provenance.
- No generated imagery, marketplace packs, fonts, or shader libraries are used.
  The project deliberately relies on the engine's built-in font for now; any
  bundled CJK font for localisation must be added here with its license before
  it enters the tree.
- Every placeholder above is expected to be replaced by owner-approved art,
  audio, and writing. Record replacement assets in this ledger as they land.

## Rules

- Record the exact asset or pack and the individual files included.
- Keep a copy/link to the license version that applied when obtained.
- Check commercial use, redistribution, modification, attribution, and AI-training restrictions where relevant.
- Marketplace purchase does not automatically permit redistribution of source files.
- An AI-generated asset is not automatically cleared for commercial use; record the tool, applicable terms, prompt/source references where appropriate, and the human editing/approval process.
- Do not commit credentials, private user data, or assets with unclear rights.
