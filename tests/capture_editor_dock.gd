extends SceneTree
## Captures the narrative editor dock from a real window, so the pull request can show the
## tool instead of describing it.
##
## The dock is an EditorPlugin panel and normally lives inside the Godot editor; this
## script instantiates the same Control — the same class, the same store, the same content
## from `res://data` — in a plain window and photographs it. What is missing from the
## frame is the editor's own chrome around the panel (the bottom-panel tab and the
## surrounding UI), not the panel itself: every control in the shot is real and driven by
## the real data layer.
##
## It photographs four states: a dialogue node with choices, an inspection, an inner-voice
## entry, and the same dialogue node with an unsaved edit so the dirty indicator and the
## enabled Save button are visible. Nothing is saved: `save()` is never called, so
## `res://data/` is only ever read.
##
## Run it with a display (Xvfb in CI):
##
##   xvfb-run -a --server-args="-screen 0 1920x1080x24" \
##     godot --path . --resolution 1600x1000 --rendering-driver opengl3 \
##     --script res://tests/capture_editor_dock.gd
##
## Frames land in `docs/screenshots/editor-dock-*.png`, next to the playthrough's.

const Harness = preload("res://tests/test_harness.gd")
const Dock = preload("res://addons/narrative_editor/ui/narrative_editor_dock.gd")

const OUT_DIR := "res://docs/screenshots"
const LOG_PATH := "res://docs/screenshots/EDITOR_CAPTURE.log"
const SIZE := Vector2i(1600, 1000)

var _failures: Array[String] = []
var _shots: Array[String] = []
## Typed as the dock script, not as `Control`: the engine resolves `_dock.store`,
## `_dock.show_kind()` and the rest against the declared type, so a `Control` here makes
## the whole script fail to compile — which is what the first CI run did, one second in.
var _dock: Dock = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "capture_editor_dock.gd")
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_dock = Dock.new()
	root.add_child(_dock)
	if _dock.store == null:
		_finish(["The dock did not build a store; nothing below could be photographed."])
		return
	_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _resize(SIZE)
	print(
		"DIAG kind=%s chapter=%s locales=%s errors=%s"
		% [
			_dock.store.kind,
			_dock.store.chapter,
			str(_dock.store.locales),
			_dock.store.describe_errors(),
		]
	)

	# --- the dialogue panel, on the node that has choices ---------------------
	var dialogue_chapter := _first_chapter("dialogue")
	var conversation := _first_conversation(dialogue_chapter)
	if conversation.is_empty():
		_finish(["No conversation could be loaded for the dialogue frame."])
		return
	var node_index := _first_node_with_choices(conversation)
	_dock.show_kind("dialogue", dialogue_chapter)
	await _frames(3)
	_dock.show_entry(conversation, node_index)
	await _frames(4)
	await _shot("editor-dock-dialogue-1600x1000.png")

	# --- an inspection --------------------------------------------------------
	_dock.show_kind("inspections", _first_chapter("inspections"))
	await _frames(4)
	await _shot("editor-dock-inspection-1600x1000.png")

	# --- the inner-voice text -------------------------------------------------
	_dock.show_kind("abilities")
	await _frames(4)
	await _shot("editor-dock-abilities-1600x1000.png")

	# --- the same node, edited but not saved ----------------------------------
	_dock.show_kind("dialogue", dialogue_chapter)
	await _frames(3)
	_dock.show_entry(conversation, node_index)
	await _frames(3)
	_edit_without_saving()
	_dock.refresh()
	await _frames(4)
	await _shot("editor-dock-unsaved-1600x1000.png")

	_finish(_failures)


# --- helpers -----------------------------------------------------------------


## Types into the Chinese body without touching the disk: the store keeps the edit in
## memory, and `save()` is deliberately never called from this script.
func _edit_without_saving() -> void:
	var store = _dock.store
	var conversation := _first_conversation(_first_chapter("dialogue"))
	var model := store.node_model(conversation, _first_node_with_choices(conversation))
	var fields: Array = model.get("fields", [])
	var target: Dictionary = {}
	for field: Dictionary in fields:
		if String(field.get("field_id", "")) == "text":
			target = field
			break
	if target.is_empty():
		_failures.append("The frame could not be given an unsaved edit: no text field.")
		return
	var original := String((target["values"] as Dictionary).get("zh-CN", ""))
	if not store.set_field(target, "zh-CN", original + "（截图用：这一处还没保存）"):
		_failures.append("The unsaved edit could not be written into the store.")


func _first_chapter(kind: String) -> String:
	var chapters: Array = _dock.store.available_chapters(kind)
	if chapters.is_empty():
		_failures.append(
			"No %s chapter was found on disk. Store errors: %s"
			% [kind, _dock.store.describe_errors()]
		)
		return ""
	return String(chapters[0])


func _first_conversation(chapter: String) -> String:
	if chapter.is_empty():
		return ""
	_dock.store.open("dialogue", chapter)
	var ids: Array = _dock.store.list_ids()
	if ids.is_empty():
		_failures.append(
			"Chapter %s has no conversations. Store errors: %s"
			% [chapter, _dock.store.describe_errors()]
		)
		return ""
	return String(ids[0])


func _first_node_with_choices(conversation: String) -> int:
	if conversation.is_empty():
		return 0
	for entry: Dictionary in _dock.store.node_entries(conversation):
		if bool(entry.get("has_choices", false)):
			return int(entry["index"])
	return 0


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	if _dock != null:
		_dock.size = Vector2(size)
	await _frames(6)


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _shot(name: String) -> void:
	var path := "%s/%s" % [OUT_DIR, name]
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append("%s came back empty." % name)
		return
	var error := image.save_png(path)
	if error != OK:
		_failures.append("Could not write %s (error %d)." % [path, error])
		return
	_shots.append(name)
	print(
		"SHOT %s  %dx%d  dirty=%s  files=%s"
		% [
			name,
			image.get_width(),
			image.get_height(),
			str(_dock.store.is_dirty()),
			str(_dock.store.file_paths()),
		]
	)
	if image.get_width() != SIZE.x or image.get_height() != SIZE.y:
		_failures.append(
			"%s is %dx%d, not %dx%d."
			% [name, image.get_width(), image.get_height(), SIZE.x, SIZE.y]
		)


func _finish(failures: Array) -> void:
	var log := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if log != null:
		for name: String in _shots:
			log.store_line("SHOT: %s" % name)
		for failure: String in failures:
			log.store_line("FAILURE: %s" % failure)
		if failures.is_empty():
			log.store_line(
				"RESULT: %d editor frames captured; unsaved edits left in the store: %s."
				% [_shots.size(), str(_dock.store.is_dirty())]
			)
		log.close()
	if failures.is_empty():
		print("PASS: captured %d editor frames." % _shots.size())
		quit(0)
		return
	for failure: Variant in failures:
		print("FAILURE: %s" % String(failure))
	quit(1)
