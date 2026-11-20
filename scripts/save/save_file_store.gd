class_name SaveFileStore
extends RefCounted
## The save file's bytes on disk: verified writes, the swap onto the save path, staged
## copies, recovery of an interrupted swap and quarantine of a file that cannot be read.
##
## Split out of the `Save` autoload (`save_manager.gd`, issue #223), which keeps everything
## that knows what a save *means* - the payload, validation before application, the
## session it is applied to - and all of its public methods. This object knows nothing
## about payloads: it moves bytes and proves where they are.
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
##
## Messages keep the `Save:` prefix: the player and the noise report know this as the save
## system, whichever file the line comes from.

const OfflineDiagnostics := preload("res://scripts/autoload/diagnostics.gd")

const SAVE_PATH := "user://save.json"
## Where an unreadable save is copied before the game starts a new run. Never the
## same file: a bug report needs the bytes that failed.
const BROKEN_PATH := "user://save.broken.json"
## The save's file name, for the temporary, backup and staged files that share it.
const SAVE_BASENAME := "save.json"
## The directory every path above lives in.
const USER_DIR := "user://"
## Every kind of file this store leaves beside the save while it works.
const ALL_STRAY_KINDS: Array = [".tmp", ".bak", ".staged"]


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


## Returns the filesystem to use *now*. `Save` passes a callable rather than an object
## because a test swaps `Save.io` between operations, and the store must follow.
var _fs_source: Callable
var _default_io := FileIO.new()
## Keeps two temporary files written in the same microsecond apart.
var _serial := 0


func _init(fs_source: Callable = Callable()) -> void:
	_fs_source = fs_source


## The filesystem: whatever the owner currently supplies, or the real one.
func fs() -> Variant:
	if _fs_source.is_valid():
		var supplied: Variant = _fs_source.call()
		if supplied != null:
			return supplied
	return _default_io


## A name nothing else in this run will pick: the clock, a counter and a counter of
## swaps, zero-padded so two of them sort in the order they were made.
func new_nonce() -> String:
	_serial += 1
	return "%012d-%03d-%04d" % [Time.get_ticks_usec(), _serial, randi() % 10000]


func has_save() -> bool:
	return fs().exists(SAVE_PATH)


func read_save_bytes() -> PackedByteArray:
	return fs().read_bytes(SAVE_PATH)


# --- Writing ----------------------------------------------------------------


## Writes `bytes` to a fresh temporary file, proves them, then installs them on the save
## path without deleting the previous save first. Returns `{ok, reason, detail, temp_path,
## backup_path, recovery_path, leftovers}`; on success `leftovers` also names what an
## earlier crash left behind and could not be removed. A failure also carries `swapped`:
## false when the temporary file never verified, so the swap was never attempted.
func write_save(bytes: PackedByteArray) -> Dictionary:
	var nonce := new_nonce()
	var temp_path := "%s.%s.tmp" % [SAVE_PATH, nonce]

	# 1. The new save exists as its own file first, and it is proved to hold the bytes
	#    that were meant to be written. `store_string()` returning is not evidence.
	var written := write_verified(temp_path, bytes)
	if not bool(written["ok"]):
		fs().remove(temp_path)
		# `swapped: false`: the existing save was never touched.
		return {
			"ok": false, "swapped": false, "reason": "write", "detail": String(written["detail"]),
			"temp_path": temp_path, "backup_path": "", "recovery_path": "", "leftovers": [],
		}

	# 2. Only now may anything touch the save that is already there.
	var replaced := replace_verified(temp_path, nonce, bytes)
	if not bool(replaced["ok"]):
		fs().remove(temp_path)
		replaced["swapped"] = true
		replaced["temp_path"] = temp_path
		replaced["recovery_path"] = String(replaced.get("recovery_path", ""))
		replaced["backup_path"] = String(replaced.get("backup_path", ""))
		return replaced

	# 3. The swap is done; anything it and an earlier crash left behind is rubbish.
	var leftovers: Array = replaced.get("leftovers", [])
	leftovers.append_array(cleanup_strays([temp_path, String(replaced.get("backup_path", ""))]))
	return {
		"ok": true, "reason": "", "detail": "", "temp_path": temp_path,
		"backup_path": String(replaced.get("backup_path", "")), "recovery_path": "",
		"leftovers": leftovers,
	}


