# Releasing

What a release of this project is, how the two platforms are built, what is verified before
anything is published, and — the part a player asks about first — why the Windows executable
says "unknown publisher".

This document describes the state after issue #66. It replaces nothing: it is the first
written record of the release process, because until now there was one platform, no icon, no
version in the file, and no policy for signing.

## What a release is

Two archives, built from one tag, by one workflow (`.github/workflows/release.yml`):

| Platform | Archive | What a player does |
| --- | --- | --- |
| Windows x86_64 | `where-is-school-<version>-windows.zip` | unzip, run `where-is-school.exe` |
| Linux x86_64 | `where-is-school-<version>-linux.zip` | unzip, run `./where-is-school` |

Both carry the same version, the same `HOW-TO-RUN.txt`, and the same `licences/` folder (the
SIL OFL text for the bundled Noto Sans SC subset, and `COPYRIGHT.md`). The Windows archive is
flat: executable, run notes, licences. The Linux archive is flat too, plus three files that
only make sense there — the binary without an extension, a desktop entry, and the icon the
desktop entry names.

They deliberately do **not** carry: `tests/`, `tools/`, `docs/`, `art/`, `addons/`,
`.github/`, the source font, or any `.pck` next to the executable (the pack is embedded in
both binaries). `tools/verify_build.py --package` fails the build if any of that appears.

## The version

There are three forms of the same version, and `tools/stamp_release_version.py` is the only
place that derives them:

| Form | Example | Where it appears |
| --- | --- | --- |
| tag | `v0.1.0-rc.1` | the Git tag, the GitHub release |
| label | `0.1.0-rc.1` | both archive names, the folder inside each archive |
| resource | `0.1.0.0` | `FileVersion` / `ProductVersion` inside the Windows executable |

A Windows version resource holds four 16-bit integers, so the `-rc.1` tail cannot survive into
it; the executable carries the numbers and the archive carries the string. That is not a
workaround, it is what the field is for.

The repository's own version lives in `packaging/version.txt` (one line, currently `0.1.0`),
and `export_presets.cfg` is committed stamped with it:

```sh
python3 tools/stamp_release_version.py --check   # the preset still says what the repo claims
python3 tools/stamp_release_version.py           # stamp from packaging/version.txt
python3 tools/stamp_release_version.py --version 0.1.0-rc.1   # what CI does for a tag
```

A build from a branch (pull request, `workflow_dispatch`) is labelled
`<version>-dev-<sha7>`, e.g. `0.1.0-dev-1a2b3c4`. It is never publishable: only a tag creates
a release.

**Prerelease rule:** a tag whose version contains a dash — `v0.1.0-rc.1`, `v0.2.0-beta.3` — is
published as a GitHub prerelease. A tag without one (`v0.1.0`) is a full release and becomes
`latest`. This is the whole rule; there is no second switch.

## The icon

The icon is drawn by `tools/build_app_icon.py` from a table of four shapes and a palette taken
from `assets/materials/classroom/`: a slate plate, an ivory doorway, the light through the gap,
and a honey threshold. It is original to this project — no third-party icon, no traced image,
no font glyph — and the palette is the classroom's own, so the application mark belongs to the
same room as the art it launches.

The script is the source of truth, not the PNGs:

```sh
python3 tools/build_app_icon.py          # rewrite assets/icon/ from the shape table
python3 tools/build_app_icon.py --check  # every pixel still matches the table
```

It writes:

| File | Purpose |
| --- | --- |
| `assets/icon/icon.svg` | the vector source, the same shapes, for whoever edits the mark next |
| `assets/icon/app_icon.ico` | 16/32/48/64/128/256 px entries; what the Windows export is pointed at |
| `assets/icon/app_icon_256.png` | the Linux package's icon and the desktop entry's target |
| `assets/icon/app_icon_512.png` | the large copy for documentation and store pages |

`--check` compares decoded pixels, not compressed bytes: a different zlib build may compress
the same image differently, and a check that fails for that reason is a check everyone learns
to ignore. It needs no engine, no network and no image library — the PNG writer and the ICO
container are thirty lines of `zlib` and `struct` in the tool.

`assets/icon/.gdignore` keeps Godot from importing these files. They are build inputs, not
game assets: the exporter reads `app_icon.ico` from disk, and the packaging step copies
`app_icon_256.png` next to the Linux launcher. Importing them would only add converted copies
to the pack and sidecars to the tree. The same trick, for the same reason, as `art/props/`.

