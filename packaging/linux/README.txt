where-is-school — the vertical slice (Linux, x86_64)
====================================================

Run it
------
From a terminal, in this folder:

    ./where-is-school

If the file manager only offers to open it, right-click -> Properties -> Permissions and
allow "executing file as program", or run `chmod +x where-is-school` once. The archive
should already carry the executable bit; some extractors drop it.

Support status: experimental. Linux desktop graphics, audio, controller behavior,
suspend/resume and Steam Deck playtesting are unverified. CI exports and inspects
the Linux archive; that does not establish that it plays correctly on your hardware.
Windows PC remains the first target. No distro or Steam Deck certification is claimed.

Do not run the game as root or with sudo. Nothing is installed and the unpacked
folder need not be writable. Godot writes per-user data under:

    ${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/where-is-school/

XDG_DATA_HOME overrides ~/.local/share when set. This is not the game folder.
It holds save.json (progress), save.broken.json (an unreadable save kept for you),
settings.cfg (language, text, audio, display and controls), and logs/ (local
technical events and an optional manually exported diagnostics-latest.json).
Back up this folder before removing data; deleting the unpacked build does not
reset a run. For reports, export diagnostics from Settings rather than sending
your save or the whole folder. The game uploads nothing.

This build is unsigned — Linux does not ask a publisher, so there is no warning to click
through, but the file also has no signature to verify. `docs/RELEASE.md` in the source
repository records why, and what would change it.

A desktop launcher
------------------
The bundled where-is-school.desktop uses %k (the desktop file's own path) to
find the game. Keep it beside where-is-school and where-is-school.png. A file
manager may require marking the launcher trusted, or may not support launching
it in place; use the terminal command above if it does not. Launcher behavior
and icon resolution vary by desktop and are unverified here.

Do not copy this desktop file alone into ~/.local/share/applications/: %k would
then name that directory instead of the unpacked game folder, so it could not
find the binary. To create an application-menu entry, use your desktop's launcher
editor with the absolute path to the unpacked executable and icon. Update that
entry if you move the game folder. Installing a menu entry is optional.

Steam Deck and other handhelds
------------------------------
Add `where-is-school` as a non-Steam game ("Add a Non-Steam Game" -> Browse). Proton is
not needed: this is a native Linux build, so leave the compatibility tool unset. The game
maps keyboard/mouse and Xbox-style controller inputs as listed in HOW-TO-RUN.txt.
Controller mappings in code are not a Steam Deck hardware acceptance result.

Requirements and troubleshooting
--------------------------------
Use an x86_64 Linux system with a graphical desktop and working graphics drivers.
The default renderer is Forward+ (Vulkan on Linux). If it cannot start, try the
Compatibility renderer explicitly from the terminal:

    ./where-is-school --rendering-method gl_compatibility --rendering-driver opengl3

Compatibility needs a working OpenGL 3.3 driver; it is an alternate diagnostic
path, not a promise of identical visuals or an automatic fallback. Include the
renderer and driver when reporting a failure. Do not assume running over SSH
without a display or a software renderer proves playable performance.

The engine and game data are embedded; there is no sibling .pck to install or
keep. System libraries and graphics drivers are still required. This project
has not measured a minimum glibc version or certified a distro: if the terminal
reports a missing library or GLIBC version, record that message and the build's
version instead of replacing system libraries or assuming a claimed minimum.
Allow space for the uncompressed archive as well as the downloaded ZIP.

Controls, known gaps and what this build is
-------------------------------------------
See HOW-TO-RUN.txt, shipped in this folder. It includes both platforms' launch
commands, the controls, checkpoints, known limits and offline diagnostics steps.

Licences
--------
licences/ carries the licences of the two bundled Chinese fonts (Noto Sans SC and Noto
Serif SC) and the project's copyright notice:

  licences/NotoSansSC-OFL.txt     Noto Sans SC, the interface font (SIL Open Font License)
  licences/NotoSerifSC-OFL.txt    Noto Serif SC, the reading text (SIL Open Font License)
  licences/COPYRIGHT.md           the project's copyright and permissions notice

The rest of the build is the project's own work, apart from the three dialogue portraits,
whose terms are still being confirmed, so treat them as not cleared for reuse.
