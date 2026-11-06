class_name Language
extends RefCounted
## The player's language choice, and every literal string the UI itself owns.
##
## Content (dialogue, inspections, ledger entries) is written per-line in both
## languages and picks its own field from `current`. This class covers the other
## half: button captions, hints, group headings, the interaction prompt — strings
## the UI generates rather than reads out of data.
##
## Deliberately all-static and NOT an autoload:
## - a headless test run (`--script tests/foo.gd`) does not instantiate autoloads,
##   so an autoload here would make every UI script uncompilable in the tests;
## - language is a presentation preference, not narrative state, so it must not
##   live in GameState either.
## The cost is no `language_changed` signal: the caller that flips the switch is
## also the caller that refreshes the surfaces (see PrologueMain._toggle_language).
##
## Rules that keep the two languages from leaking into each other:
## - Every bracketed-key style literal goes through `kb()` so a key is never
##   hardcoded in one language's sentence.
## - Callers must not concatenate zh and en. They pass both to a display method
##   that chooses one (see `pick`).

const ZH: StringName = &"zh"
const EN: StringName = &"en"

## Set by the player; the game starts in Chinese.
static var current: StringName = ZH


static func is_zh() -> bool:
	return current == ZH


## The one place a zh/en pair becomes a single displayed string.
static func pick(text_zh: String, text_en: String) -> String:
	var chosen: String = text_zh if is_zh() else text_en
	if chosen.strip_edges().is_empty() and not (text_zh.strip_edges().is_empty() and text_en.strip_edges().is_empty()):
		# Falling back is better than an empty panel, but it must be loud so a
		# missing translation is caught during authoring.
		push_warning("Missing %s text; falling back to the other language." % String(current))
		return text_en if is_zh() else text_zh
	return chosen


static func set_language(language: StringName) -> bool:
	if language != ZH and language != EN:
		push_error("Unknown language '%s'. Use Language.ZH or Language.EN." % language)
		return false
	if language == current:
		return false
	current = language
	return true


static func toggle() -> void:
	set_language(EN if is_zh() else ZH)


## The label for the switch button: shows the language you would get, which is
## the wording players read as an action.
static func other_label() -> String:
	return "English" if is_zh() else "中文"


## Bracket-key hint, e.g. kb("N", "笔记", "notes") -> "[N] 笔记".
static func kb(key: String, label_zh: String, label_en: String) -> String:
	return "[%s] %s" % [key, pick(label_zh, label_en)]


## Both languages on one button, for the switch itself where the current language
## must stay visible.
static func pair(zh: String, en: String) -> String:
	return "%s / %s" % [zh, en]