**One follow-up this does not do:** the icon *inside the window* while the game runs still
comes from `project.godot`'s `config/icon`, which this change does not touch (that file
belongs to another agent). Setting it to `res://assets/icon/app_icon_256.png` and removing
`assets/icon/.gdignore` — so the file is imported — finishes the job. Until then the
executable, the taskbar, the window manager and the Linux menu entry all carry the project
icon, and the title bar of the running window does not.

## The Windows executable's metadata

`export_presets.cfg` (preset "Windows Desktop") turns resource modification on and fills in
what a version resource needs:

| Preset field | Value |
| --- | --- |
| `application/modify_resources` | `true` — without it Godot copies the template and patches nothing |
| `application/icon` | `res://assets/icon/app_icon.ico` |
| `application/file_version`, `application/product_version` | `0.1.0.0`, stamped per build |
| `application/product_name` | `where-is-school` |
| `application/company_name` | `BrainEno` (the name in `COPYRIGHT.md`) |
| `application/file_description` | `where-is-school - the vertical slice` |
| `application/copyright` | `Copyright (c) 2026 BrainEno. All rights reserved.` |

Godot 4 patches the template itself (`platform/windows/export/template_modifier.cpp` in
4.7.2-stable): it rewrites the `.rsrc` section with RT_ICON/RT_GROUP_ICON, RT_VERSION and a
manifest. No `rcedit`, no Wine, nothing to install on the Linux runner — which is why this
works in CI at all.

**Verification is on the finished file, not on the preset.** `tools/verify_build.py` parses
the PE resource directory and requires, for a package or a `--exe`:

- an `RT_GROUP_ICON` that declares at least two sizes, the largest at 48 px or more, and names
  only `RT_ICON` images that are actually in the file (a group whose images went missing is
  exactly what a half-applied icon change looks like);
- an `RT_VERSION` whose `VS_FIXEDFILEINFO` signature is `0xFEEF04BD`, whose file and product
  versions agree with each other and with the version being released, and whose
  `FileVersion`, `ProductVersion`, `ProductName`, `CompanyName` and `FileDescription` strings
  are all non-empty.

The preset-only check (`--preset`) exists as well, but only as a cheap pre-flight: it fails in
a second on a preset that cannot produce the build, instead of after a twenty-minute export.
It is never the evidence that the build is right.

## The Linux build

`export_presets.cfg` (preset "Linux") builds an x86_64 binary with the pack embedded, so the
archive contains one runnable file and no `.pck` to lose. Godot has no icon option for this
platform, and an ELF binary has nowhere to put one, so the icon is a file next to the binary
plus a `.desktop` entry that names it:

```ini
Exec=sh -c 'cd "$(dirname "$1")" && exec ./where-is-school' sh %k
Icon=where-is-school
```

`%k` is the desktop file's own path, which is how the entry works from wherever the folder was
unpacked instead of only from an installed location. `packaging/linux/README.txt` explains
running it, the execute bit, making a menu entry, Steam Deck (add as a non-Steam game, leave
Proton off — this is a native build), and the runtime requirements.

`tools/verify_build.py --package` checks the Linux archive for: the binary, the desktop entry,
the icon, `README.txt`, `HOW-TO-RUN.txt` and both licence files; that the entry is
`Type=Application`, runs the game, and names an icon that is present and at least 128×128;
that the binary is a 64-bit little-endian x86-64 ELF of executable type; and that the file
manager will be allowed to run it (the execute bit is stored in the zip and is checked, not
assumed).

## Checking a build yourself

```sh
# before an export: does the preset describe the build this version needs?
python3 tools/verify_build.py --preset export_presets.cfg --expect-version 0.1.0

# the artifact, which is what a player gets
python3 tools/verify_build.py --package dist/where-is-school-0.1.0-windows.zip --expect-version 0.1.0
python3 tools/verify_build.py --package dist/where-is-school-0.1.0-linux.zip --expect-version 0.1.0

# a bare executable, while iterating
python3 tools/verify_build.py --exe build/windows/where-is-school.exe --expect-version 0.1.0 --list
```

Both `--package` modes also read the pack out of the executable and run every rule the build
has always been held to: the game is in it, the tests/tools/docs/art are not, the font is the
subset of the current text, and the per-category size budgets are respected.

`tests/verify_build_test.py` is the boundary test for all of this: it builds a PE with a
resource section, an ELF header and release zips in memory, and breaks one thing at a time.
Run it with `python3 tests/verify_build_test.py`; it needs no engine.

## Signing: unsigned, and why

**Decision: releases are unsigned. No certificate is bought, none is faked, and no signing
secret is stored in this repository.**

