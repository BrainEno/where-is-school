extends SceneTree
## What a save file must refuse, and what it must never quietly accept.
##
## The audit (#60) found the one thing worse than having no save system: a restore
## path that took whatever it was given. An unknown knowledge source was downgraded
## to `observed`, an empty flag table looked like a fresh run, and nothing compared a
## version number. These checks pin down the opposite: every refusal names its reason,
## a refused file changes nothing, and the one thing that *is* allowed to degrade - a
## single untrustworthy knowledge entry - is reported instead of hidden.
##
## No scene is loaded here; this is the file and the two state nodes, which is why it
## runs in a second and is the first place to look when a save stops loading.

const Harness = preload("res://tests/test_harness.gd")
const SAVE_PATH := "user://save.json"
const BROKEN_PATH := "user://save.broken.json"

var _failures: Array[String] = []

var _game_state: Node = null
var _narrative: Node = null
var _save: Node = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "save_validation_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	_game_state = autoloads["game_state"]
	_narrative = autoloads["narrative_state"]
	_save = autoloads["save"]
	if _game_state == null or _narrative == null or _save == null:
		Harness.finish(self, ["The state or save autoload could not be created."], "")
		return
	Harness.clear_session_state(self)

	Harness.stage = "value encoding"
	_expect_value_round_trip()
	_expect_unknown_tag_refused()

	Harness.stage = "envelope"
	_expect_envelope_refusals()

	Harness.stage = "payload"
	_expect_payload_refusals()

	Harness.stage = "knowledge"
	_expect_knowledge_rules()

	Harness.stage = "determinism"
	_expect_seed_round_trip()

	Harness.stage = "housekeeping"
	_save.delete_save()
	_expect(not _save.has_save(), "delete_save() left the file behind.")

	Harness.finish(
		self, _failures, "a save file refuses what it cannot trust and says why."
	)


# --- Values -----------------------------------------------------------------


func _expect_value_round_trip() -> void:
	var flags: Dictionary = {
		"flag_bool": true,
		"flag_int": 3,
		"flag_float": 1.25,
		"flag_string": "text",
		"flag_string_name": &"corridor",
		"flag_array": [1, "two", false],
		"flag_dictionary":
		{
			"die": 7,
			"total": 9,
			"success": true,
			"margin": -2.5,
			"nested": {"deep": [&"a", 2]},
		},
	}
	# Through the disk and back: encode, stringify the way the file does, parse, decode.
	var on_disk: Variant = JSON.parse_string(JSON.stringify(SaveCodec.encode_flags(flags)))
	var decoded := SaveCodec.decode_flags(on_disk)
	_expect(decoded["ok"] == true, "A table this codec wrote was refused on the way back.")
	if decoded["ok"] != true:
		return
	var restored: Dictionary = decoded["flags"]
	for key: Variant in flags.keys():
		_expect(restored.has(key), "The key '%s' did not survive the round trip." % key)
		if not restored.has(key):
			continue
		_expect(
			typeof(restored[key]) == typeof(flags[key]),
			"The value of '%s' changed type: %d -> %d."
			% [key, typeof(flags[key]), typeof(restored[key])]
		)
		_expect(restored[key] == flags[key], "The value of '%s' changed." % key)
	# JSON would have turned the integer into a float; that is the whole point.
	_expect(
		typeof(restored.get("flag_int")) == TYPE_INT,
		"An integer flag came back as something other than an int."
	)
	var record: Dictionary = restored.get("flag_dictionary", {})
	_expect(
		typeof(record.get("die")) == TYPE_INT and int(record.get("die")) == 7,
		"A nested integer inside a check record was not preserved."
	)


func _expect_unknown_tag_refused() -> void:
	var decoded := SaveCodec.decode_flags({"mystery": {"t": "z", "v": 1}})
	_expect(decoded["ok"] != true, "An unknown type tag was accepted.")
	_expect(
		String(decoded["detail"]).contains("flags.mystery"),
		"The refusal does not name the path it was found at: %s" % String(decoded["detail"])
	)
	var untagged := SaveCodec.decode_flags({"mystery": 1})
	_expect(untagged["ok"] != true, "A bare number was accepted as a flagged value.")


# --- Envelope ---------------------------------------------------------------


