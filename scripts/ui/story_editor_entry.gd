extends RefCounted
## Shared boundary between the saved opt-in and the optional editor. iOS carries its
## scripts; desktop and Android must be able to boot this code without them.

const BOOTSTRAP_PATH := "res://scripts/story_editor/bootstrap.gd"
const NODE_NAME := &"StoryEditor"
const AUTHOR_APP := ^"Authoring"
const AUTHOR_PROJECT_NAME := "Where Is School - Author"


static func available(root: Window) -> bool:
	return not root.has_node(AUTHOR_APP) and ResourceLoader.exists(BOOTSTRAP_PATH, "GDScript")


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
