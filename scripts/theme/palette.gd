class_name Palette
extends RefCounted
## The project's colours, as names, with no dependencies of their own.
##
## This is a **leaf** module: it imports nothing, owns no state and draws nothing, so any
## layer may name a colour without inverting the dependency direction in
## `docs/ARCHITECTURE.md` §2. That is the point of it. The bone accent used to be typed out
## as a literal in eight files - in the menus, in the HUD, in the notebook, and again as the
## fallback inside a data resource and a dialogue helper - and those copies had already begun
## to drift (the reading band's "ember" is 0.851/0.447/0.271 where the menus' is
## 0.851/0.396/0.255). A colour that lives in one file can be changed once.
##
## `MenuStyle` is still where the *menu* styling lives, and it re-exports these names, so
## `MenuStyle.INK` and `Palette.INK` are the same value and existing callers do not change.
## The rule that keeps it that way is `tools/check_ui_palette.py`: a colour value may be
## written out in exactly one file (issue #210).
##
## Speaker colours are **not** here. A character's accent is content: it is authored on
## `data/characters/*.tres`. The constants below are the shared fallback for a speaker whose
## profile names none.

## The dark the project draws on: menus, panels, the fades between rooms.
const INK := Color(0.043, 0.051, 0.051, 1.0)
## The dark, washed back over a scene.
const INK_WASH := Color(INK, 0.86)
## A panel ground a shade warmer than the ink.
const PANEL := Color(0.055, 0.065, 0.067, 0.96)
## The sheet under the pause menu, the confirmation and the settings box. Each caller picks
## its own alpha; the base is the same, which it was not before.
const SHEET := Color(0.04, 0.047, 0.048, 1.0)
## The page: warm, faintly yellow, and the colour of a nameplate's letters.
const PAPER := Color(0.898, 0.871, 0.804, 1.0)

## Body text on the ink.
const TEXT := Color(0.807, 0.788, 0.741, 0.92)
## Secondary text, and a disabled control.
const MUTED := Color(0.611, 0.6, 0.561, 0.9)

## The bone accent: the selected entry's rule, an outline, and a speaker's name when the
## speaker has no colour of their own.
const ACCENT := Color(0.776, 0.733, 0.643, 1.0)
## The one warm accent of the menus and the reading band: what is selected.
const EMBER := Color(0.851, 0.396, 0.255, 1.0)
## A caution colour: the check overlay's title, and a "warn" line.
const WARN := Color(0.82, 0.553, 0.349, 1.0)

## Entry text on a page, and the brighter, warmer white it turns when selected.
const PAGE_TEXT := Color(0.86, 0.835, 0.776, 0.94)
const PAGE_LIT := Color(1.0, 0.925, 0.851, 1.0)
## The colour fields behind the title: brick, ochre, and the dark of the ground.
const BRICK := Color(0.4, 0.192, 0.133, 1.0)
const OCHRE := Color(0.62, 0.471, 0.29, 1.0)
const GROUND := Color(0.027, 0.033, 0.033, 1.0)

## What a notebook entry of each kind is called in colour: seen, heard, remembered,
## imagined. A kind has to look the same wherever it is named - the notebook, the HUD's
## "noted" line, and (once the reading band is restyled on paper) its badges.
##
## `SOURCE_OBSERVED` is the bone accent today, but it is named for what it means: the colour
## of a seen thing may move without moving every border in the menus. `SOURCE_IMAGINED` and
## `WARN` are the same clay today, for the same reason.
const SOURCE_OBSERVED := ACCENT
const SOURCE_REPORTED := Color(0.561, 0.663, 0.710, 1.0)
const SOURCE_RECALLED := Color(0.604, 0.639, 0.592, 1.0)
const SOURCE_IMAGINED := WARN
