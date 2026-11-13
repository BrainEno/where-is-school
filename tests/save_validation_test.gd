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
const USER_DIR := "user://"
## Keep the native-int edges independent of the codec's float range guard. In
## particular, converting MAX_SIGNED_INT to float would round it up to 2^63.
const MAX_SIGNED_INT := 9223372036854775807
const MIN_SIGNED_INT := -MAX_SIGNED_INT - 1


## The real file layer, with the operations a case names made to fail.
##
## A disk cannot be asked to fail on demand, and every failure the writer has to survive
## happens *halfway through* a replacement — which is exactly the moment no test can reach
## by other means. So the six calls are repeated here, each checking a list of call indices
## first: call 0 of `rename`, call 1, or all of them. Everything else goes to the real
## filesystem, so the bytes under assertion are real bytes on a real disk.
class FaultyIO:
	var fail_writes: Array = []
	var fail_renames: Array = []
	var fail_removes: Array = []
	var fail_reads: Array = []
	## A write that reports success and stores fewer bytes: the "full disk" case.
	var truncate_writes := false
	var writes := 0
	var renames := 0
	var removes := 0
	var reads := 0
	## Every path a removal was attempted on, so a case can prove the save itself was never
	## one of them.
	var removed: Array = []
	## Every (from, to) pair a rename was attempted with.
	var renamed: Array = []

	func exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> PackedByteArray:
		var index := reads
		reads += 1
		if fail_reads.has(index):
			return PackedByteArray()
		return FileAccess.get_file_as_bytes(path)

	func write_bytes(path: String, data: PackedByteArray) -> int:
		var index := writes
		writes += 1
		if fail_writes.has(index):
			return ERR_FILE_CANT_WRITE
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		var payload := data
		if truncate_writes and data.size() > 8:
			payload = data.slice(0, data.size() / 2)
		file.store_buffer(payload)
		var error := file.get_error()
		file.close()
		return error

	func rename(from: String, to: String) -> int:
		var index := renames
		renames += 1
		renamed.append([from, to])
		if fail_renames.has(index):
			return ERR_FILE_CANT_WRITE
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return DirAccess.get_open_error()
		return dir.rename(from, to)

	func remove(path: String) -> int:
		var index := removes
		removes += 1
		removed.append(path)
		if fail_removes.has(index):
			return ERR_FILE_CANT_WRITE
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return DirAccess.get_open_error()
		return dir.remove(path)

	func list() -> PackedStringArray:
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return PackedStringArray()
		return dir.get_files()

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

	Harness.stage = "integer validation"
	var integer_failures_before := _failures.size()
	_expect_integer_values()
	_expect_integer_versions()
	_expect_integer_load_refusals()
	print(
		"::notice title=save integer validation::native int64 edges, integral floats, "
		+ "fractions, non-finite/range guards, nested paths and disk refusals; %d problem(s)"
		% (_failures.size() - integer_failures_before)
	)

	Harness.stage = "knowledge"
	_expect_knowledge_rules()

	Harness.stage = "determinism"
	_expect_seed_round_trip()

	Harness.stage = "write failures"
	_check_write_failures()

	Harness.stage = "recovery and cleanup"
	_check_recovery_and_cleanup()

	Harness.stage = "the delete contract"
	_check_delete_contract()

	Harness.stage = "housekeeping"
	_save.delete_save({"broken": true})
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


# --- Integer validation (#149) ----------------------------------------------


