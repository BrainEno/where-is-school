extends Node
## Autoload `Save`: the one place that reads and writes the save file.
##
## Two things live here, and they are separate on purpose:
##
## - **The file.** Path, atomic write, envelope, version, quarantine of a file we
##   cannot read. `SaveCodec` does the value encoding; this node does the I/O.
## - **The session payload.** What a save is made of: the story flags, the knowledge
##   log, the dice seed and the place the player is standing. `capture()` builds it
##   from the live nodes, `load_game()` validates it and applies it.
##
## The rule the audit (#60) asked for is enforced here: **validation runs before
## application**. A file whose envelope, version, flag types or world block cannot be
## trusted applies nothing at all, so a refused load leaves the session exactly as it
## was and "start a new game" stays a decision instead of a fallback. The one
## deliberate exception is a single untrustworthy knowledge entry, which is rejected
## on its own and reported (ADR 0005 §5).
##
## The payload deliberately does not describe anything mid-flight (a fade, a beat, an
## open conversation). Saves are taken at checkpoints where none of those exist.

## Emitted after a successful write, with the path written.
signal save_written(path: String)
## Emitted when a write fails, so a caller that does not check the return value
## still cannot miss it.
signal save_failed(reason: String, detail: String)
## Emitted after a successful load, once the state nodes are populated.
signal save_loaded(rejected: Array)

const SAVE_PATH := "user://save.json"
## Where an unreadable save is copied before the game starts a new run. Never the
## same file: a bug report needs the bytes that failed.
const BROKEN_PATH := "user://save.broken.json"

## The node whose children are `Player`, `LocationHost` and `DialogueController`.
## Set by the director; without it a save still records progress, it just cannot
## describe a place (and a test that only exercises flags does not need one).
var _world_root: Node = null

## The outcome of the last `save_game()`/`load_game()`, for the HUD, tests and bug
## reports. Shape: `{ok, reason, detail, path, rejected, quarantined_to, version}`.
var _last_result: Dictionary = {}

## How many saves this process has written. Tests assert on the delta so a previous
## check leaving a file behind cannot make them pass by accident.
var saves_written: int = 0


func _ready() -> void:
	# Saves are written from gameplay code, never from the UI thread's idle work, but
	# they must keep working while the tree is paused (a future pause menu).
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind_world(root: Node) -> void:
	_world_root = root


func unbind_world() -> void:
	_world_root = null


func get_last_result() -> Dictionary:
	return _last_result.duplicate(true)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# --- Writing ----------------------------------------------------------------


## Captures the session and writes it. Returns the same shape as `get_last_result()`.
func save_game() -> Dictionary:
	var payload := capture()
	if payload.is_empty():
		return _record_failure("empty", "there is nothing to save yet")
	return write_payload(payload)


## Writes a payload that a caller built. Used by `save_game()` and by tests that want
## to control the contents exactly.
func write_payload(payload: Dictionary) -> Dictionary:
	var text := SaveCodec.wrap(payload, int(Time.get_unix_time_from_system()))
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return _record_failure(
			"write", "could not open %s (error %d)" % [tmp_path, FileAccess.get_open_error()]
		)
	file.store_string(text)
	file.close()

	# Rename over the old file: the reader either sees the previous complete save or
	# the new one, never a half-written file.
	var dir := DirAccess.open("user://")
	if dir == null:
		return _record_failure("write", "could not open user:// for renaming")
	var renamed := dir.rename(tmp_path, SAVE_PATH)
	if renamed != OK:
		# Some platforms refuse to rename onto an existing file. Removing first costs
		# the atomic guarantee, so it is the fallback rather than the default.
		dir.remove(SAVE_PATH)
		renamed = dir.rename(tmp_path, SAVE_PATH)
	if renamed != OK:
		return _record_failure("write", "could not replace %s (error %d)" % [SAVE_PATH, renamed])

	saves_written += 1
	_last_result = {
		"ok": true,
		"reason": "",
		"detail": "",
		"path": SAVE_PATH,
		"rejected": [],
		"quarantined_to": "",
		"version": SaveCodec.VERSION,
	}
	save_written.emit(SAVE_PATH)
	return _last_result.duplicate(true)


# --- Reading ----------------------------------------------------------------