## Writes `bytes` to `path` and reads them back. Returns `{ok, detail}`.
func write_verified(path: String, bytes: PackedByteArray) -> Dictionary:
	var error: int = fs().write_bytes(path, bytes)
	if error != OK:
		return {"ok": false, "detail": "could not write %s (error %d)" % [path, error]}
	var read_back: PackedByteArray = fs().read_bytes(path)
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
func replace_verified(temp_path: String, nonce: String, intended: PackedByteArray) -> Dictionary:
	var io: Variant = fs()
	var had_save: bool = io.exists(SAVE_PATH)
	var previous := PackedByteArray()
	if had_save:
		previous = io.read_bytes(SAVE_PATH)

	var renamed: int = io.rename(temp_path, SAVE_PATH)
	if renamed == OK:
		var straight := expect_bytes(SAVE_PATH, intended)
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
	var moved_aside: int = io.rename(SAVE_PATH, backup_path)
	if moved_aside != OK or not io.exists(backup_path):
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

	var aside := expect_bytes(backup_path, previous)
	if not bool(aside["ok"]):
		# A backup that is not the old save is not a backup: put it back before going on.
		var undo: int = io.rename(backup_path, SAVE_PATH)
		return {
			"ok": false,
			"reason": "write",
			"detail":
			"%s; the previous save was moved back (%s, error %d)"
			% [String(aside["detail"]), SAVE_PATH, undo],
			"recovery_path": SAVE_PATH if io.exists(SAVE_PATH) else backup_path,
			"backup_path": backup_path if io.exists(backup_path) else "",
			"leftovers": [],
		}

	var installed: int = io.rename(temp_path, SAVE_PATH)
	if installed != OK:
		return _put_previous_back(installed, backup_path)

	var installed_bytes := expect_bytes(SAVE_PATH, intended)
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
	var removed: int = io.remove(backup_path)
	if io.exists(backup_path):
		leftovers.append(backup_path)
		push_warning("Save: the backup at %s could not be removed (error %d)."
			% [backup_path, removed])
	return {"ok": true, "reason": "", "detail": "", "backup_path": backup_path, "leftovers": leftovers}


## The new save could not be installed after the old one was moved aside: put the old
## one back, and say where it is if even that failed.
func _put_previous_back(installed: int, backup_path: String) -> Dictionary:
	var io: Variant = fs()
	var put_back: int = io.rename(backup_path, SAVE_PATH)
	if put_back != OK or not io.exists(SAVE_PATH):
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


## True when `path` holds exactly `bytes`; `{ok, detail}` otherwise.
func expect_bytes(path: String, bytes: PackedByteArray) -> Dictionary:
	if not fs().exists(path):
		return {"ok": false, "detail": "%s does not exist" % path}
	var found: PackedByteArray = fs().read_bytes(path)
	if found != bytes:
		return {
			"ok": false,
			"detail":
			"%s holds %d byte(s) that are not the %d that were written"
			% [path, found.size(), bytes.size()],
		}
	return {"ok": true, "detail": ""}


# --- Strays, recovery and staging ---------------------------------------------


## The temporary, backup and staged files this system owns, of the kinds asked for.
##
## The kinds are named because they are not equally disposable: a `.staged` file belongs to
## a new game that may still be running (or to a rollback that could not finish), so an
## ordinary successful write clears temporary and backup files and leaves staged ones
## alone.
func stray_paths(kinds: Array = ALL_STRAY_KINDS) -> PackedStringArray:
	var found := PackedStringArray()
	for name: String in fs().list():
		if not name.begins_with(SAVE_BASENAME + "."):
			continue
		for kind: String in kinds:
			if name.ends_with(kind):
				found.append(USER_DIR + name)
				break
	found.sort()
	return found


## Removes the leftovers of earlier runs, and returns the paths it could not remove.
func cleanup_strays(protected: Array = [], kinds: Array = [".tmp", ".bak"]) -> Array:
	var leftovers: Array = []
	for path: String in stray_paths(kinds):
		if protected.has(path):
			continue
		if not fs().exists(path):
			continue
		fs().remove(path)
		if fs().exists(path):
			leftovers.append(path)
	return leftovers


## Puts back a save left behind as `.bak`/`.staged` by a crash in the middle of a swap.
##
## Only runs when there is no save at all: a save that is there is the truth, and this
## never overwrites it. The caller decides whether recovery may run at all (`Save` refuses
## while a new game owns these files). Returns `{ok, recovered, path}`.
func recover_pending_swap() -> Dictionary:
	var io: Variant = fs()
	if io.exists(SAVE_PATH):
		return {"ok": true, "recovered": false, "path": ""}
	var candidates := stray_paths([".bak", ".staged"])
	var restored := ""
	for index in range(candidates.size() - 1, -1, -1):
		var candidate: String = candidates[index]
		if candidate.ends_with(".tmp"):
			continue
		if io.rename(candidate, SAVE_PATH) == OK and io.exists(SAVE_PATH):
			restored = candidate
			break
	if restored.is_empty():
		return {"ok": true, "recovered": false, "path": ""}
	OfflineDiagnostics.note("save.recovered")
	push_warning("Save: a save interrupted mid-write was put back from %s." % restored)
	return {"ok": true, "recovered": true, "path": restored}