func _expect_integer_values() -> void:
	var invalid: Array = [
		{"label": "positive fraction", "value": 3.7},
		{"label": "negative fraction", "value": -3.7},
		{"label": "not a number", "value": NAN},
		{"label": "positive infinity", "value": INF},
		{"label": "negative infinity", "value": -INF},
		{"label": "exclusive upper edge", "value": 9223372036854775808.0},
		{"label": "below the lower edge", "value": -9223372036854777856.0},
		{"label": "numeric string", "value": "3"},
		{"label": "boolean", "value": true},
	]
	for fixture: Dictionary in invalid:
		var decoded := SaveCodec.decode_value({"t": "i", "v": fixture["value"]}, "flags.numeric")
		_expect(decoded["ok"] != true, "An int tag accepted %s." % fixture["label"])
		_expect(
			String(decoded.get("detail", "")).contains("flags.numeric"),
			"The %s int refusal did not name flags.numeric." % fixture["label"]
		)

	var valid: Array = [
		{"label": "native zero", "value": 0, "expected": 0},
		{"label": "integral float", "value": 3.0, "expected": 3},
		{"label": "negative integral float", "value": -3.0, "expected": -3},
		{"label": "negative zero", "value": -0.0, "expected": 0},
		{"label": "native maximum", "value": MAX_SIGNED_INT, "expected": MAX_SIGNED_INT},
		{"label": "native minimum", "value": MIN_SIGNED_INT, "expected": MIN_SIGNED_INT},
		{"label": "float minimum", "value": -9223372036854775808.0, "expected": MIN_SIGNED_INT},
		{
			"label": "last float below the upper edge",
			"value": 9223372036854774784.0,
			"expected": 9223372036854774784,
		},
	]
	for fixture: Dictionary in valid:
		var decoded := SaveCodec.decode_value({"t": "i", "v": fixture["value"]}, "flags.numeric")
		_expect(decoded["ok"] == true, "An int tag refused %s: %s" % [fixture["label"], decoded])
		_expect(
			typeof(decoded.get("value")) == TYPE_INT and decoded.get("value") == fixture["expected"],
			"The %s int changed type or value." % fixture["label"]
		)

	# Fractions belong to a float tag; tightening integers must not narrow floats.
	var floating := SaveCodec.decode_value({"t": "f", "v": -3.7}, "flags.floating")
	_expect(
		floating["ok"] == true and typeof(floating.get("value")) == TYPE_FLOAT
		and floating.get("value") == -3.7,
		"A legitimate fractional float tag was changed or refused."
	)
	var nested := SaveCodec.decode_flags({
		"fine": {"t": "i", "v": 1},
		"nested": {"t": "d", "v": {"rolls": {"t": "a", "v": [{"t": "i", "v": 3.7}]}}},
	})
	_expect(nested["ok"] != true, "A nested fractional integer flag was accepted.")
	_expect((nested["flags"] as Dictionary).is_empty(), "A refused integer table was partially decoded.")
	_expect(
		String(nested.get("detail", "")).contains("flags.nested.rolls[0]"),
		"The nested integer refusal lost its array/dictionary path."
	)


func _expect_integer_versions() -> void:
	for token: String in [
		"1.9", "1.0001", "-1.9", "0.9", "9223372036854775808.0", "-9223372036854777856.0",
	]:
		var text := '{"format":"where-is-school/save","version":%s,"payload":{}}' % token
		var decoded := SaveCodec.unwrap(text)
		_expect(decoded["ok"] != true, "The envelope accepted version %s." % token)
		_expect(decoded["reason"] == "version", "Version %s did not report a version refusal." % token)
		_expect((decoded["payload"] as Dictionary).is_empty(), "A refused version exposed its payload.")
		_expect(
			String(decoded.get("detail", "")).contains("version"),
			"The version %s refusal did not name the field." % token
		)

	# Test the raw JSON spelling too: JSON numbers arrive as floats in Godot.
	for token: String in ["1", "1.0", "1e0"]:
		var text := '{"format":"where-is-school/save","version":%s,"payload":{}}' % token
		var decoded := SaveCodec.unwrap(text)
		_expect(decoded["ok"] == true, "The valid version spelling %s was refused." % token)
		_expect(
			typeof(decoded.get("version")) == TYPE_INT and decoded.get("version") == SaveCodec.VERSION,
			"The valid version spelling %s changed type or value." % token
		)


