# Implementation notes — the build

The round that made the slice exportable: `export_presets.cfg`, a release workflow that
exports on a real runner, a font subset that took 10 MB out of the pack, and a tool that
reads the finished build back to check what is in it.

Everything below is about packaging. Nothing in the game changed: same rooms, same text,
same anchors.

## 1. Why a build, now

Every milestone pull request since the first vertical slice ends with the same sentence:
"Windows hands-on checks are listed in the pull request and are not yet performed." Six
rounds of that is not a scheduling failure, it is a missing deliverable. `export_presets.cfg`
was in `.gitignore`, so no build had ever been produced from this repository — not by CI,
not by the owner. The automated suite proves the game *runs*; nothing proved it *packs*,
and nobody could be handed something to play.

The next content round needs playtest data (Phase 6 depends on it explicitly: the dice are
to be retuned "against real playtest data", and the inner voice may grow into several
voices). That data cannot exist until a build exists.

## 2. The preset

`export_presets.cfg` is committed. One preset, `Windows Desktop`, x86_64:

| Setting | Value | Why |
|---|---|---|
| `binary_format/embed_pck` | `true` | One file to hand over. A loose `.pck` beside the executable is one more thing to lose, and the first question a playtester asks is "which file do I run". |
| `binary_format/architecture` | `x86_64` | The baseline in `docs/TECHNICAL_ROADMAP.md` §1. A 32-bit build would run on nothing this game targets. |
| `exclude_filter` | `tests/*, tools/*, docs/*, art/*, .github/*, packaging/*` | `docs/screenshots` alone is 9.4 MB of committed PNGs, and they are *imported textures*, so by default every one of them was going to be packed into the player's download. `art/` is source material (`.blend`, the full font) and is `.gdignore`d, but it is excluded by name too so a future `.gdignore` mistake cannot put a 10 MB font in a build. |
| `include_filter` | `""` | "All resources" already covers the dialogue JSON in `data/`. Verified rather than assumed — see §4. |
| `script_export_mode` | `2` | Compressed binary tokens. Shipping readable GDScript in a narrative game is shipping the script of the twist in the same folder as the game. |
| `application/modify_resources` | `false` | There is no `.ico` and no version metadata to stamp yet, and `rcedit` is not installed on the Linux runner. Turning it off means an export cannot fail on the runner because of a Windows-only tool. The cost is the default engine icon, which is listed in the run-me file. |
| `codesign/enable` | `false` | There is no certificate. This is a real limitation, not a setting: an unsigned executable gets a SmartScreen warning, and worse, some corporate machines quarantine it outright. That is recorded in `docs/PLAYTEST_CHECKLIST.md` §1 as something to report. |

The preset used to be gitignored, on the theory that an export preset is a local file with
machine-specific paths. It has no machine-specific paths, and the build has to be
reproducible from the repository: same reversal as tracking the `.import` sidecars in issue
#37, and `.gitignore` §2 records it.

## 3. The font

`assets/fonts/NotoSansSC-Regular.ttf` is Noto Sans SC: 10.07 MiB, 30,890 mapped characters.
The game can currently draw 819 of them, plus punctuation margin.

Up to this round the whole font was in every build, because a `.ttf` under `res://` is an
imported resource and every imported resource is packed. Nothing needs 29,000 glyphs of
coverage for a fifteen-minute slice in one language pair.

The split:

- `art/fonts/NotoSansSC-Regular.ttf` — the untouched upstream file, next to the `.blend`
  sources, with an `art/fonts/.gdignore` so Godot never imports it.
- `assets/fonts/NotoSansSC-Regular.ttf` — the **subset**, same path, same import sidecar,
  same resource uid. Only the bytes changed, so nothing else in the project moved: the
  theme still points at the same path.

`tools/subset_font.py` rebuilds the subset from the current text and is the only thing that
writes it. Its character set is:

- every character in `data/**/*.json` (dialogue, inspections, interface strings),
  `scenes/**/*.tscn`, `scripts/**/*.gd`, `tests/**/*.gd` and `project.godot` — tests
  included on purpose, so a test that renders Chinese is not the thing that finds a missing
  glyph;
- plus fixed ranges whether or not today's text uses them: ASCII, Latin-1, general
  punctuation (the em dash and the curly quotes), currency, arrows, mathematical operators,
  geometric shapes, CJK punctuation (`、。「」`) and full-width forms (`，！？：；（）`). Those
  cost about 20 KiB and remove the most common reason to regenerate.

Result: **325 KiB, 32× smaller**, byte-for-byte reproducible (the build is deterministic, so
CI can compare the committed file with a fresh one instead of trusting a comment).

**What breaks, and what happens then.** New text that uses a character outside the subset
would render as a tofu box in a *build* — where no headless test would ever see it. Both CI
workflows therefore run `tools/subset_font.py --check`, which fails on exactly that, names
the characters, and says to run the tool. The fix is one command and needs only `fonttools`
and the source font in `art/fonts/`. It also fails when a font larger than 2 MiB sits under
`assets/`, which is what accidentally moving the source font back would look like.

