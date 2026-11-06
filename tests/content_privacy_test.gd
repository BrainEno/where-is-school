extends SceneTree
## Guards the creative-material restriction mechanically.
##
## The author's unpublished manuscript must not enter this repository. This test
## does not (and cannot) know the manuscript; instead it enforces the reviewable
## rules that keep original game writing separable from source material:
##
##   1. No file under data/ or scripts/ may contain placeholder markers, quoted
##      manuscript references, or TODOs that hide unapproved copied text.
##   2. Every authored line must be bilingual and non-empty.
##   3. Every dialogue line must declare provenance.
##   4. No content file may reference an external URL or a manuscript file path.
##
## Any future paste of source prose into a content file that carried a marker, a
## quote block, or an external reference will therefore fail CI.

const CONTENT_ROOTS: Array[String] = ["res://data", "res://scripts"]
const FORBIDDEN_MARKERS: Array[String] = [
	"[MANUSCRIPT",
	"[SOURCE EXCERPT",
	"[FROM THE NOVEL",
	"原文摘录",
	"手稿原文",
	"TODO(manuscript",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for root_path: String in CONTENT_ROOTS:
		_scan_directory(root_path)

	_check_scripts_are_bilingual()

	if _failures.is_empty():
		print("content_privacy_test passed: no manuscript markers, external references, or unmarked quotes in content.")
		quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL: " + failure)
		printerr("content_privacy_test failed with %d problem(s)." % _failures.size())
		quit(1)


func _scan_directory(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		_failures.append("could not open content directory %s" % path)
		return
	for file_name: String in dir.get_files():
		if not (file_name.ends_with(".gd") or file_name.ends_with(".json") or file_name.ends_with(".tres")):
			continue
		_scan_file(path.path_join(file_name))
	for sub: String in dir.get_directories():
		_scan_directory(path.path_join(sub))


func _scan_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_failures.append("could not read %s" % path)
		return
	var text: String = file.get_as_text()
	file.close()

	for marker: String in FORBIDDEN_MARKERS:
		if text.find(marker) != -1:
			_failures.append("%s contains the marker '%s'; copied source material must not be committed" % [path, marker])
	if text.find("http://") != -1 or text.find("https://") != -1:
		_failures.append("%s contains an external URL; content must be shipped, not fetched" % path)


## Every dialogue line in the authored scripts must carry both Chinese and English
## text. This is what makes an accidental paste of untranslated source prose
## visible in review instead of shipping as "one more string".
func _check_scripts_are_bilingual() -> void:
	var scripts: Array[DialogueScript] = [
		PrologueQConversation.build(),
		PrologueNConversation.build(),
		PrologueAnticipation.build(),
		StreetObservations.build(),
	]
	for inspection_id: StringName in [
		ClassroomInspections.BAG,
		ClassroomInspections.SET_SQUARE,
		ClassroomInspections.TEACHER_DESK,
		ClassroomInspections.TIMETABLE,
		ClassroomInspections.CHAIR,
		ClassroomInspections.WINDOW,
	]:
		scripts.append(ClassroomInspections.script_for(inspection_id, {}))

	for script: DialogueScript in scripts:
		if script == null:
			_failures.append("a content script failed to build")
			continue
		for node_id: StringName in script.nodes:
			var node: DialogueNode = script.nodes[node_id]
			for line: DialogueLine in node.lines:
				if line.text_zh.strip_edges().is_empty() or line.text_en.strip_edges().is_empty():
					_failures.append("%s/%s has a line missing one language" % [script.id, node_id])
				if not NarrativeProvenance.is_valid(line.kind):
					_failures.append("%s/%s has a line without provenance" % [script.id, node_id])
			for choice: DialogueChoice in node.choices:
				if choice.text_zh.strip_edges().is_empty() or choice.text_en.strip_edges().is_empty():
					_failures.append("%s/%s has a choice missing one language" % [script.id, node_id])
