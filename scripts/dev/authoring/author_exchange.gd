extends Node
## Explicit handoff to the desktop save dialog or the iOS author-only UIKit bridge.
## The bridge can see only these request/result files, not drafts, settings or saves.

const Patch := preload("res://scripts/dev/authoring/dialogue_patch.gd")
const Journal := preload("res://scripts/dev/authoring/draft_journal.gd")
const INBOX := "user://authoring/share/request.json"
const RECEIPT := "user://authoring/share/result.json"
const FILE_NAME := "where-is-school-dialogue-draft.json"

signal exported(digest: String, note: String)
signal edited(field: String, text: String)
signal notice(text: String)

var _token := ""
var _kind := ""
var _field := ""
var _draft := ""
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
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.title = "导出剧情草稿"
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.add_filter("*.json", "剧情草稿 JSON")
		_file_dialog.file_selected.connect(write_to)
		_file_dialog.canceled.connect(func() -> void: _finish(false, "已取消导出。"))
		add_child(_file_dialog)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	_file_dialog.current_file = FILE_NAME.replace(".json", "-" + stamp + ".json")
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
static func is_export_destination(path: String) -> bool:
	if not path.is_absolute_path() or path.begins_with("res://") or path.get_extension().to_lower() != "json":
		return false
	var absolute := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	var project := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	if OS.has_feature("windows") or OS.has_feature("macos"):
		absolute = absolute.to_lower()
		project = project.to_lower()
	return not absolute.begins_with(project + "/")


func write_to(path: String) -> void:
	if _kind != "export":
		return
	if not is_export_destination(path):
		_finish(false, "请选择项目之外的 .json 文件。")
		return
	if FileAccess.file_exists(path):
		_finish(false, "为防止覆盖，请使用一个新的文件名。")
		return
	var ok := Journal.write_checked(path, _draft) == OK
	_finish(ok, "JSON 已导出。" if ok else "保存文件失败，草稿仍保留。")


func _process(_delta: float) -> void:
	var receipt := Patch.read_json(RECEIPT)
	if receipt.get("id") == _token:
		match receipt.get("state"):
			"presented": _deadline = 0
			"exported": _finish(_kind == "export", "JSON 已保存到「文件」。")
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
	var digest := _draft.sha256_text() if ok else ""
	var was_export := _kind == "export"
	set_process(false)
	if not _token.is_empty():
		DirAccess.remove_absolute(RECEIPT)
	_token = ""
	_kind = ""
	_field = ""
	_draft = ""
	_deadline = 0
	if was_export:
		exported.emit(digest, note)
	elif not note.is_empty():
		notice.emit(note)
