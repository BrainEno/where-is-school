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
## **What the write path promises, and what it does not.** A save is written to a unique
## temporary file, read back and compared byte for byte, and only then moved onto the save
## path. Where a platform refuses to rename onto an existing file, the old save is moved
## aside to a unique backup and proved to still hold its bytes *before* anything takes its
## place, and it is moved back if the new file cannot be installed. A crash in the middle
## of that swap leaves the old save as a `.bak`, which `recover_pending_swap()` puts back
## on the next read, so a half-finished replacement does not cost the player their run.
##
## This is **not** compare-and-swap and it is not claimed to be: ordinary Godot file APIs
## give `rename`/`remove`, not an atomic exchange, and the guarantees differ per platform
## and filesystem. What is guaranteed here is narrower and checkable: the old save is never
## deleted before a verified copy of it exists, every write is verified by reading it back,
## and every failure leaves either the previous save or a recovery path that is named in
## the result and in the log.

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
## The save's file name, for the temporary, backup and staged files that share it.
const SAVE_BASENAME := "save.json"
## The directory every path above lives in.
const USER_DIR := "user://"


## Every filesystem operation the save system performs, in one object.
##
## Production never replaces it. It exists so a test can make exactly one operation fail -
## a write, a rename, a removal - and observe what the writer does about it. A disk cannot
## be asked to fail on demand, and the failure being guarded against here only happens
## halfway through, so without this seam those paths would be untested prose.
class FileIO:
	func exists(path: String) -> bool:
		return FileAccess.file_exists(path)

	func read_bytes(path: String) -> PackedByteArray:
		return FileAccess.get_file_as_bytes(path)

	func write_bytes(path: String, data: PackedByteArray) -> int:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return FileAccess.get_open_error()
		file.store_buffer(data)
		var error := file.get_error()
		file.close()
		return error

	func rename(from: String, to: String) -> int:
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return DirAccess.get_open_error()
		return dir.rename(from, to)

	func remove(path: String) -> int:
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return DirAccess.get_open_error()
		return dir.remove(path)

	## The file names sitting directly in `user://`, without their directory.
	func list() -> PackedStringArray:
		var dir := DirAccess.open(USER_DIR)
		if dir == null:
			return PackedStringArray()
		return dir.get_files()

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

## Replaces `FileIO` for a test. Null means the real filesystem. Untyped on purpose: the
## six calls are made dynamically, so a test's stand-in does not have to share a base class
## with the real one.
var io: Variant = null
var _default_io := FileIO.new()

## Set while a new game is being prepared: the old world must not be able to put a
## checkpoint back on disk between the save being taken away and the new run starting.
var _writes_suspended := false
## Keeps two temporary files written in the same microsecond apart.
var _serial := 0


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
	return _fs().exists(SAVE_PATH)


## The filesystem this node uses: the real one, or the test's.
func _fs() -> Variant:
	return io if io != null else _default_io


## A name nothing else in this run will pick: the clock, a counter and a counter of
## swaps, zero-padded so two of them sort in the order they were made.
func _new_nonce() -> String:
	_serial += 1
	return "%012d-%03d-%04d" % [Time.get_ticks_usec(), _serial, randi() % 10000]


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
	var bytes := text.to_utf8_buffer()
	var nonce := _new_nonce()
	var temp_path := "%s.%s.tmp" % [SAVE_PATH, nonce]

	# 1. The new save exists as its own file first, and it is proved to hold the bytes
	#    that were meant to be written. `store_string()` returning is not evidence.
	var written := _write_verified(temp_path, bytes)
	if not bool(written["ok"]):
		_fs().remove(temp_path)
		return _record_failure("write", String(written["detail"]))

	# 2. Only now may anything touch the save that is already there.
	var replaced := _replace_verified(temp_path, nonce, bytes)
	if not bool(replaced["ok"]):
		_fs().remove(temp_path)
		var failed := _record_failure(String(replaced["reason"]), String(replaced["detail"]))
		failed["recovery_path"] = String(replaced.get("recovery_path", ""))
		failed["backup_path"] = String(replaced.get("backup_path", ""))
		failed["leftovers"] = replaced.get("leftovers", [])
		_last_result = failed
		return failed.duplicate(true)

	# 3. The swap is done; anything it and an earlier crash left behind is rubbish.
	var leftovers: Array = replaced.get("leftovers", [])
	leftovers.append_array(_cleanup_strays([temp_path, String(replaced.get("backup_path", ""))]))
	if not leftovers.is_empty():
		push_warning("Save: a save was written but %d file(s) could not be cleaned up: %s"
			% [leftovers.size(), ", ".join(leftovers)])

	saves_written += 1
	_last_result = {
		"ok": true,
		"reason": "",
		"detail": "",
		"path": SAVE_PATH,
		"temp_path": temp_path,
		"backup_path": String(replaced.get("backup_path", "")),
		"recovery_path": "",
		"leftovers": leftovers,
		"rejected": [],
		"quarantined_to": "",
		"version": SaveCodec.VERSION,
	}
	save_written.emit(SAVE_PATH)
	return _last_result.duplicate(true)