func _expect_integer_load_refusals() -> void:
	var fixtures: Array = [
		{"label": "fractional version", "version": 1.9, "bad": {"t": "i", "v": 3},
			"reason": "version", "path": "version"},
		{"label": "fractional flag", "version": 1, "bad": {"t": "i", "v": -3.7},
			"reason": "payload", "path": "flags.bad"},
		{"label": "out-of-range flag", "version": 1, "bad": {"t": "i", "v": 9223372036854775808.0},
			"reason": "payload", "path": "flags.bad"},
		{"label": "nested fractional flag", "version": 1,
			"bad": {"t": "a", "v": [{"t": "i", "v": 3.7}]},
			"reason": "payload", "path": "flags.bad[0]"},
	]
	for fixture: Dictionary in fixtures:
		Harness.clear_session_state(self)
		_game_state.set_flag(&"kept_across_integer_refusal", 7)
		var seeded: Dictionary = _narrative.restore_snapshot({"entries": [{
			"entry_id": "kept_integer_knowledge", "source": "recalled",
			"speaker_id": "", "text": "Existing test knowledge.",
		}]})
		_expect(seeded["ok"] == true, "Could not seed the integer refusal's knowledge fixture.")
		var flags_before: Dictionary = _game_state.get_snapshot().duplicate(true)
		var knowledge_before: Dictionary = _narrative.to_snapshot().duplicate(true)
		var text := JSON.stringify({
			"format": SaveCodec.FORMAT, "version": fixture["version"],
			"payload": {"flags": {"must_not_apply": {"t": "b", "v": true}, "bad": fixture["bad"]},
				"entries": [], "check_seed": 0},
		})
		_write_raw(text)
		var bytes := _disk_bytes(SAVE_PATH)
		_expect(bytes == text.to_utf8_buffer(), "The integer refusal fixture was not written in full.")
		var loaded: Dictionary = _save.load_game()
		_expect(loaded["ok"] != true, "load_game accepted %s." % fixture["label"])
		_expect(
			loaded.get("reason") == fixture["reason"]
			and String(loaded.get("detail", "")).contains(String(fixture["path"])),
			"The %s load refusal lost its reason/path: %s" % [fixture["label"], loaded]
		)
		_expect(
			_game_state.get_snapshot() == flags_before,
			"A %s load applied or cleared flags." % fixture["label"]
		)
		_expect(
			_narrative.to_snapshot() == knowledge_before,
			"A %s load applied or cleared knowledge." % fixture["label"]
		)
		_expect(_disk_bytes(SAVE_PATH) == bytes, "An integer refusal rewrote/deleted the save.")
		_expect(_disk_bytes(BROKEN_PATH) == bytes, "The integer refusal quarantine is not the original bytes.")
		var repeated: Dictionary = _save.load_game()
		_expect(repeated["ok"] != true, "A repeated integer refusal unexpectedly loaded.")
		_expect(
			_game_state.get_snapshot() == flags_before and _narrative.to_snapshot() == knowledge_before
			and _disk_bytes(SAVE_PATH) == bytes and _disk_bytes(BROKEN_PATH) == bytes,
			"Repeating an integer refusal changed the session, save or quarantine."
		)
	Harness.clear_session_state(self)


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


# --- Writing: what a failure costs ------------------------------------------
#
# Every case below writes one save, then tries to write a second one with exactly one call
# made to fail, and asks the same three questions: was the failure reported, is the *first*
# save still the bytes it was, and was the save file itself ever removed to make room.