func _expect_envelope_refusals() -> void:
	_expect(SaveCodec.unwrap("")["reason"] == "not_json", "An empty file was not refused.")
	_expect(
		SaveCodec.unwrap("{ this is not json")["reason"] == "not_json",
		"Broken JSON was not refused as such."
	)
	_expect(
		SaveCodec.unwrap("[1, 2, 3]")["reason"] == "not_json",
		"A JSON array was accepted as an envelope."
	)

	var foreign := SaveCodec.unwrap(
		JSON.stringify({"format": "someone-else/save", "version": 1, "payload": {}})
	)
	_expect(foreign["reason"] == "format", "A file from another writer was not refused.")

	var newer := SaveCodec.unwrap(
		JSON.stringify({"format": SaveCodec.FORMAT, "version": SaveCodec.VERSION + 1, "payload": {}})
	)
	_expect(newer["reason"] == "version", "A newer file version was accepted.")
	_expect(
		String(newer["detail"]).contains("newer build"),
		"A newer version is not explained in words the player can act on."
	)

	var ancient := SaveCodec.unwrap(
		JSON.stringify({"format": SaveCodec.FORMAT, "version": 0, "payload": {}})
	)
	_expect(ancient["reason"] == "version", "Version 0 was accepted.")

	var no_payload := SaveCodec.unwrap(
		JSON.stringify({"format": SaveCodec.FORMAT, "version": 1})
	)
	_expect(no_payload["ok"] != true, "An envelope without a payload was accepted.")

	var good := SaveCodec.unwrap(SaveCodec.wrap({"flags": {}}, 0))
	_expect(good["ok"] == true, "A file this codec wrote was refused.")


# --- Payload ----------------------------------------------------------------


func _expect_payload_refusals() -> void:
	Harness.clear_session_state(self)
	_game_state.set_flag(&"kept_across_a_refusal", 1)

	# A payload whose flag table is not a table.
	_write_raw(
		JSON.stringify(
			{"format": SaveCodec.FORMAT, "version": 1, "payload": {"flags": "nope"}}
		)
	)
	# Typed explicitly: `_save` is a Node, so a call on it has no static type to infer.
	var read: Dictionary = _save.read_save()
	_expect(read["ok"] != true, "A payload with a non-object flag table was accepted.")
	_expect(String(read["reason"]) == "payload", "The refusal does not blame the payload: %s" % String(read["reason"]))

	# A payload with one unknown value type refuses the whole file, not just the flag.
	_write_raw(
		JSON.stringify(
			{
				"format": SaveCodec.FORMAT,
				"version": 1,
				"payload": {"flags": {"fine": {"t": "i", "v": 1}, "bad": {"t": "z"}}}
			}
		)
	)
	var typed: Dictionary = _save.read_save()
	_expect(typed["ok"] != true, "A file with an unknown value type was accepted.")
	_expect(
		String(typed["detail"]).contains("flags.bad"),
		"The payload refusal does not name the flag: %s" % String(typed["detail"])
	)

	# Loading that file must apply nothing at all.
	var loaded: Dictionary = _save.load_game()
	_expect(loaded["ok"] != true, "load_game accepted a file read_save refused.")
	_expect(
		int(_game_state.get_flag(&"fine", 0)) == 0,
		"load_game applied a flag from a payload it refused."
	)
	_expect(
		int(_game_state.get_flag(&"kept_across_a_refusal", 0)) == 1,
		"A refused load changed the session."
	)

	# The refused file is copied, never destroyed.
	_expect(
		FileAccess.file_exists(BROKEN_PATH),
		"The unreadable save was not kept as %s." % BROKEN_PATH
	)
	_expect(
		FileAccess.file_exists(SAVE_PATH),
		"The unreadable save was deleted from its own path."
	)

	# A world block that cannot be placed anywhere is a payload error too.
	_write_raw(
		JSON.stringify(
			{
				"format": SaveCodec.FORMAT,
				"version": 1,
				"payload": {"flags": {}, "entries": [], "world": {"location_id": ""}}
			}
		)
	)
	_expect(_save.read_save()["ok"] != true, "A world block with no location id was accepted.")

	_write_raw(
		JSON.stringify(
			{
				"format": SaveCodec.FORMAT,
				"version": 1,
				"payload":
				{
					"flags": {},
					"entries": [],
					"world":
					{"location_id": "corridor", "spawn": "FromClassroom", "position": [1, 2]},
				}
			}
		)
	)
	_expect(_save.read_save()["ok"] != true, "A three-element point of two numbers was accepted.")


