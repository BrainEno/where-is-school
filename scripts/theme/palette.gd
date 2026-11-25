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
## The green of the look ring and the talk bubble: the mark the pointer draws on a thing or a
## person to look at or talk to. Read by name by `HoverCue` and `TalkBubble`.
const LOOK_GREEN := Color(0.55, 0.92, 0.5, 1.0)

## Entry text on a page, and the brighter, warmer white it turns when selected.
const PAGE_TEXT := Color(0.86, 0.835, 0.776, 0.94)
const PAGE_LIT := Color(1.0, 0.925, 0.851, 1.0)
## The colour fields behind the title: brick, ochre, and the dark of the ground.
const BRICK := Color(0.4, 0.192, 0.133, 1.0)
const OCHRE := Color(0.62, 0.471, 0.29, 1.0)
const GROUND := Color(0.027, 0.033, 0.033, 1.0)

## Source accents for the dark notebook and HUD. Bone and caution clay also serve other
## controls today, but those controls need not change if the source colours change.
const SOURCE_OBSERVED := ACCENT
const SOURCE_REPORTED := Color(0.561, 0.663, 0.710, 1.0)
const SOURCE_RECALLED := Color(0.604, 0.639, 0.592, 1.0)
const SOURCE_IMAGINED := WARN

## One source map for both surfaces (#288). Preserve the dark inks on light paper and
## the lighter accents on the dark notebook/HUD; sharing one RGB would lose contrast.
## Keys are NarrativeEntry's stable content IDs. Callers translate the enum to an ID so
## this file remains a leaf, and keep their own opacity and localized source label.
const _SOURCE_COLORS: Dictionary = {
	"observed": {"accent": SOURCE_OBSERVED, "ink": Color(0.42, 0.35, 0.29, 1.0)},
	"reported": {"accent": SOURCE_REPORTED, "ink": Color(0.24, 0.37, 0.52, 1.0)},
	"recalled": {"accent": SOURCE_RECALLED, "ink": Color(0.32, 0.4, 0.34, 1.0)},
	"imagined": {"accent": SOURCE_IMAGINED, "ink": Color(0.64, 0.32, 0.15, 1.0)},
}

## The reading band (#231): the dialogue is written on a sheet torn from an exercise book, in
## ink. Only the values the band's files share are here; each keeps its own one-off inks.
## The sheet itself, warm white.
const NOTEBOOK_PAPER := Color(0.93, 0.9, 0.82, 1.0)
## Pencil-grey: a speaker with no colour, the hint line, the mode words at rest.
const NOTEBOOK_MUTED := Color(0.36, 0.33, 0.35, 1.0)
## Red ink: an option at rest, a mode word under the pointer.
const RED_INK := Color(0.66, 0.24, 0.14, 1.0)
## The deeper red of an option under the pointer and of a mode that is on.
const RED_INK_LIT := Color(0.44, 0.1, 0.06, 1.0)


## Ink for a narrative source on the reading band's light paper.
static func source_ink(source_id: String) -> Color:
	var colors: Dictionary = _SOURCE_COLORS.get(source_id, {})
	return colors.get("ink", NOTEBOOK_MUTED)


## Accent on a dark ground. The HUD keeps its bone fallback for an unknown source.
static func source_accent(source_id: String, fallback: Color = PAPER) -> Color:
	var colors: Dictionary = _SOURCE_COLORS.get(source_id, {})
	return colors.get("accent", fallback)