func _check_write_failures() -> void:
	Harness.clear_session_state(self)
	var first: Dictionary = _save.write_payload(_payload(&"first_run"))
	_expect(first["ok"] == true, "the fixture save was not written: %s" % first)
	var before := _disk_bytes(SAVE_PATH)
	_expect(not before.is_empty(), "the fixture save has no bytes on disk.")

	# 1. The temporary file cannot be written at all. Nothing else is touched.
	var io := _install(FaultyIO.new())
	io.fail_writes = [0]
	var result: Dictionary = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] != true, "a write that failed was reported as a success.")
	_expect(String(result.get("reason", "")) == "write", "the failure reason was '%s'." % result.get("reason"))
	_expect(_disk_bytes(SAVE_PATH) == before, "a failed write changed the save on disk.")
	_expect(not io.removed.has(SAVE_PATH), "a failed write removed the save.")
	_expect(_strays().is_empty(), "a failed write left %s behind." % str(_strays()))

	# 2. The write reports success and the bytes are not there: the "full disk" case. The
	#    writer has to notice, because `store_buffer()` returning is not evidence.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	before = _disk_bytes(SAVE_PATH)
	io = _install(FaultyIO.new())
	io.truncate_writes = true
	result = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] != true, "a shortened write was accepted as a complete save.")
	_expect(
		String(result.get("detail", "")).contains("reads back")
		or String(result.get("detail", "")).contains("does not hold"),
		"the short write was not described as a short write: %s" % result.get("detail")
	)
	_expect(_disk_bytes(SAVE_PATH) == before, "a short write changed the save on disk.")

	# 3. The rename onto the save path fails, and so does every retry: the old save is still
	#    there, byte for byte, and was never removed.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	before = _disk_bytes(SAVE_PATH)
	io = _install(FaultyIO.new())
	io.fail_renames = [0, 1, 2, 3, 4, 5]
	result = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] != true, "a save that was never installed was reported as written.")
	_expect(_disk_bytes(SAVE_PATH) == before, "the old save is not the file it was.")
	_expect(not io.removed.has(SAVE_PATH), "the writer removed the save to make room for a new one.")
	_expect(_strays().is_empty(), "a failed replacement left %s behind." % str(_strays()))

	# 4. The platform refuses to rename onto an existing file (the first rename), so the
	#    two-step swap runs: the old save is moved aside, the new one installed, the backup
	#    removed. It succeeds once, and the save on disk is the new one.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	io = _install(FaultyIO.new())
	io.fail_renames = [0]
	result = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] == true, "the backup path did not save the file: %s" % result)
	_expect(not io.removed.has(SAVE_PATH), "the backup path removed the save instead of moving it.")
	_expect(_strays().is_empty(), "the backup path left %s behind." % str(_strays()))
	var read: Dictionary = _save.read_save()
	_expect(read["ok"] == true, "the save written through the backup path cannot be read.")
	if read["ok"] == true:
		var flags: Dictionary = SaveCodec.decode_flags(read["payload"].get("flags", {}))["flags"]
		_expect(flags.has(&"second_run"), "the file on disk is not the save that was written.")

	# 5. The second phase fails: the new save cannot be installed *and* the old one cannot be
	#    put back. What is left must be a named recovery path holding the old bytes.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	before = _disk_bytes(SAVE_PATH)
	io = _install(FaultyIO.new())
	io.fail_renames = [0, 2, 3]
	result = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] != true, "a replacement that could not be installed was reported as written.")
	var recovery := String(result.get("recovery_path", ""))
	_expect(not recovery.is_empty(), "the failure names no recovery path.")
	if not recovery.is_empty():
		_expect(
			_disk_bytes(recovery) == before,
			"the recovery path %s does not hold the save that was there before." % recovery
		)

	# 6. The same, except the old save *can* be put back: it is back at the save path, and
	#    the game reads it as its own.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	before = _disk_bytes(SAVE_PATH)
	io = _install(FaultyIO.new())
	io.fail_renames = [0, 2]
	result = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] != true, "a replacement that failed was reported as written.")
	_expect(_disk_bytes(SAVE_PATH) == before, "the old save was not put back after a failed swap.")
	read = _save.read_save()
	_expect(read["ok"] == true, "the save left after a failed swap cannot be read.")
	if read["ok"] == true:
		var restored: Dictionary = SaveCodec.decode_flags(read["payload"].get("flags", {}))["flags"]
		_expect(restored.has(&"first_run"), "the save left after a failed swap is not the old one.")

	# 7. The backup cannot be removed. The write still succeeded, and the file it could not
	#    clean up is named rather than forgotten.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	io = _install(FaultyIO.new())
	io.fail_renames = [0]
	io.fail_removes = [0, 1, 2, 3]
	result = _save.write_payload(_payload(&"second_run"))
	_uninstall()
	_expect(result["ok"] == true, "a write failed because a backup could not be cleaned up.")
	_expect(
		(result.get("leftovers", []) as Array).size() > 0,
		"a backup that could not be removed was not reported."
	)
	_expect(_save.read_save()["ok"] == true, "the save written beside an unclean backup is unreadable.")
	_force_clean()

	# 8. No write at all is accepted while a new game holds the files.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	before = _disk_bytes(SAVE_PATH)
	_save.suspend_writes(true)
	result = _save.write_payload(_payload(&"second_run"))
	_save.suspend_writes(false)
	_expect(result["ok"] != true, "a write during a suspended session was accepted.")
	_expect(String(result.get("reason", "")) == "suspended", "the refusal reason was '%s'." % result.get("reason"))
	_expect(_disk_bytes(SAVE_PATH) == before, "a suspended write touched the save.")


# --- Recovery and cleanup ---------------------------------------------------