# --- Knowledge --------------------------------------------------------------


func _expect_knowledge_rules() -> void:
	Harness.clear_session_state(self)
	var restored_signal: Array[int] = []
	var handler := func(count: int) -> void:
		restored_signal.append(count)
	_narrative.entries_restored.connect(handler)

	var result: Dictionary = _narrative.restore_snapshot(
		{
			"entries":
			[
				{"entry_id": "a", "source": "observed", "speaker_id": "q", "text": "A."},
				{"entry_id": "b", "source": "guesswork", "speaker_id": "q", "text": "B."},
				{"entry_id": "c", "source": "imagined", "speaker_id": "", "text": "  "},
				{"entry_id": "d", "source": "recalled", "speaker_id": "", "text": "D."},
				"not an object",
				{"entry_id": "a", "source": "reported", "speaker_id": "", "text": "A again."},
			]
		}
	)
	_narrative.entries_restored.disconnect(handler)
	_expect(result["ok"] == true, "A snapshot with one bad entry refused the whole log.")
	_expect(int(result["restored"]) == 2, "Expected 2 usable entries, got %d." % int(result["restored"]))
	_expect(
		(result["rejected"] as Array).size() == 4,
		"Expected 4 rejected entries, got %d." % (result["rejected"] as Array).size()
	)
	_expect(
		restored_signal.size() == 1 and restored_signal[0] == 2,
		"entries_restored did not report the two entries that were loaded."
	)
	_expect(_narrative.has_entry(&"b") == false, "An entry with an unknown source was restored.")
	_expect(
		_narrative.count_for_source(NarrativeEntry.Source.OBSERVED) == 1,
		"An unknown source was downgraded to observed."
	)
	_expect(_narrative.has_entry(&"c") == false, "An entry with no text was restored.")
	_expect(_narrative.has_entry(&"d") == true, "A valid entry after a bad one was dropped.")

	# A structurally wrong snapshot changes nothing.
	var before: int = _narrative.get_entries().size()
	var broken: Dictionary = _narrative.restore_snapshot({"entries": "not an array"})
	_expect(broken["ok"] != true, "A snapshot whose entries are not an array was accepted.")
	_expect(
		_narrative.get_entries().size() == before,
		"A refused snapshot emptied or rewrote the log."
	)


# --- Determinism ------------------------------------------------------------


func _expect_seed_round_trip() -> void:
	# `CheckResolver` derives every check from the session seed, so a seed that comes
	# back from the file is the whole of "the same check falls the same way".
	var key := "gate:try_roll"
	var before := CheckResolver.new(4242)
	var expected := CheckResolver.describe(before.roll(&"orientation", 3, 9, 0, key))

	Harness.clear_session_state(self)
	_save.write_payload({"flags": {}, "entries": [], "check_seed": 4242})
	var read: Dictionary = _save.read_save()
	_expect(read["ok"] == true, "A payload holding only a seed was refused.")
	if read["ok"] != true:
		return
	var payload: Dictionary = read["payload"]
	var after := CheckResolver.new(int(payload.get("check_seed", 0)))
	var actual := CheckResolver.describe(after.roll(&"orientation", 3, 9, 0, key))
	_expect(actual == expected, "The same check differs after a round trip:\n  %s\n  %s" % [expected, actual])

	# ...and the assertion above is only meaningful if the seed actually moves the dice.
	# Eight different keys, because any single key can coincide between two seeds (a
	# 1-in-36 chance with 2d6) and a test that fails 3% of the time is worse than none.
	var other := CheckResolver.new(int(payload.get("check_seed", 0)) + 1)
	var differs := false
	for index in 8:
		if other.faces_for("gate:%d" % index) != before.faces_for("gate:%d" % index):
			differs = true
			break
	_expect(differs, "The dice do not depend on the seed, so this test proves nothing.")


# --- Helpers ----------------------------------------------------------------


func _write_raw(text: String) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write a fixture save at %s." % SAVE_PATH)
		return
	file.store_string(text)
	file.close()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