## Writes `bytes` to `path` and reads them back. Returns `{ok, detail}`.
func _write_verified(path: String, bytes: PackedByteArray) -> Dictionary:
	var error: int = _fs().write_bytes(path, bytes)
	if error != OK:
		return {"ok": false, "detail": "could not write %s (error %d)" % [path, error]}
	var read_back: PackedByteArray = _fs().read_bytes(path)
	if read_back.size() != bytes.size():
		return {
			"ok": false,
			"detail":
			"%s accepted %d byte(s) and reads back %d; the write did not land"
			% [path, bytes.size(), read_back.size()],
		}
	if read_back != bytes:
		return {"ok": false, "detail": "%s does not hold the bytes that were written" % path}
	return {"ok": true, "detail": ""}


## Moves the verified temporary file onto the save path without ever deleting the save
## that is already there. Returns `{ok, reason, detail, backup_path, recovery_path,
## leftovers}`.
func _replace_verified(temp_path: String, nonce: String, intended: PackedByteArray) -> Dictionary:
	var fs := _fs()
	var had_save: bool = fs.exists(SAVE_PATH)
	var previous := PackedByteArray()
	if had_save:
		previous = fs.read_bytes(SAVE_PATH)

	var renamed: int = fs.rename(temp_path, SAVE_PATH)
	if renamed == OK:
		var straight := _expect_bytes(SAVE_PATH, intended)
		if bool(straight["ok"]):
			return {"ok": true, "reason": "", "detail": "", "backup_path": "", "leftovers": []}
		# The move reported success and the file is not what was written: keep whatever is
		# there, say so, and do not pretend the save was replaced.
		return {
			"ok": false,
			"reason": "verify",
			"detail": String(straight["detail"]),
			"backup_path": "",
			"recovery_path": SAVE_PATH,
			"leftovers": [],
		}

	# Some platforms refuse to rename onto a file that exists. The fallback moves the old
	# save aside first and keeps it there, verified, until the new one is in place — the
	# player's only copy is never deleted to make room.
	if not had_save:
		return {
			"ok": false,
			"reason": "write",
			"detail": "could not move %s onto %s (error %d)" % [temp_path, SAVE_PATH, renamed],
			"recovery_path": "",
			"leftovers": [],
		}

	var backup_path := "%s.%s.bak" % [SAVE_PATH, nonce]
	var moved_aside: int = fs.rename(SAVE_PATH, backup_path)
	if moved_aside != OK or not fs.exists(backup_path):
		# Nothing was replaced: the save is where it was.
		return {
			"ok": false,
			"reason": "write",
			"detail":
			"could not move the previous save aside to %s (error %d); %s is untouched"
			% [backup_path, moved_aside, SAVE_PATH],
			"recovery_path": SAVE_PATH,
			"leftovers": [],
		}

	var aside := _expect_bytes(backup_path, previous)
	if not bool(aside["ok"]):
		# A backup that is not the old save is not a backup: put it back before going on.
		var undo: int = fs.rename(backup_path, SAVE_PATH)
		return {
			"ok": false,
			"reason": "write",
			"detail":
			"%s; the previous save was moved back (%s, error %d)"
			% [String(aside["detail"]), SAVE_PATH, undo],
			"recovery_path": SAVE_PATH if fs.exists(SAVE_PATH) else backup_path,
			"backup_path": backup_path if fs.exists(backup_path) else "",
			"leftovers": [],
		}

	var installed: int = fs.rename(temp_path, SAVE_PATH)
	if installed != OK:
		var put_back: int = fs.rename(backup_path, SAVE_PATH)
		if put_back != OK or not fs.exists(SAVE_PATH):
			return {
				"ok": false,
				"reason": "write",
				"detail":
				(
					"could not install the new save (error %d) and could not put the previous "
					+ "one back (error %d); the previous save is at %s"
				) % [installed, put_back, backup_path],
				"recovery_path": backup_path,
				"backup_path": backup_path,
				"leftovers": [backup_path],
			}
		return {
			"ok": false,
			"reason": "write",
			"detail":
			"could not install the new save (error %d); the previous save was put back at %s"
			% [installed, SAVE_PATH],
			"recovery_path": SAVE_PATH,
			"backup_path": "",
			"leftovers": [],
		}

	var installed_bytes := _expect_bytes(SAVE_PATH, intended)
	if not bool(installed_bytes["ok"]):
		return {
			"ok": false,
			"reason": "verify",
			"detail": String(installed_bytes["detail"]),
			"recovery_path": backup_path,
			"backup_path": backup_path,
			"leftovers": [],
		}

	# The new save is in place; the backup has done its job. A backup that will not go away
	# is reported rather than fatal — the file that matters is the one just verified.
	var leftovers: Array = []
	var removed: int = fs.remove(backup_path)
	if fs.exists(backup_path):
		leftovers.append(backup_path)
		push_warning("Save: the backup at %s could not be removed (error %d)."
			% [backup_path, removed])
	return {"ok": true, "reason": "", "detail": "", "backup_path": backup_path, "leftovers": leftovers}


