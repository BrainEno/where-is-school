extends Node
## Explicit handoff to the desktop save dialog or the iOS author-only UIKit bridge.
## The bridge can see only these request/result files, not drafts, settings or saves.

const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const Journal := preload("res://scripts/story_editor/draft_journal.gd")
const NativeChapter := preload("res://scripts/story_editor/native_chapter.gd")
const INBOX := "user://story_editor/share/request.json"
const RECEIPT := "user://story_editor/share/result.json"
const FILE_NAME := "where-is-school-dialogue-draft.json"

signal exported(digest: String, note: String)
signal edited(field: String, text: String)
signal notice(text: String)

var _token := ""
var _kind := ""
var _field := ""
var _draft := ""
var _chapter_files := {}
var _deadline := 0
var _file_dialog: FileDialog


func _ready() -> void:
	set_process(false)


func is_busy() -> bool:
	return not _kind.is_empty()


func export_draft(draft: String) -> void:
	if is_busy():
		return
	_kind = "export"
	_draft = draft
	if OS.has_feature("ios"):
		_request({"text": draft})
		return
	_choose_path(FILE_NAME, "导出剧情草稿", "*.json", "剧情草稿 JSON")


func export_chapter(chapter: String, files: Dictionary) -> void:
	if is_busy() or files.is_empty():
		return
	_kind = "chapter"
	_chapter_files = files
	if OS.has_feature("ios"):
		# Same path-free UTF-8 request protocol: the bridge receives only this ZIP's
		# bytes, not the ability to select paths in the project or the save directory.
		var temporary := INBOX.get_base_dir().path_join(Patch.new_id() + ".zip")
		if NativeChapter.write_archive(temporary, files) != OK:
			_finish(false, "未能生成章节候选包，草稿仍保留。")
			return
		_draft = Marshalls.raw_to_base64(FileAccess.get_file_as_bytes(temporary))
		DirAccess.remove_absolute(temporary)
		_request({"text": _draft})
		return
	_choose_path(chapter + "-chapter.zip", "导出整章候选包", "*.zip", "双语章节候选 ZIP")


func _choose_path(filename: String, caption: String, pattern: String, description: String) -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.file_selected.connect(write_to)
		_file_dialog.canceled.connect(func() -> void: _finish(false, "已取消导出。"))
		add_child(_file_dialog)
	_file_dialog.title = caption
	_file_dialog.clear_filters()
	_file_dialog.add_filter(pattern, description)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_file_dialog.current_file = filename.get_basename() + "-" + stamp + "." + filename.get_extension()
	_file_dialog.popup_centered_ratio(0.58)


func edit_field(field: String, text: String, caption: String) -> void:
	if is_busy() or not OS.has_feature("ios"):
		return
	_kind = "edit"
	_field = field
	_request({"text": text, "caption": caption})


func _request(data: Dictionary) -> void:
	_token = Patch.new_id()
	data["id"] = _token
	data["kind"] = _kind
	if Journal.write_checked(INBOX, JSON.stringify(data)) != OK:
		_finish(false, "无法准备文件，草稿仍保留。")
		return
	_deadline = Time.get_ticks_msec() + 12_000
	set_process(true)


## FileDialog normally returns an OS path, including for project files.
static func is_export_destination(path: String, extension: String = "json") -> bool:
	if not path.is_absolute_path() or path.begins_with("res://") or path.get_extension().to_lower() != extension:
		return false
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	if OS.has_feature("windows") or OS.has_feature("macos"):
		absolute = absolute.to_lower()
		project = project.to_lower()
	return not absolute.begins_with(project + "/")


func write_to(path: String) -> void:
	if not _is_export():
		return
	var chapter := _kind == "chapter"
	var extension := "zip" if chapter else "json"
	if not is_export_destination(path, extension):
		_finish(false, "请选择项目之外的 .%s 文件。" % extension)
		return
	if FileAccess.file_exists(path):
		_finish(false, "为防止覆盖，请使用一个新的文件名。")
		return
	var result := NativeChapter.write_archive(path, _chapter_files) if chapter else Journal.write_checked(path, _draft)
	_finish(result == OK, ("双语整章候选包已导出。" if chapter else "JSON 已导出。")
		if result == OK else "保存文件失败，草稿仍保留。")


func _is_export() -> bool:
	return _kind in ["export", "chapter"]


func _process(_delta: float) -> void:
	var receipt := Patch.read_json(RECEIPT)
	if receipt.get("id") == _token:
		match receipt.get("state"):
			"presented": _deadline = 0
			"exported": _finish(_is_export(), "已保存到「文件」。")
			"edited":
				var text: Variant = receipt.get("text")
				var field := _field
				if _kind == "edit" and text is String and text.length() <= Patch.MAX_FIELD_CHARS:
					_finish(false, "")
					edited.emit(field, text)
				else:
					_finish(false, "文本过长，未替换当前字段。")
			"cancelled": _finish(false, "已取消。")
			"error": _finish(false, "无法打开 iOS 编辑或文件窗口，草稿仍保留。")
	if _deadline > 0 and Time.get_ticks_msec() > _deadline:
		DirAccess.remove_absolute(INBOX)
		_finish(false, "未收到 iOS 组件回应，请检查作者版构建。")


func _finish(ok: bool, note: String) -> void:
	var digest := ""
	if ok:
		digest = Patch.digest(_chapter_files) if _kind == "chapter" else _draft.sha256_text()
	var was_export := _is_export()
	set_process(false)
	if not _token.is_empty():
		DirAccess.remove_absolute(RECEIPT)
	_token = ""
	_kind = ""
	_field = ""
	_draft = ""
	_chapter_files = {}
	_deadline = 0
	if was_export:
		exported.emit(digest, note)
	elif not note.is_empty():
		notice.emit(note)
