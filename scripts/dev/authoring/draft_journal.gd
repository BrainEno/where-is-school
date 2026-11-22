extends RefCounted
## Two checked slots. A torn write to the older slot cannot erase the last good draft.
## Not a save slot and not part of the normal game session/reset path.

const Patch := preload("res://scripts/dev/authoring/dialogue_patch.gd")
const DIRECTORY := "user://authoring"

var _directory: String
var _sequence := 0
var _digest := ""
var problem := ""


func _init(directory: String = DIRECTORY) -> void:
	_directory = directory


func recover() -> Dictionary:
	_sequence = 0
	_digest = ""
	problem = ""
	var latest: Dictionary = {}
	var existed := false
	for index in 2:
		var path := _slot(index)
		existed = existed or FileAccess.file_exists(path)
		var wrapper := Patch.read_json(path)
		var generation: Variant = wrapper.get("generation")
		var body: Variant = wrapper.get("body")
		if not (generation is float or generation is int) or not is_finite(float(generation)) \
				or generation != int(generation) or generation <= _sequence or generation > 2_000_000_000 \
				or not body is String or body.sha256_text() != wrapper.get("sha256"):
			continue
		var value: Variant = JSON.parse_string(body)
		if not value is Dictionary or not value.get("draft") is Dictionary:
			continue
		_sequence = int(generation)
		_digest = wrapper["sha256"]
		latest = value
	if existed and latest.is_empty():
		problem = "两个草稿文件都无法校验。未覆盖原文件。"
	return latest


func save(payload: Dictionary) -> bool:
	if not problem.is_empty():
		return false
	var body := JSON.stringify(payload, "", true, true)
	var digest := body.sha256_text()
	if _digest == digest:
		return true
	var next := _sequence + 1
	var wrapped := JSON.stringify({"generation": next, "body": body, "sha256": digest})
	if write_checked(_slot(next % 2), wrapped) != OK:
		return false
	_sequence = next
	_digest = digest
	return true


func _slot(index: int) -> String:
	return _directory.path_join("draft-%d.json" % index)


## Used for the journal and exported files. Temp and destination are on the same volume.
static func write_checked(path: String, content: String) -> Error:
	var bytes := content.to_utf8_buffer()
	if bytes.size() > Patch.MAX_BYTES:
		return ERR_INVALID_PARAMETER
	var absolute := ProjectSettings.globalize_path(path)
	var result := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result != OK:
		return result
	var temporary := absolute + "." + Patch.new_id() + ".writing"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var wrote := file.store_buffer(bytes)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if not wrote or write_error != OK or FileAccess.get_file_as_bytes(temporary) != bytes:
		DirAccess.remove_absolute(temporary)
		return ERR_FILE_CANT_WRITE
	result = DirAccess.rename_absolute(temporary, absolute)
	if result != OK:
		DirAccess.remove_absolute(temporary)
	return result
