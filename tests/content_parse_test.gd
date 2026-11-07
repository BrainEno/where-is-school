extends SceneTree
## Loads every script, scene and resource in the project and reports the ones that
## do not parse.
##
## `godot --headless --editor --quit` imports assets but does not compile every
## GDScript file it walks past: a file with a syntax error can sit in the tree and
## the editor pass still exits 0. This test is the actual parse gate. It loads each
## resource through the real loader (which parses scripts and scene files) and
## fails on anything that comes back as null, naming the file.
##
## Loading is not running: no `_ready` is called, no autoload is touched, and the
## main scene is never instantiated. So a project whose scripts are fine but whose
## content is temporarily broken still reports the parse problem only.

const Harness = preload("res://tests/test_harness.gd")
## Directories that hold engine cache, imported binaries or third-party addons.
const SKIP_DIRS: Array[String] = [".godot", ".git", "addons", "docs"]
const CHECKED_EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]

var _failures: Array[String] = []
var _checked := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "content_parse_test.gd")
	call_deferred("_run")


func _run() -> void:
	for path: String in _collect("res://"):
		_load_one(path)
	if _checked == 0:
		_failures.append("No scripts or resources were found to check; the walker is broken.")
	Harness.finish(
		self,
		_failures,
		"%d script/scene/resource file(s) parsed." % _checked
	)


func _collect(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_failures.append("Could not open directory %s." % dir_path)
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not SKIP_DIRS.has(entry):
				found.append_array(_collect(full))
		else:
			var extension := entry.get_extension().to_lower()
			if CHECKED_EXTENSIONS.has(extension):
				found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _load_one(path: String) -> void:
	_checked += 1
	# CACHE_MODE_IGNORE forces a real parse instead of returning a cached handle.
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		_failures.append("%s did not load (parse error or missing dependency)." % path)
		return
	if path.get_extension() == "gd":
		var script := resource as Script
		if script == null:
			_failures.append("%s is not a Script resource." % path)
			return
		# A script that parses but cannot be instantiated is still unusable.
		if script.get_instance_base_type() == &"":
			_failures.append("%s has no base type; it probably failed to parse." % path)