## Reads and validates the file without touching the session. Returns
## `{ok, payload, reason, detail, version, rejected, quarantined_to}`.
func read_save() -> Dictionary:
	if not has_save():
		var missing := _refuse("missing_file", "there is no save at %s" % SAVE_PATH)
		missing["payload"] = {}
		return missing

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var unreadable := _refuse(
			"unreadable",
			"could not open %s (error %d)" % [SAVE_PATH, FileAccess.get_open_error()]
		)
		unreadable["payload"] = {}
		_quarantine()
		unreadable["quarantined_to"] = BROKEN_PATH
		return unreadable
	var text := file.get_as_text()
	file.close()

	var envelope := SaveCodec.unwrap(text)
	if envelope["ok"] != true:
		var refused := _refuse(
			String(envelope["reason"]), String(envelope["detail"])
		)
		refused["payload"] = {}
		refused["quarantined_to"] = _quarantine()
		return refused

	var payload: Dictionary = envelope["payload"]
	var problem := validate_payload(payload)
	if not problem.is_empty():
		var broken := _refuse("payload", problem)
		broken["payload"] = {}
		broken["quarantined_to"] = _quarantine()
		return broken

	return {
		"ok": true,
		"payload": payload,
		"reason": "",
		"detail": "",
		"version": int(envelope["version"]),
		"rejected": [],
		"quarantined_to": "",
	}


## Reads the file, applies what it describes to the session singletons and returns
## `{ok, reason, detail, world, rejected, quarantined_to}`. `world` is for the
## director: this node does not know how to load a location.
##
## Nothing is applied when the file cannot be trusted.
func load_game() -> Dictionary:
	var read := read_save()
	if read["ok"] != true:
		_last_result = read.duplicate(true)
		return _last_result

	var payload: Dictionary = read["payload"]
	var flags_result := SaveCodec.decode_flags(payload.get("flags", {}))
	if flags_result["ok"] != true:
		# `validate_payload` already refused this, so reaching it means the two
		# disagree; fail closed rather than apply half a table.
		var failed := _refuse("payload", String(flags_result["detail"]))
		failed["payload"] = {}
		_last_result = failed
		return _last_result

	var game_state := get_node_or_null(^"/root/GameState")
	if game_state == null:
		var no_state := _refuse("no_state", "GameState is not available")
		_last_result = no_state
		return _last_result
	game_state.replace_snapshot(flags_result["flags"])

	var rejected: Array = []
	var narrative_state := get_node_or_null(^"/root/NarrativeState")
	if narrative_state != null:
		var restored: Dictionary = narrative_state.restore_snapshot(
			{"entries": payload.get("entries", [])}
		)
		if restored["ok"] != true:
			var no_log := _refuse("payload", String(restored["rejected"][0]))
			_last_result = no_log
			return _last_result
		rejected = restored["rejected"]

	var seed_result := _apply_seed(int(payload.get("check_seed", 0)))
	if not seed_result.is_empty():
		var no_seed := _refuse("payload", seed_result)
		_last_result = no_seed
		return _last_result

	_last_result = {
		"ok": true,
		"reason": "",
		"detail": "",
		"path": SAVE_PATH,
		"rejected": rejected,
		"quarantined_to": "",
		"version": int(read["version"]),
		"world": payload.get("world", {}),
	}
	for problem: Variant in rejected:
		push_error("Save: a knowledge entry was rejected: %s" % String(problem))
	save_loaded.emit(rejected)
	return _last_result.duplicate(true)


## Deletes the save and the quarantined copy. This is what "new game" means (ADR
## 0005 §7): after it returns, the next boot starts the prologue from the beginning.
func delete_save() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for path in [SAVE_PATH, BROKEN_PATH]:
		if FileAccess.file_exists(path):
			dir.remove(path)


## Test hygiene: forget everything this process knows, including the file. Used by
## `TestHarness.clear_session_state()` so one check cannot resume another's run.
func forget_all() -> void:
	delete_save()
	_last_result = {}
	saves_written = 0


# --- Payload ----------------------------------------------------------------


