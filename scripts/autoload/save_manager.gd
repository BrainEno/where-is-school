extends Node
## Autoload `Save`: the one place that reads and writes the save file.
##
## Two things live here, and they are separate on purpose:
##
## - **The file.** Path, verified write-and-swap, envelope, version, recovery of an
##   interrupted swap, quarantine of a file we cannot read. `SaveCodec` does the value
##   encoding; this node does the I/O.
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
##
## **The file itself** - verified writes, the swap onto the save path, staged copies,
## recovery of an interrupted swap and the quarantine copy - is `SaveFileStore`
## (`scripts/save/save_file_store.gd`), split out of this node for issue #223. Its header
## states what the write path promises and what it does not; this node decides *when* the
## file may change (never while a new game holds `suspend_writes()`), turns the store's
## results into the ones its callers have always received, and reports failures.

const OfflineDiagnostics := preload("res://scripts/autoload/diagnostics.gd")

## Emitted after a successful write, with the path written.
signal save_written(path: String)
## Emitted when a write fails, so a caller that does not check the return value
## still cannot miss it.
signal save_failed(reason: String, detail: String)
## Emitted after a successful load, once the state nodes are populated.
signal save_loaded(rejected: Array)

const SAVE_PATH := SaveFileStore.SAVE_PATH
## Where an unreadable save is copied before the game starts a new run.
const BROKEN_PATH := SaveFileStore.BROKEN_PATH
## The save's file name, for the temporary, backup and staged files that share it.
const SAVE_BASENAME := SaveFileStore.SAVE_BASENAME
## The directory every path above lives in.
const USER_DIR := SaveFileStore.USER_DIR

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

## Replaces `SaveFileStore.FileIO` for a test. Null means the real filesystem. Untyped on
## purpose: the six calls are made dynamically, so a test's stand-in does not have to share
## a base class with the real one. The store asks for it on every operation, so a test may
## swap it between two calls.
var io: Variant = null
## The bytes on disk. Reads `io` through a callable on every operation, see above.
var _store: SaveFileStore = null

## Set while a new game is being prepared: the old world must not be able to put a
## checkpoint back on disk between the save being taken away and the new run starting.
var _writes_suspended := false


func _init() -> void:
	_store = SaveFileStore.new(_current_io)


## What the store uses as its filesystem: the test's `io`, or null for the real one.
func _current_io() -> Variant:
	return io


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
	recover_pending_swap()
	return _store.has_save()


# --- Writing ----------------------------------------------------------------


## Captures the session and writes it. Returns the same shape as `get_last_result()`.
func save_game() -> Dictionary:
	var payload := capture()
	if payload.is_empty():
		return _record_failure("empty", "there is nothing to save yet")
	return write_payload(payload)


## Writes a payload that a caller built. Used by `save_game()` and by tests that want
## to control the contents exactly.
##
## The result always carries `{ok, reason, detail, path, temp_path, backup_path,
## recovery_path, leftovers}`. `recovery_path` is where the previous save can be found if
## this write did not land, and `leftovers` names every temporary file that could not be
## cleaned up — both are facts the caller can act on, not warnings to ignore.
func write_payload(payload: Dictionary) -> Dictionary:
	if _writes_suspended:
		return _record_failure(
			"suspended", "a new game is being started; nothing may write the save until it ends"
		)

	var text := SaveCodec.wrap(payload, int(Time.get_unix_time_from_system()))
	var written := _store.write_save(text.to_utf8_buffer())
	if not bool(written["ok"]) and not bool(written.get("swapped", true)):
		return _record_failure("write", String(written["detail"]))
	if not bool(written["ok"]):
		var failed := _record_failure(String(written["reason"]), String(written["detail"]))
		failed["recovery_path"] = String(written.get("recovery_path", ""))
		failed["backup_path"] = String(written.get("backup_path", ""))
		failed["leftovers"] = written.get("leftovers", [])
		_last_result = failed
		return failed.duplicate(true)

	var leftovers: Array = written["leftovers"]
	if not leftovers.is_empty():
		OfflineDiagnostics.note("save.cleanup_incomplete", {"count": leftovers.size()})
		push_warning("Save: a save was written but %d file(s) could not be cleaned up: %s"
			% [leftovers.size(), ", ".join(leftovers)])

	saves_written += 1
	_last_result = {
		"ok": true,
		"reason": "",
		"detail": "",
		"path": SAVE_PATH,
		"temp_path": String(written["temp_path"]),
		"backup_path": String(written["backup_path"]),
		"recovery_path": "",
		"leftovers": leftovers,
		"rejected": [],
		"quarantined_to": "",
		"version": SaveCodec.VERSION,
	}
	OfflineDiagnostics.note("save.written", {"version": SaveCodec.VERSION})
	save_written.emit(SAVE_PATH)
	return _last_result.duplicate(true)