func _check_recovery_and_cleanup() -> void:
	# A temporary file left by a crash is rubbish, and the next write clears it.
	Harness.clear_session_state(self)
	var stale := SAVE_PATH + ".000000000001-001-0001.tmp"
	var file := FileAccess.open(stale, FileAccess.WRITE)
	file.store_string("half a save")
	file.close()
	_expect(FileAccess.file_exists(stale), "the stale temporary file was not created.")
	var result: Dictionary = _save.write_payload(_payload(&"first_run"))
	_expect(result["ok"] == true, "a write with a stale temporary file present failed: %s" % result)
	_expect(not FileAccess.file_exists(stale), "the stale temporary file survived a successful write.")
	_expect((result.get("leftovers", []) as Array).is_empty(), "a clean write reported leftovers.")

	# A save that is *only* at its staged name (the process died mid-swap) is put back by the
	# next read instead of looking like a missing run.
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"crashed_run"))
	var bytes := _disk_bytes(SAVE_PATH)
	var staged: Dictionary = _save.stage_save()
	_expect(staged["ok"] == true, "stage_save() failed: %s" % staged)
	_expect(not FileAccess.file_exists(SAVE_PATH), "staging left the save where it was.")
	var staged_path := String(staged.get("staged_path", ""))
	_expect(FileAccess.file_exists(staged_path), "staging did not leave a copy behind.")
	_expect(_save.has_save(), "a staged save was not recovered on the next check.")
	_expect(_disk_bytes(SAVE_PATH) == bytes, "the recovered save is not the bytes that were staged.")
	_expect(not FileAccess.file_exists(staged_path), "the staged copy survived its own recovery.")
	var recovered: Dictionary = _save.read_save()
	_expect(recovered["ok"] == true, "the recovered save cannot be read.")
	_force_clean()


# --- The delete contract ----------------------------------------------------


func _check_delete_contract() -> void:
	Harness.clear_session_state(self)
	_save.write_payload(_payload(&"first_run"))
	_write_raw_to(BROKEN_PATH, "{\"the broken save\": true}")
	var broken := _disk_bytes(BROKEN_PATH)

	# The quarantined copy of an unreadable save outlives the save it came from.
	var result: Dictionary = _save.delete_save()
	_expect(result["ok"] == true, "delete_save() failed: %s" % result)
	_expect(not FileAccess.file_exists(SAVE_PATH), "delete_save() left the save behind.")
	_expect(FileAccess.file_exists(BROKEN_PATH), "delete_save() removed the quarantined copy.")
	_expect(_disk_bytes(BROKEN_PATH) == broken, "delete_save() rewrote the quarantined copy.")
	_expect(not (result.get("removed", []) as Array).has(BROKEN_PATH), "the result claims the copy was removed.")

	# Asking for it removes it, which is what test hygiene needs and a new game must not.
	result = _save.delete_save({"broken": true})
	_expect(result["ok"] == true, "delete_save({\"broken\": true}) failed: %s" % result)
	_expect(not FileAccess.file_exists(BROKEN_PATH), "asking for the quarantined copy left it behind.")

	# A delete that the filesystem refuses is a failure with the file still there, not a
	# silent no-op.
	_save.write_payload(_payload(&"first_run"))
	var before := _disk_bytes(SAVE_PATH)
	var io := _install(FaultyIO.new())
	io.fail_removes = [0, 1, 2, 3]
	result = _save.delete_save()
	_uninstall()
	_expect(result["ok"] != true, "a delete the disk refused was reported as done.")
	_expect(String(result.get("reason", "")) == "delete", "the delete failure reason was '%s'." % result.get("reason"))
	_expect(_disk_bytes(SAVE_PATH) == before, "a refused delete damaged the save.")


# --- Helpers ----------------------------------------------------------------


func _payload(flag: StringName) -> Dictionary:
	return {
		"flags": SaveCodec.encode_flags({flag: true, &"counter": 3}),
		"entries": [],
		"check_seed": 4242,
	}


func _disk_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _install(faults: FaultyIO) -> FaultyIO:
	_save.set("io", faults)
	return faults


func _uninstall() -> void:
	_save.set("io", null)


## Everything the save system may leave behind, by name.
func _strays() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return found
	for name: String in dir.get_files():
		if name.begins_with("save.json."):
			found.append(name)
	found.sort()
	return found


func _force_clean() -> void:
	_uninstall()
	_save.suspend_writes(false)
	_save.delete_save({"broken": true})
	for name: String in _strays():
		DirAccess.remove_absolute(USER_DIR + name)


func _write_raw_to(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not write a fixture at %s." % path)
		return
	file.store_string(text)
	file.close()


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