## Builds the payload from the live nodes. Sections whose node is missing are left
## out rather than written as nulls, and `load_game()` treats them as absent.
func capture() -> Dictionary:
	var game_state := get_node_or_null(^"/root/GameState")
	if game_state == null:
		return {}
	var payload: Dictionary = {"flags": SaveCodec.encode_flags(game_state.get_snapshot())}

	var narrative_state := get_node_or_null(^"/root/NarrativeState")
	if narrative_state != null:
		var snapshot: Dictionary = narrative_state.to_snapshot()
		payload["entries"] = snapshot.get("entries", [])

	var dialogue := _world_child("DialogueController")
	if dialogue != null and dialogue.has_method("get_session_seed"):
		payload["check_seed"] = int(dialogue.get_session_seed())

	var world := _capture_world()
	if not world.is_empty():
		payload["world"] = world
	return payload


## Validates the payload's shape without applying it. Returns `""` when it can be
## used, or a sentence naming the first problem.
func validate_payload(payload: Dictionary) -> String:
	var flags: Variant = payload.get("flags", {})
	if not (flags is Dictionary):
		return "'flags' is not an object"
	# Value-level validation, not just the shape: a flag whose type tag nobody knows is a
	# payload error, and knowing that before anything is applied is what keeps
	# `load_game()` from ever having to undo a half-applied session.
	var decoded := SaveCodec.decode_flags(flags)
	if decoded["ok"] != true:
		return String(decoded["detail"])
	if not (payload.get("entries", []) is Array):
		return "'entries' is not an array"
	var seed_value: Variant = payload.get("check_seed", 0)
	if not (seed_value is int or seed_value is float):
		return "'check_seed' is not a number"
	if payload.has("world"):
		var world: Variant = payload["world"]
		if not (world is Dictionary):
			return "'world' is not an object"
		return _validate_world(world)
	return ""


func _validate_world(world: Dictionary) -> String:
	var location_id := String(world.get("location_id", ""))
	if location_id.is_empty():
		return "'world.location_id' is empty"
	if not (world.get("spawn", "") is String):
		return "'world.spawn' is not a string"
	for key in ["position", "facing"]:
		var point: Variant = world.get(key, null)
		if point == null:
			continue
		if not (point is Array) or (point as Array).size() != 3:
			return "'world.%s' is not three numbers" % key
		for value: Variant in point:
			if not (value is float or value is int):
				return "'world.%s' is not three numbers" % key
	return ""


func _capture_world() -> Dictionary:
	var location_host := _world_child("LocationHost")
	if location_host == null:
		return {}
	if not location_host.has_method("get_current"):
		return {}
	# Typed, not inferred: `get_current()` is a dynamic call on a Node, so a ternary
	# that can also yield null has no type for the compiler to pick.
	var location: LocationRoot = location_host.get_current()
	if location == null:
		return {}
	var world: Dictionary = {
		"location_id": String(location.location_id),
		"spawn": String(location_host.get_current_spawn()),
	}
	var player := _world_child("Player") as Node3D
	if player != null:
		var position := player.global_position
		world["position"] = [position.x, position.y, position.z]
		if player.has_method("get_facing_direction"):
			var facing: Vector3 = player.get_facing_direction()
			world["facing"] = [facing.x, facing.y, facing.z]
	return world


func _apply_seed(seed_value: int) -> String:
	var dialogue := _world_child("DialogueController")
	if dialogue == null or not dialogue.has_method("set_session_seed"):
		# A session with no dialogue controller has no dice to keep consistent.
		return ""
	dialogue.set_session_seed(seed_value)
	return ""


func _world_child(child_name: String) -> Node:
	if _world_root == null or not is_instance_valid(_world_root):
		return null
	return _world_root.get_node_or_null(NodePath(child_name))


# --- Failure bookkeeping ----------------------------------------------------


func _record_failure(reason: String, detail: String) -> Dictionary:
	_last_result = _refuse(reason, detail)
	push_error("Save: %s (%s)." % [detail, reason])
	save_failed.emit(reason, detail)
	return _last_result.duplicate(true)


func _refuse(reason: String, detail: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"detail": detail,
		"path": "",
		"rejected": [],
		"quarantined_to": "",
		"version": 0,
		"world": {},
	}


## Copies the file we could not read to `save.broken.json` and returns that path.
## The original stays where it is: nothing this node does may destroy a save.
func _quarantine() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var text_file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if text_file == null:
		return ""
	var text := text_file.get_as_text()
	text_file.close()
	var broken := FileAccess.open(BROKEN_PATH, FileAccess.WRITE)
	if broken == null:
		return ""
	broken.store_string(text)
	broken.close()
	push_error("Save: the unreadable save was copied to %s." % BROKEN_PATH)
	return BROKEN_PATH