## Puts back a save left behind as `.bak`/`.staged` by a crash in the middle of a swap.
##
## Only runs when there is no save at all: a save that is there is the truth, and this
## never overwrites it. Returns `{ok, recovered, path}`.
func recover_pending_swap() -> Dictionary:
	# A new game owns these files while it runs: one of its staged copies is *supposed* to
	# be the only copy for a moment, and putting it back here would undo the very thing it
	# is doing.
	if _writes_suspended:
		return {"ok": true, "recovered": false, "path": ""}
	return _store.recover_pending_swap()


## Moves the save to a unique staged file and proves the move, so a caller that is about
## to start a new game holds a recoverable copy until it commits. The save path is empty
## afterwards, which is what "start fresh" means.
##
## Returns `{ok, staged, staged_path, reason, detail}`.
func stage_save() -> Dictionary:
	return _store.stage_save()


## Puts a staged save back where the game reads it, and proves the bytes arrived.
func restore_staged(staged_path: String) -> Dictionary:
	return _store.restore_staged(staged_path)


## Removes a staged save, and says whether it is really gone.
func discard_staged(staged_path: String) -> Dictionary:
	return _store.discard_staged(staged_path)


## Removes every temporary, backup and staged file beside the save, and says which could
## not be removed. Only a committed new game calls this, while writes are still suspended:
## the player has just confirmed that the run those files belong to is to be discarded, and
## a leftover from it must not be "recovered" as the save of the run that replaces it
## (`recover_pending_swap()` would do exactly that the first time the save path is empty).
## Returns `{ok, removed, leftovers}`.
func discard_strays() -> Dictionary:
	return _store.discard_strays()


## Refuses writes until `false`. A new game holds this while it moves the save away and
## clears the session, so the world it is replacing cannot put a checkpoint back.
func suspend_writes(suspended: bool) -> void:
	_writes_suspended = suspended


func writes_suspended() -> bool:
	return _writes_suspended


# --- Reading ----------------------------------------------------------------


## Reads and validates the file without touching the session. Returns
## `{ok, payload, reason, detail, version, rejected, quarantined_to}`.
func read_save() -> Dictionary:
	recover_pending_swap()
	if not _store.has_save():
		var missing := _refuse("missing_file", "there is no save at %s" % SAVE_PATH)
		missing["payload"] = {}
		return missing

	var bytes: PackedByteArray = _store.read_save_bytes()
	if bytes.is_empty():
		var unreadable := _refuse(
			"unreadable", "could not read %s (%d byte(s))" % [SAVE_PATH, bytes.size()]
		)
		OfflineDiagnostics.note("save.read_refused", {"reason": "unreadable"})
		unreadable["payload"] = {}
		unreadable["quarantined_to"] = _quarantine()
		return unreadable
	var text := bytes.get_string_from_utf8()

	var envelope := SaveCodec.unwrap(text)
	if envelope["ok"] != true:
		var refused := _refuse(
			String(envelope["reason"]), String(envelope["detail"])
		)
		OfflineDiagnostics.note("save.read_refused", {"reason": envelope["reason"]})
		refused["payload"] = {}
		refused["quarantined_to"] = _quarantine()
		return refused

	var payload: Dictionary = envelope["payload"]
	var problem := validate_payload(payload)
	if not problem.is_empty():
		var broken := _refuse("payload", problem)
		OfflineDiagnostics.note("save.read_refused", {"reason": "payload"})
		broken["payload"] = {}
		broken["quarantined_to"] = _quarantine()
		return broken

	return {
		"ok": true,
		"payload": payload,
		"reason": "",
		"detail": "",
		"version": int(envelope["version"]),
		"saved_at_unix": int(envelope.get("saved_at_unix", 0)),
		"rejected": [],
		"quarantined_to": "",
	}


