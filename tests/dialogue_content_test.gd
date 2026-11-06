extends SceneTree
## Content validation for every dialogue and character resource in data/.
## Runs the project's own resource-side validation; no fake fixtures.

const KNOWN_SPEAKERS: PackedStringArray = ["q", "n", "narrator", "inner", "imagination"]
const REQUIRED_CONVERSATIONS: PackedStringArray = [
	"wake_intro", "q_intro", "q_free_talk", "bag_search", "set_square",
	"n_arrival", "bell_gap", "imagination_b", "door_locked", "gate_end",
]

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	var dialogue_dir := DirAccess.open("res://data/dialogue")
	if dialogue_dir == null:
		push_error("dialogue_content_test failed: res://data/dialogue not readable")
		quit(1)
		return

	var seen: Dictionary = {}
	var file_names: Array[String] = dialogue_dir.get_files()
	file_names.sort()
	for file_name in file_names:
		if not file_name.ends_with(".tres"):
			continue
		var path: String = "res://data/dialogue/" + file_name
		var conversation: Resource = load(path)
		if conversation == null:
			failures.append("%s: failed to load as a Resource" % path)
			continue
		var errors: PackedStringArray = conversation.validate()
		for error in errors:
			failures.append("%s: %s" % [path, error])
		seen[conversation.id] = true
		for entry in conversation.entries:
			if entry == null:
				continue
			if not KNOWN_SPEAKERS.has(String(entry.speaker_id)):
				failures.append("%s: entry '%s' references unknown speaker '%s'" % [path, entry.id, entry.speaker_id])

	for required in REQUIRED_CONVERSATIONS:
		if not seen.has(required):
			failures.append("required conversation '%s' not found in data/dialogue" % required)

	var character_dir := DirAccess.open("res://data/characters")
	if character_dir == null:
		failures.append("res://data/characters not readable")
	else:
		for speaker in KNOWN_SPEAKERS:
			var char_path: String = "res://data/characters/%s.tres" % speaker
			var def: Resource = load(char_path)
			if def == null:
				failures.append("character definition missing or invalid: %s" % char_path)

	if not failures.is_empty():
		for failure in failures:
			push_error("dialogue_content_test failed: %s" % failure)
		quit(1)
		return
	print("dialogue_content_test passed (%d conversations validated)" % seen.size())
	quit(0)