## True when `path` holds exactly `bytes`; `{ok, detail}` otherwise.
func _expect_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	if not _fs().exists(path):
		return {"ok": false, "detail": "%s does not exist" % path}
	var found: PackedByteArray = _fs().read_bytes(path)
	if found != bytes:
		return {
			"ok": false,
			"detail":
			"%s holds %d byte(s) that are not the %d that were written"
			% [path, found.size(), bytes.size()],
		}
	return {"ok": true, "detail": ""}


## The temporary, backup and staged files this system owns, of the kinds asked for.
##
## The kinds are named because they are not equally disposable: a `.staged` file belongs to
## a new game that may still be running (or to a rollback that could not finish), so an
## ordinary successful write clears temporary and backup files and leaves staged ones
## alone.
func _stray_paths(kinds: Array = [".tmp", ".bak", ".staged"]) -> PackedStringArray:
	var found := PackedStringArray()
	for name: String in _fs().list():
		if not name.begins_with(SAVE_BASENAME + "."):
			continue
		for kind: String in kinds:
			if name.ends_with(kind):
				found.append(USER_DIR + name)
				break
	found.sort()
	return found


## Removes the leftovers of earlier runs, and returns the paths it could not remove.
func _cleanup_strays(protected: Array = [], kinds: Array = [".tmp", ".bak"]) -> Array:
	var leftovers: Array = []
	for path: String in _stray_paths(kinds):
		if protected.has(path):
			continue
		if not _fs().exists(path):
			continue
		_fs().remove(path)
		if _fs().exists(path):
			leftovers.append(path)
	return leftovers


## Puts back a save left behind as `.bak`/`.staged` by a crash in the middle of a swap.
##
## Only runs when there is no save at all: a save that is there is the truth, and this
## never overwrites it. Returns `{ok, recovered, path}`.
func recover_pending_swap() -> Dictionary:
	var fs := _fs()
	# A new game owns these files while it runs: one of its staged copies is *supposed* to
	# be the only copy for a moment, and putting it back here would undo the very thing it
	# is doing.
	if _writes_suspended:
		return {"ok": true, "recovered": false, "path": ""}
	if fs.exists(SAVE_PATH):
		return {"ok": true, "recovered": false, "path": ""}
	var candidates := _stray_paths([".bak", ".staged"])
	var restored := ""
	for index in range(candidates.size() - 1, -1, -1):
		var candidate: String = candidates[index]
		if candidate.ends_with(".tmp"):
			continue
		if fs.rename(candidate, SAVE_PATH) == OK and fs.exists(SAVE_PATH):
			restored = candidate
			break
	if restored.is_empty():
		return {"ok": true, "recovered": false, "path": ""}
	push_warning("Save: a save interrupted mid-write was put back from %s." % restored)
	return {"ok": true, "recovered": true, "path": restored}


## Moves the save to a unique staged file and proves the move, so a caller that is about
## to start a new game holds a recoverable copy until it commits. The save path is empty
## afterwards, which is what "start fresh" means.
##
## Returns `{ok, staged, staged_path, reason, detail}`.
func stage_save() -> Dictionary:
	var fs := _fs()
	if not fs.exists(SAVE_PATH):
		return {"ok": true, "staged": false, "staged_path": "", "reason": "", "detail": ""}
	var bytes := fs.read_bytes(SAVE_PATH)
	var staged_path := "%s.%s.staged" % [SAVE_PATH, _new_nonce()]
	var moved: int = fs.rename(SAVE_PATH, staged_path)
	if moved != OK or not fs.exists(staged_path):
		return {
			"ok": false,
			"staged": false,
			"staged_path": "",
			"reason": "stage",
			"detail": "could not move %s to %s (error %d)" % [SAVE_PATH, staged_path, moved],
		}
	var check := _expect_bytes(staged_path, bytes)
	if not bool(check["ok"]):
		fs.rename(staged_path, SAVE_PATH)
		return {
			"ok": false,
			"staged": false,
			"staged_path": "",
			"reason": "stage",
			"detail": String(check["detail"]),
		}
	return {"ok": true, "staged": true, "staged_path": staged_path, "reason": "", "detail": ""}