What that means for a player:

- **Windows** shows "Windows protected your PC" the first time the executable runs, with an
  unknown publisher. "More info" → "Run anyway" gets past it. The download is unverified in
  the way that matters: nothing cryptographic binds the file to this project, so a copy from
  anywhere but the release page should not be trusted. The version resource says version and
  product and nothing about who built it.
- **Linux** shows no warning at all, which is not the same as being safe: there is simply no
  signature to check, by anyone.

Why not fix it:

- A code-signing certificate is a paid, identity-verified subscription (roughly 100–400 USD a
  year depending on the authority and the hardware token), renewed annually, and this project
  has no budget line for it, no legal entity to verify, and no update channel that would use
  it.
- A self-signed certificate does not help: SmartScreen does not trust it, Windows shows the
  same warning, and it would make the release look more official than it is. It is worse than
  nothing, so it is not done.
- Free programmes for open source (SignPath, Azure Trusted Signing) exist. Both need an
  organisation with a verifiable history, and both are worth revisiting when the project has
  one; that is the trigger to reopen this decision, and it is written down here so the next
  person finds it instead of re-deciding it in a chat.

What would change in the code when a certificate exists: `codesign/enable=true` in the Windows
preset, an `osslsigncode` (Linux) or `signtool` (Windows) run over the exported executable with
the certificate and password supplied as `actions` secrets, and a signature check in
`tools/verify_build.py --package` (the PE's certificate table) so an unsigned build cannot be
published by accident. None of that is enabled now, and `codesign/enable` is `false` in the
preset, which is what makes "unsigned" a fact about the file rather than a claim in a document.

## Cutting the first prerelease

The owner does this; the workflow does not create tags and no agent creates one.

1. **Merge to `main`.** The release builds whatever the tag points at.
2. **Check the build first, without publishing.** Actions → "Release build" → "Run workflow"
   on `main`. That produces two artifacts (`where-is-school-windows`, `where-is-school-linux`)
   and creates **no release**. Download both, and:
   - Windows: unzip, run `where-is-school.exe`, confirm the icon in Explorer and the version in
     the file's properties (`0.1.0.0`), and play the slice against
     `docs/PLAYTEST_CHECKLIST.md`.
   - Linux: unzip, `./where-is-school`, confirm the desktop entry's icon, play the same slice.
   This step exists because nothing in CI can click through SmartScreen or hear the audio.
3. **Tag the same commit.**
   ```sh
   git checkout main && git pull
   git tag -a v0.1.0-rc.1 -m "where-is-school 0.1.0-rc.1: first playable prerelease"
   git push origin v0.1.0-rc.1
   ```
   The dash is what makes it a prerelease. Nothing else needs setting.
4. **Watch the run.** The tag triggers the same build; this time the `publish` job downloads
   the two artifacts, verifies them again, and creates the release with both archives, marked
   prerelease, with notes naming the platforms, how to run each, the signing status and a link
   to the run that made it.
5. **Check the release page.** Both assets present, "Pre-release" badge, notes correct. If a
   build is wrong, delete the tag and the release
   (`gh release delete v0.1.0-rc.1 --yes`, `git push --delete origin v0.1.0-rc.1`) and start
   again from step 2 — a broken tag must never be re-pointed at a different commit, because a
   tag is what people pin.
6. **Tell players** that Windows will warn, and why, and link to this document.

Re-running the workflow for a tag that already has a release edits the release and replaces
its assets (`--clobber`), which is the recovery path for a failed upload.

## Known gaps in release engineering

Recorded so the next person does not rediscover them:

- **The Windows executable has never been run on Windows by CI.** Wine is not in the pipeline
  and would not be the same thing. The hands-on check in step 2 is the only evidence that it
  starts, and the playtest checklist is the only evidence that it plays.
- **The icon in the running window** is still Godot's default; see "The icon" above.
- **`packaging/HOW-TO-RUN.txt` still says "the executable carries the default engine icon"**
  in its known-gaps list. That is no longer true, and the file belongs to the UI workstream;
  the line should be dropped there rather than edited here.
- **No macOS, no AppImage, no Flatpak, no auto-update.** Linux ships as a folder with a
  desktop entry, which runs anywhere with glibc and a GL/Vulkan driver and needs no
  installation; that is deliberate for a slice, not a final answer for a game.
- **The Linux binary is built on `ubuntu-latest`**, so it needs the glibc of that image or
  newer. If that becomes a problem, the fix is building in an older container, not shipping a
  static binary.
