extends RefCounted
## Shared boundary between the saved opt-in and the optional editor. iOS carries its
## scripts; desktop and Android must be able to boot this code without them.

const BOOTSTRAP_PATH := "res://scripts/story_editor/bootstrap.gd"
const NODE_NAME := &"StoryEditor"
const AUTHOR_APP := ^"Authoring"
const AUTHOR_PROJECT_NAME := "Where Is School - Author"

## The development override for the saved switch (#394, #395). The author workflow is wanted in
## every run of the project, and a preferences file the machine will not accept must never be
## able to hide the tool it is there for, so `--story-editor` (after `--`) or
## `WHERE_IS_SCHOOL_STORY_EDITOR=1` turns the editor on for one run without writing anything.
## Both that override and `development_run()` below are honoured only where this build carries
## the editor's scripts - the same rule as the row in the settings screen - so the desktop and
## Android player exports, which leave them out, cannot be switched on from a command line.
const DEVELOPMENT_ARGUMENT := "--story-editor"
const DEVELOPMENT_ENVIRONMENT := "WHERE_IS_SCHOOL_STORY_EDITOR"


static func scripts_present() -> bool:
	return ResourceLoader.exists(BOOTSTRAP_PATH, "GDScript")


static func available(root: Window) -> bool:
	return not root.has_node(AUTHOR_APP) and scripts_present()


static func development_requested(args: PackedStringArray, environment: String) -> bool:
	return args.has(DEVELOPMENT_ARGUMENT) or environment == "1"


## Whether this run counts as an author's own. `OS.is_debug_build()` is the project's existing
## test for that - the same call `dialogue_controller.gd`, `location_host.gd` and the inspection
## library use to keep a development-only report out of a shipped copy - and the player's builds
## are exported with `--export-release` (`.github/workflows/release.yml`, `tools/export_mobile.py`),
## where that test is false. It is a `static var` because one test file has to speak as both a
## player's copy and an author's run; nothing else assigns it.
static var debug_run: bool = OS.is_debug_build()


## A refused preferences write may still install the editor for this run - and nothing may
## remember it - only here, and only where the build actually carries the editor.
static func development_run() -> bool:
	return debug_run and scripts_present()


## True when this run asked for the editor on its own terms. Read-only by design: the file keeps
## saying whatever it said, so a player's copy is unaffected by how the project was launched.
static func development_override() -> bool:
	return scripts_present() and development_requested(
		OS.get_cmdline_user_args(), OS.get_environment(DEVELOPMENT_ENVIRONMENT)
	)


## Settings calls this deferred, after the autoload/scene change that read the preference.
## The standalone author app already owns its editor and is not affected by this setting.
static func reconcile(root: Window, enabled: bool) -> void:
	var editor := installed(root)
	if not enabled or not available(root):
		if editor != null:
			editor.call("release_overlay")
			editor.queue_free()
			root.remove_child(editor)
		return
	if editor == null:
		var bootstrap := load(BOOTSTRAP_PATH) as GDScript
		if bootstrap == null:
			return
		editor = bootstrap.new() as Node
		editor.name = NODE_NAME
		root.add_child(editor)


static func installed(root: Window) -> Node:
	return root.get_node_or_null(NodePath(NODE_NAME))


## The live editor is never a mid-run switch. Staging sets a new project identity
## before Godot opens user://, so progress, read log and drafts are isolated from boot.
static func isolated_author(root: Window) -> Node:
	if ProjectSettings.get_setting("application/config/name") != AUTHOR_PROJECT_NAME \
			or bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)):
		return null
	return root.get_node_or_null(AUTHOR_APP)


static func for_pause(root: Window) -> Node:
	var author := isolated_author(root)
	return author if author != null else installed(root)


static func is_editing(root: Window) -> bool:
	var editor := installed(root)
	if editor == null:
		editor = root.get_node_or_null(AUTHOR_APP)
	return editor != null and bool(editor.call("is_editing"))
