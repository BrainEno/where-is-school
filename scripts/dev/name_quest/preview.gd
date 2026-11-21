extends Node
## Standalone F6 entry. The production world is instanced, not edited; all disk
## calls made by its save manager go to the preview's own directory.

const WORLD := preload("res://scenes/main/main.tscn")
const DIRECTOR := preload("res://scripts/dev/name_quest/opening.gd")
const CARD_PATH := "res://scenes/dev/name_quest/cards.zh-CN.json"
const SOURCE_FONT := "res://art/fonts/NotoSansSC-Regular.ttf"
const SAVE_DIR := "user://name_quest_preview"
const RESET_OPTION := "--name-quest-reset"


class PreviewFiles:
	var directory: String
	var _disk := SaveFileStore.FileIO.new()

	func _init(path: String) -> void:
		directory = path

	func _local(path: String) -> String:
		return directory.path_join(path.get_file())

	func exists(path: String) -> bool:
		return _disk.exists(_local(path))

	func read_bytes(path: String) -> PackedByteArray:
		return _disk.read_bytes(_local(path))

	func write_bytes(path: String, data: PackedByteArray) -> int:
		return _disk.write_bytes(_local(path), data)

	func rename(from: String, to: String) -> int:
		return DirAccess.rename_absolute(_local(from), _local(to))

	func remove(path: String) -> int:
		return DirAccess.remove_absolute(_local(path))

	func list() -> PackedStringArray:
		return DirAccess.get_files_at(directory)


var _save: Node
var _previous_io: Variant
var _previous_log: ReadLog
var _previously_suspended := false


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CARD_PATH))
	if not data is Dictionary:
		push_error("Name quest preview: cannot read %s." % CARD_PATH)
		return
	var font := FontFile.new()
	if font.load_dynamic_font(ProjectSettings.globalize_path(SOURCE_FONT)) != OK:
		push_error("Name quest preview: cannot load the source font for preview-only glyphs.")
		return
	if DirAccess.make_dir_recursive_absolute(SAVE_DIR) != OK:
		push_error("Name quest preview: cannot create %s." % SAVE_DIR)
		return

	_save = get_node(^"/root/Save")
	_previous_io = _save.io
	_previously_suspended = _save.writes_suspended()
	_save.io = PreviewFiles.new(SAVE_DIR)
	_save.suspend_writes(false)
	if RESET_OPTION in OS.get_cmdline_user_args():
		_save.forget_all()
	# The pause settings panel reads the shared log in _ready even when its
	# button is hidden. Install the isolated log before any child enters the tree.
	_previous_log = ReadLog._shared
	var read_log := ReadLog.new(SAVE_DIR.path_join("read_log.json"))
	read_log.load_file()
	ReadLog.use_shared(read_log)

	# Start before the actual dismissal conversation, without replaying the earlier
	# lessons. On Continue, OpeningSave replaces this seed with the disk snapshot.
	get_node(^"/root/GameState").replace_snapshot({
		StoryFlags.BELL_RUNG: true,
		StoryFlags.N_ARRIVED: true,
	})
	get_node(^"/root/NarrativeState").clear()
	var world := WORLD.instantiate()
	var opening := world.get_node(^"OpeningSequence")
	opening.set_script(DIRECTOR)
	var director := opening as DIRECTOR
	director.autostart = false
	director.cards = data
	director.progress = $PreviewHUD/Progress
	director.preview_font = font
	world.get_node(^"InnerVoiceDirector").set_process(false)
	add_child(world)
	var pause := world.get_node(^"PauseMenu") as PauseMenu
	# No production session commands, including settings' shared read-log reset.
	for entry: StringName in [&"new_game", &"save_quit", &"settings"]:
		pause.get_entry(entry).hide()


func _exit_tree() -> void:
	if is_instance_valid(_save):
		ReadLog.use_shared(_previous_log)
		_save.unbind_world()
		_save.io = _previous_io
		_save.suspend_writes(_previously_suspended)
