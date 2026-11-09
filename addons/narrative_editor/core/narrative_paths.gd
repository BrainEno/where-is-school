extends RefCounted
## Editor-only: where content lives, and how many chapters there really are.
##
## The chapter list is read from the directory tree, not from a second constant. The
## project already keeps `DialogueLibrary.CHAPTERS` and `InspectionLibrary.CHAPTERS`, and
## a tool with its own copy of that list would silently fall out of date the first time a
## chapter is added. So the files are the list; the constants are then used as a
## cross-check, and a disagreement is reported in the dock instead of being hidden.
##
## `data_root` exists so the tests (and nothing else) can point the same code at a
## `user://` copy of the content and edit it without risking the real files.

const DialogueLibraryScript := preload("res://scripts/dialogue/dialogue_library.gd")
const InspectionLibraryScript := preload("res://scripts/narrative/inspection_library.gd")

const DEFAULT_DATA_ROOT := "res://data"
const DIALOGUE_DIR := "dialogue"
const INSPECTION_DIR := "inspections"
const ABILITY_DIR := "abilities"
const ABILITY_STRUCTURE_FILE := "abilities.json"

var data_root: String = DEFAULT_DATA_ROOT


func _init(root: String = DEFAULT_DATA_ROOT) -> void:
	data_root = root if not root.is_empty() else DEFAULT_DATA_ROOT


func is_project_root() -> bool:
	return data_root == DEFAULT_DATA_ROOT


func dialogue_file(locale: String, chapter: String) -> String:
	return "%s/%s/%s/%s.json" % [data_root, DIALOGUE_DIR, locale, chapter]


func inspection_file(locale: String, chapter: String) -> String:
	return "%s/%s/%s/%s.json" % [data_root, INSPECTION_DIR, locale, chapter]


func ability_text_file(locale: String) -> String:
	return "%s/%s/%s.json" % [data_root, ABILITY_DIR, locale]


func ability_structure_file() -> String:
	return "%s/%s/%s" % [data_root, ABILITY_DIR, ABILITY_STRUCTURE_FILE]


func dir_for(kind: String) -> String:
	return "%s/%s" % [data_root, DIALOGUE_DIR if kind == "dialogue" else INSPECTION_DIR]


## Every chapter that exists in *any* language, sorted. Union rather than intersection on
## purpose: a chapter with a missing translation should appear in the list and fail to
## open loudly, not vanish from the tool as if it had never been written.
func chapters_on_disk(kind: String) -> Array[String]:
	var seen: Dictionary = {}
	for locale: String in L10n.LOCALES:
		for stem: String in _json_stems("%s/%s" % [dir_for(kind), locale]):
			seen[stem] = true
	var chapters: Array[String] = []
	for stem: Variant in seen.keys():
		chapters.append(String(stem))
	chapters.sort()
	return chapters


## Chapters a language tree is missing, so an author sees a half-added chapter before the
## runtime does.
func missing_files(kind: String) -> Array[String]:
	var missing: Array[String] = []
	for locale: String in L10n.LOCALES:
		for chapter: String in chapters_on_disk(kind):
			var file := (
				dialogue_file(locale, chapter)
				if kind == "dialogue"
				else inspection_file(locale, chapter)
			)
			if not FileAccess.file_exists(file):
				missing.append(file)
	return missing


## The library constants still name chapters that no file backs, or the tree has chapters
## the constants do not name. Both are worth telling the author about; only the second one
## is a lie the runtime would tell, because `DialogueLibrary.load_all()` iterates the
## constants.
func chapter_warnings(kind: String) -> Array[String]:
	var warnings: Array[String] = []
	if not is_project_root():
		return warnings
	var declared: Array[String] = []
	for name: Variant in (
		DialogueLibraryScript.CHAPTERS if kind == "dialogue" else InspectionLibraryScript.CHAPTERS
	):
		declared.append(String(name))
	declared.sort()
	var on_disk := chapters_on_disk(kind)
	for chapter: String in on_disk:
		if not declared.has(chapter):
			warnings.append(
				"章节 '%s' 在 %s 下有文件，但没有登记在 %s 里，游戏不会加载它。"
				% [chapter, dir_for(kind), "DialogueLibrary.CHAPTERS" if kind == "dialogue" else "InspectionLibrary.CHAPTERS"]
			)
	for chapter: String in declared:
		if not on_disk.has(chapter):
			warnings.append(
				"章节 '%s' 登记在 %s 里，但没有对应的文件（%s）。"
				% [chapter, "DialogueLibrary.CHAPTERS" if kind == "dialogue" else "InspectionLibrary.CHAPTERS", dir_for(kind)]
			)
	return warnings


func _json_stems(directory: String) -> Array[String]:
	var stems: Array[String] = []
	if not DirAccess.dir_exists_absolute(directory):
		return stems
	for name: String in DirAccess.get_files_at(directory):
		if not name.ends_with(".json"):
			continue
		stems.append(name.trim_suffix(".json"))
	stems.sort()
	return stems
