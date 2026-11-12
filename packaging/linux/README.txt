where-is-school — the vertical slice (Linux, x86_64)
====================================================

Run it
------
From a terminal, in this folder:

    ./where-is-school

If the file manager only offers to open it, right-click -> Properties -> Permissions and
allow "executing file as program", or run `chmod +x where-is-school` once. The archive
should already carry the executable bit; some extractors drop it.

Nothing is installed. Nothing is written outside the game's own settings file (the
language choice), which Godot keeps in ~/.local/share/godot/app_userdata/where-is-school/.

This build is unsigned — Linux does not ask a publisher, so there is no warning to click
through, but the file also has no signature to verify. `docs/RELEASE.md` in the source
repository records why, and what would change it.

A menu entry
------------
`where-is-school.desktop` launches the game with the icon next to it, and works when the
whole folder is kept together. To add it to the application menu:

    cp where-is-school.desktop ~/.local/share/applications/
    cp where-is-school.png ~/.local/share/icons/hicolor/256x256/apps/
    update-desktop-database ~/.local/share/applications 2>/dev/null || true

(the `Exec` line runs the game from the desktop file's own folder, so move the folder
first and re-copy the file if you move it again).

Steam Deck and other handhelds
------------------------------
Add `where-is-school` as a non-Steam game ("Add a Non-Steam Game" -> Browse). Proton is
not needed: this is a native Linux build, so leave the compatibility tool unset. The game
uses the mouse and the keyboard listed in HOW-TO-RUN.txt; a gamepad is not mapped in this
slice.

Requirements
------------
x86_64 Linux with a working OpenGL 3.3 or Vulkan driver (Godot 4.7 renders through either,
and falls back to OpenGL when Vulkan is missing), glibc 2.31 or newer, and about 100 MB of
disk. No runtime packages are needed: the engine is inside the executable, and the data is
inside it too, so there is no .pck next to it to lose.

Controls, known gaps and what this build is
-------------------------------------------
See HOW-TO-RUN.txt, shipped in this folder. Its first section is Windows-specific; the
controls, the "what this build is" notes and the reporting notes apply here unchanged.

Licences
--------
licences/ carries the licences of the two bundled Chinese fonts (Noto Sans SC and Noto
Serif SC) and the project's copyright notice. The rest of the build is the project's own
work, apart from the three dialogue portraits, whose terms are still being confirmed.