## Puts a staged save back where the game reads it, and proves the bytes arrived.
func restore_staged(staged_path: String) -> Dictionary:
	var fs := _fs()
	if staged_path.is_empty() or not fs.exists(staged_path):
		return {
			"ok": false,
			"reason": "missing",
			"detail": "there is no staged save at '%s'" % staged_path,
		}
	var bytes := fs.read_bytes(staged_path)
	if fs.rename(staged_path, SAVE_PATH) != OK or not fs.exists(SAVE_PATH):
		return {
			"ok": false,
			"reason": "restore",
			"detail": "could not put %s back at %s" % [staged_path, SAVE_PATH],
		}
	var check := _expect_bytes(SAVE_PATH, bytes)
	if not bool(check["ok"]):
		return {"ok": false, "reason": "verify", "detail": String(check["detail"])}
	return {"ok": true, "reason": "", "detail": "", "path": SAVE_PATH, "bytes": bytes.size()}


## Removes a staged save, and says whether it is really gone.
func discard_staged(staged_path: String) -> Dictionary:
	if staged_path.is_empty():
		return {"ok": true, "removed": false, "detail": ""}
	var fs := _fs()
	if not fs.exists(staged_path):
		return {"ok": true, "removed": false, "detail": ""}
	var error: int = fs.remove(staged_path)
	if fs.exists(staged_path):
		return {
			"ok": false,
			"removed": false,
			"detail": "the staged save at %s could not be removed (error %d)" % [staged_path, error],
		}
	return {"ok": true, "removed": true, "detail": ""}


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
	if not _fs().exists(SAVE_PATH):
		var missing := _refuse("missing_file", "there is no save at %s" % SAVE_PATH)
		missing["payload"] = {}
		return missing

	var bytes: PackedByteArray = _fs().read_bytes(SAVE_PATH)
	if bytes.is_empty():
		var unreadable := _refuse(
			"unreadable", "could not read %s (%d byte(s))" % [SAVE_PATH, bytes.size()]
		)
		unreadable["payload"] = {}
		unreadable["quarantined_to"] = _quarantine()
		return unreadable
	var text := bytes.get_string_from_utf8()

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


## Deletes the save file and proves it is gone. Returns
## `{ok, reason, detail, removed, leftovers}`.
##
## The quarantined copy of an unreadable save is **not** removed: it is the player's only
## copy of a file this build could not read, and the point of writing it aside is that it
## outlives the run that could not open it. `{"broken": true}` removes it too, which is
## what test hygiene wants and what a new game must not do.
func delete_save(options: Dictionary = {}) -> Dictionary:
	var remove_broken := bool(options.get("broken", false))
	var fs := _fs()
	var removed: Array = []
	var refused: Array = []
	var targets: Array = [SAVE_PATH, BROKEN_PATH] if remove_broken else [SAVE_PATH]
	for path: String in targets:
		if not fs.exists(path):
			continue
		var error: int = fs.remove(path)
		if fs.exists(path):
			refused.append("%s could not be removed (error %d)" % [path, error])
		else:
			removed.append(path)
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
	_cleanup_strays([], [".tmp", ".bak", ".staged"])
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
		"temp_path": "",
		"backup_path": "",
		"recovery_path": "",
		"leftovers": [],
		"rejected": [],
		"quarantined_to": "",
		"version": 0,
		"world": {},
	}


## Copies the file we could not read to `save.broken.json` and returns that path.
## The original stays where it is: nothing this node does may destroy a save.
##
## An existing copy of the *same* bytes is left alone rather than rewritten — a second
## boot must not touch evidence that is already there. A copy of different bytes is
## replaced: this is a single-slot game (ADR 0005), and the file it replaces is still at
## `SAVE_PATH`, unread, so nothing is lost by writing the newer one.
func _quarantine() -> String:
	if not _fs().exists(SAVE_PATH):
		return ""
	var bytes: PackedByteArray = _fs().read_bytes(SAVE_PATH)
	if bytes.is_empty():
		return ""
	if _fs().exists(BROKEN_PATH) and _fs().read_bytes(BROKEN_PATH) == bytes:
		return BROKEN_PATH
	var written := _write_verified(BROKEN_PATH, bytes)
	if not bool(written["ok"]):
		push_error("Save: the unreadable save could not be copied aside: %s"
			% String(written["detail"]))
		return ""
	push_error("Save: the unreadable save was copied to %s." % BROKEN_PATH)
	return BROKEN_PATH
