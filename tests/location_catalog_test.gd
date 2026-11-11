extends SceneTree
## The location catalog is complete, and it is the reason a new room does not need a
## code change.
##
## `data/story/locations.json` moved three things out of `opening_sequence.gd`: which
## room the game starts in, what the objective says when you arrive, and which first
## line a place says about itself. A data file is only better than a `match` if it is
## checked, so this test is the check:
##
## 1. **Every room on disk is in the catalog.** A scene under `scenes/locations/`
##    that nobody described would work but would say nothing about itself; the test
##    refuses it rather than letting the silence become a habit.
## 2. **Every door points at a catalogued room.** An exit naming a destination the
##    catalog has never heard of is the classic typo this replaces.
## 3. **Every objective key and arrival line exists, in every language.** A key that
##    only exists in English is a Chinese player looking at an empty objective line.
## 4. **The loader's own validation passes**, which covers scene paths, the single
##    start location, and flag names that `StoryFlags` actually declares.

const Harness = preload("res://tests/test_harness.gd")

const CATALOG_PATH := "res://data/story/locations.json"
const LOCATION_DIR := "res://scenes/locations"
const LOCALES := ["en", "zh-CN"]
const LOCALE_DIR := "res://data/locale"

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "location_catalog_test.gd")
	call_deferred("_run")


func _run() -> void:
	var catalog := LocationCatalog.load_all()
	if not catalog.is_valid():
		Harness.finish(self, [catalog.describe_errors()], "")
		return

	_check_every_scene_is_described(catalog)
	_check_doors_point_at_described_rooms(catalog)
	_check_objective_keys(catalog)
	_check_arrival_conversations(catalog)

	Harness.finish(
		self, _failures,
		"every location is described, every door leads to a described room, and every key exists in both languages."
	)


func _check_every_scene_is_described(catalog: LocationCatalog) -> void:
	var described := {}
	for location_id: StringName in catalog.get_ids():
		described[catalog.get_entry(location_id).scene] = true

	var dir := DirAccess.open(LOCATION_DIR)
	if dir == null:
		_failures.append("Could not open %s." % LOCATION_DIR)
		return
	for folder in dir.get_directories():
		var scene := "%s/%s/%s.tscn" % [LOCATION_DIR, folder, folder]
		if not FileAccess.file_exists(scene):
			_failures.append("%s has no %s.tscn." % [folder, folder])
			continue
		if not described.has(scene):
			_failures.append(
				"%s exists but is not in %s. Add an entry (or delete the scene)."
				% [scene, CATALOG_PATH]
			)
	print("catalog: %d location(s) described, %d scene folder(s) on disk"
		% [catalog.get_ids().size(), dir.get_directories().size()])


## An exit is the only place a room names another room, so this is where a typo in a
## location id would otherwise sit unnoticed until someone walked through that door.
func _check_doors_point_at_described_rooms(catalog: LocationCatalog) -> void:
	var doors := 0
	for location_id: StringName in catalog.get_ids():
		var scene := catalog.get_entry(location_id).scene
		var text := _file_text(scene)
		if text.is_empty():
			_failures.append("%s could not be read." % scene)
			continue
		for line in text.split("\n"):
			var trimmed := line.strip_edges()
			if not trimmed.begins_with("destination_id = "):
				continue
			doors += 1
			var target := _quoted_value(trimmed)
			if target.is_empty():
				_failures.append("%s has an exit with no destination_id: %s" % [scene, trimmed])
			elif not catalog.has(StringName(target)):
				_failures.append(
					"%s has a door to '%s', which %s does not describe."
					% [scene, target, CATALOG_PATH]
				)
	print("catalog: %d door(s) checked" % doors)


func _check_objective_keys(catalog: LocationCatalog) -> void:
	for locale in LOCALES:
		var strings := _strings(locale)
		if strings.is_empty():
			_failures.append("data/locale/%s.json could not be read." % locale)
			continue
		for location_id: StringName in catalog.get_ids():
			var key := catalog.get_entry(location_id).objective
			if key.is_empty():
				continue
			if not strings.has(key):
				_failures.append(
					"%s: objective '%s' is missing from %s." % [location_id, key, locale]
				)


## The arrival line has to exist in every language, otherwise the parity checker is
## the only thing that would notice, and it only runs on shipped chapters.
func _check_arrival_conversations(catalog: LocationCatalog) -> void:
	var library := DialogueLibrary.load_all()
	if not library.is_valid():
		_failures.append(library.describe_errors())
		return
	for locale in LOCALES:
		library.set_locale(locale)
		for location_id: StringName in catalog.get_ids():
			var conversation := catalog.get_entry(location_id).arrival_conversation
			if String(conversation).is_empty():
				continue
			if not library.has_conversation(conversation):
				_failures.append(
					"%s: arrival conversation '%s' is missing from %s."
					% [location_id, conversation, locale]
				)


func _strings(locale: String) -> Dictionary:
	var text := _file_text("%s/%s.json" % [LOCALE_DIR, locale])
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var strings: Variant = (parsed as Dictionary).get("strings", {})
	return strings if strings is Dictionary else {}


func _quoted_value(line: String) -> String:
	var parts := line.split("\"")
	if parts.size() < 2:
		return ""
	return parts[1].strip_edges()


func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text
