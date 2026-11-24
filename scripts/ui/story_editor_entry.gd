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


## The author's key for the editor (#396). The row in the pause menu sits behind a preferences
## file a machine may refuse to write, and behind two menus, so `Session` watches for this key
## and calls `toggle()` from anywhere in the run. It is a raw key rather than an action in
## `project.godot`'s `[input]` on purpose: that list is the player's control scheme, the author can
## rebind it, and it ships inside a player's copy, where there is nothing for the key to do.
const HOTKEY := KEY_F9
const SETTINGS_NODE := ^"Settings"
const SETTINGS_MISSING := "the settings autoload is not running"


## Whether `event` is the hotkey. Only a fresh press counts, with nothing held: holding the key
## down must not flip the mode back and forth, and a modified F9 stays somebody else's chord.
static func hotkey_pressed(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.keycode == HOTKEY and not key.ctrl_pressed and not key.alt_pressed \
		and not key.shift_pressed and not key.meta_pressed


## Whether this run may answer the key at all. `development_run()` keeps a released export out -
## the iOS one ships `scripts/story_editor/`, where a key a player can press must not be a way in
## - and `development_override()` lets an author's own release export use it after being launched
## as an author's run, which is the same terms the saved switch is honoured on.
static func hotkey_allowed(root: Window) -> bool:
	if not available(root):
		return false
	return development_run() or development_override()


## Open the editor, or put it away, and say what the file did. `{changed, enabled, saved, step}`:
## `saved` is whether the preference accepted the change and `step` names what refused when it did
## not, which is how the settings row tells 「已保存」 from 「只在这次」 from 「开关未更改」. Both
## directions go through `Settings.set_story_editor_enabled()` - the one place that decides who may
## turn this on - so the key cannot install a tool the build does not carry, and cannot store a
## choice a player's copy was refused.
static func toggle(root: Window) -> Dictionary:
	var report := {"changed": false, "enabled": false, "saved": false, "step": ""}
	if root == null or not hotkey_allowed(root):
		return report
	var settings := root.get_node_or_null(SETTINGS_NODE)
	if settings == null or not settings.has_method("set_story_editor_enabled"):
		report["step"] = SETTINGS_MISSING
		return report
	var was_on := _is_on(settings)
	var saved := bool(settings.call("set_story_editor_enabled", not was_on))
	var is_on := _is_on(settings)
	report["changed"] = is_on != was_on
	report["enabled"] = is_on
	report["saved"] = saved
	if not saved:
		report["step"] = _refusal_step(settings)
	return report


## The one line a host needs: the always-alive owner of "which screen the game is on" forwards its
## `_shortcut_input` here, so the key's rules and the tool they open stay in the file that already
## holds the saved switch. A run that may not answer the key changes nothing and claims nothing -
## no state, no taken press - which is what keeps this shared code inert inside a player's package.
## The note goes to the console because `Diagnostics` writes its own files and is not an engine
## logger, and the engine keeps what a run refused in the editor console alone.
static func handle_shortcut_input(host: Node, event: InputEvent) -> void:
	if not hotkey_pressed(event) or not host.is_inside_tree():
		return
	var report: Dictionary = toggle(host.get_tree().root)
	if not bool(report["changed"]):
		if not String(report["step"]).is_empty():
			push_warning("StoryEditor: F9 could not store the switch (%s)" % String(report["step"]))
		return
	host.get_viewport().set_input_as_handled()
	print("StoryEditor: F9 %s the story editor - %s" % [
		"opened" if bool(report["enabled"]) else "closed",
		"the preference file took it" if bool(report["saved"])
		else "this run only (%s)" % String(report["step"]),
	])


static func _is_on(settings: Node) -> bool:
	return settings.has_method("is_story_editor_enabled") \
		and bool(settings.call("is_story_editor_enabled"))


## The step `Settings` refused its last write over, or "" when it has none to report. Read through
## a lookup, so a stand-in settings node in a test keeps working.
static func _refusal_step(settings: Node) -> String:
	if not settings.has_method("get_last_store_failure"):
		return ""
	var failure: Variant = settings.call("get_last_store_failure")
	if not (failure is Dictionary):
		return ""
	return str((failure as Dictionary).get("step", ""))


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