The licence travels with the file: `assets/fonts/OFL.txt` is copied into the zip beside the
executable, in `licences/`.

## 4. Verifying the build, not the preset

An export preset is a wish list; the pack is the truth. `tools/verify_build.py` reads the
pack back out of the finished executable and checks both directions:

- **the game is in it**: `scenes/main/main.tscn`, the theme, `data/dialogue/{en,zh-CN}/`,
  `data/inspections/en/`, at least one audio file;
- **the repository is not**: nothing under `tests/`, `tools/`, `docs/`, `art/`, `.github/`;
  the font is under 1 MiB; the whole pack is under 16 MiB.

It also prints the largest entries, so a build that suddenly doubles explains itself in the
log instead of in a bug report. This is the check that makes "all resources" trustworthy: if
the dialogue JSON were *not* packed, the game would launch into an empty conversation and
the export would still have exited 0.

Format note: the tool parses the Godot 4 pack directory directly (magic `GDPC`, version 2,
then a directory of path/offset/size/md5/flags). If the engine changes the format it fails
loudly with the header it saw rather than reporting a cheerful empty build. Both paths —
`--exe` (embedded pack, the shipped artefact) and `--pck` (standalone) — are supported.

## 4a. What the first real build weighed

Numbers from the first successful export (CI run of this pull request), because "the build
is small now" is worth nothing without them:

| Part | Size | Note |
|---|---|---|
| The game (pack) | **1.31 MiB**, 246 files | Everything the engine loads: scenes, scripts, dialogue JSON, the subset font, three models, five sounds. |
| Largest single entries | 225 KiB `.fontdata`, 206 KiB bench `.scn`, 134 KiB backpack `.scn` | The font's converted form is smaller than the 325 KiB `.ttf` it comes from, because the importer compresses it. |
| Executable | **105 MiB** | Almost entirely the engine: the 4.7.2 release template. The game is 1% of it. |
| Zip | **37 MiB** | What actually travels. |

What is *not* in the pack, and was going to be: `docs/screenshots` (65 imported textures,
9.4 MB of PNG), the 10 MiB source font, `tests/`, `tools/`, `art/`. The verifier checks the
absence as firmly as the presence.

The pack's layout is worth knowing when reading these numbers: an imported resource is
stored as a `res://…​.import`-style stub plus the converted data under
`.godot/exported/<hash>/`, and paths inside the pack carry no `res://` prefix (the packer
strips it). That is why "is the font in the build" is answered by a per-file size budget
rather than by looking up one exact path.

## 5. What a player downloads

```
where-is-school-<version>-windows.zip
  where-is-school-<version>-windows/
    where-is-school.exe          the game; pack embedded
    HOW-TO-RUN.txt               controls, the SmartScreen warning, known gaps
    licences/NotoSansSC-OFL.txt  the font licence
    licences/COPYRIGHT.md        the project's own terms
```

Built by `.github/workflows/release.yml`: on a pull request and on demand it is a check with
an artefact attached; on a `v*` tag it also publishes a GitHub release. A failed or partial
build can never become a download, the same split as the capture workflow's
read-only-capture / publish-only-on-main arrangement.

## 6. Not in this round, and known limits

- **No icon or version metadata** on the executable (default engine icon, no file
  properties). Needs an `.ico` and `rcedit` on the runner, or `modify_resources` with a
  Windows runner.
- **Unsigned.** SmartScreen warns; some managed machines quarantine. Only a certificate
  fixes this, and that is a purchasing decision, not a task.
- **Windows only.** Linux and macOS presets, Steam and Steam Deck evaluation are Phase 7 in
  `docs/TECHNICAL_ROADMAP.md` §5, and each needs its own packaging decisions (a macOS
  `.app`/notarisation, a Linux tarball or AppImage).
- **No save/load, no settings screen, no pause menu** — so a playtest is one sitting, and
  the only persisted setting is the language. Both are Phase 7 items and both are listed in
  the run-me file so a playtester does not report them as bugs.
- **The 10 MB source font stays in git.** It is the input to the subset, and a clone
  carrying it is the price of being able to rebuild the subset offline. Repo size is a
  separate decision from build size; if it ever matters, the source moves to a download
  step with a pinned checksum, which breaks the "works offline" property this project has
  deliberately kept.

## 7. Evidence

| Claim | Where it is checked |
|---|---|
| The project exports without an error | `release.yml` "Export the Windows build" |
| The pack contains the game and not the repository | `tools/verify_build.py` in the same workflow |
| The shipped font can still draw all current text | `tools/subset_font.py --check`, in both CI workflows |
| The game still runs after the font changed | the 34 headless checks and the capture workflow, unchanged |
| Someone can actually play it | **not automatic**: `docs/PLAYTEST_CHECKLIST.md`, by hand, on Windows |

The last row is the point of the round. The first four were already true; only the fifth
can tell us whether any of this is worth playing.