## What a menu shows about the save, read without side effects: no recovery of an
## interrupted swap, no quarantine, nothing applied. Returns `{exists, ok, saved_at_unix,
## location_id}`; `ok` is false for a file this build cannot read (the title screen's
## `read_save()` is what reports and quarantines it).
##
## The pause menu asks this while a run is live. `read_save()` would be wrong there: with no
## save on disk yet (a new run before its first checkpoint) its recovery pass could put an
## older run's leftover back under the save path.
func peek_save() -> Dictionary:
	var info := {"exists": false, "ok": false, "saved_at_unix": 0, "location_id": ""}
	if not _store.has_save():
		return info
	info["exists"] = true
	var bytes: PackedByteArray = _store.read_save_bytes()
	var envelope := SaveCodec.unwrap(bytes.get_string_from_utf8())
	if envelope["ok"] != true:
		return info
	var payload: Dictionary = envelope["payload"]
	if not validate_payload(payload).is_empty():
		return info
	info["ok"] = true
	info["saved_at_unix"] = int(envelope.get("saved_at_unix", 0))
	var world: Variant = payload.get("world", {})
	if world is Dictionary:
		info["location_id"] = String((world as Dictionary).get("location_id", ""))
	return info


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
		OfflineDiagnostics.note("save.read_refused", {"reason": "payload"})
		_last_result = failed
		return _last_result

	var game_state := get_node_or_null(^"/root/GameState")
	if game_state == null:
		var no_state := _refuse("no_state", "GameState is not available")
		OfflineDiagnostics.note("save.read_refused", {"reason": "no_state"})
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
		OfflineDiagnostics.note("save.read_refused", {"reason": "seed"})
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
	OfflineDiagnostics.note("save.loaded", {"version": _last_result["version"]})
	save_loaded.emit(rejected)
	return _last_result.duplicate(true)


## Deletes the save file and proves it is gone. Returns
## `{ok, reason, detail, removed, leftovers}`.
##
## The quarantined copy of an unreadable save is **not** removed: it is the player's only
## copy of a file this build could not read, and the point of writing it aside is that it
## outlives the run that could not open it. `{"broken": true}` removes it too, which is
## what test hygiene wants and what a new game must not do.
func delete_save(options: Dictionary = {}) -> Dictionary:
	var remove_broken := bool(options.get("broken", false))
	var targets: Array = [SAVE_PATH, BROKEN_PATH] if remove_broken else [SAVE_PATH]
	var outcome := _store.remove_files(targets)
	var removed: Array = outcome["removed"]
	var refused: Array = outcome["refused"]
	if not refused.is_empty():
		var failed := _record_failure("delete", "; ".join(refused))
		failed["removed"] = removed
		_last_result = failed
		return failed.duplicate(true)
	_last_result = {
		"ok": true,
		"reason": "",
		"detail": "",
		"path": SAVE_PATH,
		"removed": removed,
		"leftovers": [],
		"rejected": [],
		"quarantined_to": "",
		"version": 0,
	}
	return _last_result.duplicate(true)


## Test hygiene: forget everything this process knows, including the files. Used by
## `TestHarness.clear_session_state()` so one check cannot resume another's run.
func forget_all() -> void:
	delete_save({"broken": true})
	_store.cleanup_strays([], SaveFileStore.ALL_STRAY_KINDS)
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
	OfflineDiagnostics.note("save.operation_failed", {"reason": reason})
	push_error("Save: %s (%s)." % [detail, reason])
	save_failed.emit(reason, detail)
	return _last_result.duplicate(true)


func _refuse(reason: String, detail: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"detail": detail,
		"path": "",
		"temp_path": "",
		"backup_path": "",
		"recovery_path": "",
		"leftovers": [],
		"rejected": [],
		"quarantined_to": "",
		"version": 0,
		"world": {},
	}


## Copies the file we could not read to `save.broken.json` and returns that path; the
## original stays where it is. See `SaveFileStore.quarantine()`.
func _quarantine() -> String:
	return _store.quarantine()