## Moves the save to a unique staged file and proves the move. Returns
## `{ok, staged, staged_path, reason, detail}`.
func stage_save() -> Dictionary:
	var io: Variant = fs()
	if not io.exists(SAVE_PATH):
		return {"ok": true, "staged": false, "staged_path": "", "reason": "", "detail": ""}
	var bytes: PackedByteArray = io.read_bytes(SAVE_PATH)
	var staged_path := "%s.%s.staged" % [SAVE_PATH, new_nonce()]
	var moved: int = io.rename(SAVE_PATH, staged_path)
	if moved != OK or not io.exists(staged_path):
		return {
			"ok": false,
			"staged": false,
			"staged_path": "",
			"reason": "stage",
			"detail": "could not move %s to %s (error %d)" % [SAVE_PATH, staged_path, moved],
		}
	var check := expect_bytes(staged_path, bytes)
	if not bool(check["ok"]):
		io.rename(staged_path, SAVE_PATH)
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
	var io: Variant = fs()
	if staged_path.is_empty() or not io.exists(staged_path):
		return {
			"ok": false,
			"reason": "missing",
			"detail": "there is no staged save at '%s'" % staged_path,
		}
	var bytes: PackedByteArray = io.read_bytes(staged_path)
	if io.rename(staged_path, SAVE_PATH) != OK or not io.exists(SAVE_PATH):
		return {
			"ok": false,
			"reason": "restore",
			"detail": "could not put %s back at %s" % [staged_path, SAVE_PATH],
		}
	var check := expect_bytes(SAVE_PATH, bytes)
	if not bool(check["ok"]):
		return {"ok": false, "reason": "verify", "detail": String(check["detail"])}
	return {"ok": true, "reason": "", "detail": "", "path": SAVE_PATH, "bytes": bytes.size()}


## Removes a staged save, and says whether it is really gone.
func discard_staged(staged_path: String) -> Dictionary:
	if staged_path.is_empty():
		return {"ok": true, "removed": false, "detail": ""}
	var io: Variant = fs()
	if not io.exists(staged_path):
		return {"ok": true, "removed": false, "detail": ""}
	var error: int = io.remove(staged_path)
	if io.exists(staged_path):
		return {
			"ok": false,
			"removed": false,
			"detail": "the staged save at %s could not be removed (error %d)" % [staged_path, error],
		}
	return {"ok": true, "removed": true, "detail": ""}


## Removes every temporary, backup and staged file beside the save. Returns
## `{ok, removed, leftovers}`.
func discard_strays() -> Dictionary:
	var before := stray_paths()
	var leftovers := cleanup_strays([], ALL_STRAY_KINDS)
	var removed: Array = []
	for path: String in before:
		if not leftovers.has(path):
			removed.append(path)
	return {"ok": leftovers.is_empty(), "removed": removed, "leftovers": leftovers}


## Removes `paths` that exist and proves each is gone. Returns `{removed, refused}`, where
## `refused` holds one sentence per file that stayed.
func remove_files(paths: Array) -> Dictionary:
	var io: Variant = fs()
	var removed: Array = []
	var refused: Array = []
	for path: String in paths:
		if not io.exists(path):
			continue
		var error: int = io.remove(path)
		if io.exists(path):
			refused.append("%s could not be removed (error %d)" % [path, error])
		else:
			removed.append(path)
	return {"removed": removed, "refused": refused}


## Copies the file we could not read to `save.broken.json` and returns that path.
## The original stays where it is: nothing this store does may destroy a save.
##
## An existing copy of the *same* bytes is left alone rather than rewritten — a second
## boot must not touch evidence that is already there. A copy of different bytes is
## replaced: this is a single-slot game (ADR 0005), and the file it replaces is still at
## `SAVE_PATH`, unread, so nothing is lost by writing the newer one.
func quarantine() -> String:
	var io: Variant = fs()
	if not io.exists(SAVE_PATH):
		return ""
	var bytes: PackedByteArray = io.read_bytes(SAVE_PATH)
	if bytes.is_empty():
		return ""
	if io.exists(BROKEN_PATH) and io.read_bytes(BROKEN_PATH) == bytes:
		return BROKEN_PATH
	var written := write_verified(BROKEN_PATH, bytes)
	if not bool(written["ok"]):
		OfflineDiagnostics.note("save.quarantine_failed")
		push_error("Save: the unreadable save could not be copied aside: %s"
			% String(written["detail"]))
		return ""
	push_error("Save: the unreadable save was copied to %s." % BROKEN_PATH)
	return BROKEN_PATH
