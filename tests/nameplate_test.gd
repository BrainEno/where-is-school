extends SceneTree
## Checks the grey-box name labels: who gets one, what it says, and what it must not do.
##
## The labels exist because the blockout people have no faces. That makes them easy to
## get wrong in ways a screenshot cannot catch, so this script walks the rules:
##
## - the people who exist get exactly one label each, and a person who is not in the
##   scene gets none — a label is not a reason to create a character;
## - the name comes from the character profile and the locale tables, so it follows the
##   language switch and is never a string typed into a script;
## - the label is a `Label3D` with a billboard, no collision, no area, no body: it
##   cannot be walked into, cannot block a click and cannot widen an interaction;
## - it sits above the head, moves with the actor, and leaves no duplicate behind when
##   a scene is loaded twice;
## - the development-only switch turns all of them off in one place.

const Harness = preload("res://tests/test_harness.gd")
const NPC_SCENE := "res://scenes/actors/npc/npc_actor.tscn"
const PLAYER_SCENE := "res://scenes/actors/player/player.tscn"
const CLASSROOM_SCENE := "res://scenes/locations/classroom/classroom.tscn"

var _failures: Array[String] = []
var _loc: Node = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "nameplate_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	if not L10n.errors().is_empty():
		_failures.append("Locale tables reported errors: %s" % " | ".join(L10n.errors()))
	if not L10n.has_key("name.protagonist") or not L10n.has_key("name.q"):
		_failures.append("The locale tables have no name keys for the characters.")
	_loc.set_locale("en")
	CharacterDirectory.reset_cache_for_tests()
	# The labels follow the build type unless a project setting says otherwise. The
	# tests pin them on so the visibility claims do not depend on how CI's engine was
	# compiled, and the fallback is checked at the end.
	ProjectSettings.set_setting(CharacterNameplate.SETTING, true)

	await _check_actor(PLAYER_SCENE, &"protagonist", "protagonist", "You", 1.95)
	await _check_actor(NPC_SCENE, &"q", "q", "Q", 1.92)
	await _check_actor(NPC_SCENE, &"n", "n", "N", 1.92)

	await _check_language_switch()
	await _check_development_switch()
	await _check_no_duplicates()
	await _check_classroom()

	_loc.set_locale("en")
	Harness.finish(
		self,
		_failures,
		"every grey-box person carries one localized, non-physical name label."
	)


## Instances one actor scene, gives it a character, and checks the label it carries.
func _check_actor(
	scene_path: String, character_id: StringName, npc_id: String, name_en: String, height: float
) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_failures.append("%s could not be loaded." % scene_path)
		return
	var actor: Node3D = packed.instantiate()
	if actor is NpcActor:
		(actor as NpcActor).npc_id = StringName(npc_id)
	root.add_child(actor)
	await process_frame
	await process_frame

	var plates := _nameplates(actor)
	if plates.size() != 1:
		_failures.append("%s: found %d name labels, expected 1." % [character_id, plates.size()])
		actor.queue_free()
		return
	var plate := plates[0]
	if plate.character_id != character_id:
		_failures.append(
			"%s: the label is for '%s'." % [character_id, String(plate.character_id)]
		)
	if plate.text != name_en:
		_failures.append("%s: the label reads '%s', expected '%s'." % [character_id, plate.text, name_en])
	if plate.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
		_failures.append("%s: the label does not face the camera." % character_id)
	if not is_equal_approx(plate.position.y, height):
		_failures.append("%s: the label sits at y=%.2f, not above the head." % [character_id, plate.position.y])
	if not plate.visible:
		_failures.append("%s: the label is hidden in a development build." % character_id)
	if _physics_nodes(plate).size() != 0:
		_failures.append("%s: the label contains physics nodes: %s." % [character_id, _physics_nodes(plate)])
	if plate.no_depth_test:
		_failures.append("%s: the label ignores depth and would show through walls." % character_id)

	# It belongs to the actor, not to the world: moving the actor moves the label.
	var offset := plate.global_position - actor.global_position
	actor.global_position += Vector3(2.0, 0.0, 1.0)
	await process_frame
	if (plate.global_position - actor.global_position).distance_to(offset) > 0.01:
		_failures.append("%s: the label did not follow the actor." % character_id)

	actor.queue_free()
	await process_frame


func _check_language_switch() -> void:
	var packed: PackedScene = load(NPC_SCENE)
	var actor: NpcActor = packed.instantiate()
	actor.npc_id = &"q"
	root.add_child(actor)
	await process_frame
	var plate := _nameplates(actor)[0]

	_loc.set_locale("zh-CN")
	await process_frame
	var directory := CharacterDirectory.load_cached()
	if plate.text != directory.get_localized_name(&"q"):
		_failures.append("The label does not use the localized profile name: '%s'." % plate.text)
	# Q is called Q in both languages — a name does not have to change to be correct.
	# The protagonist's does, so that is where "the label follows the language" is
	# actually observable.
	var player: Node3D = load(PLAYER_SCENE).instantiate()
	root.add_child(player)
	await process_frame
	var player_plate := _nameplates(player)[0]
	if not _has_cjk(player_plate.text):
		_failures.append(
			"The protagonist's label stayed English after switching to Chinese: '%s'."
			% player_plate.text
		)
	player.queue_free()
	await process_frame

	_loc.set_locale("en")
	await process_frame
	if plate.text != "Q":
		_failures.append("The label did not return to its English name: '%s'." % plate.text)

	# A character nobody defined must not render a raw id as a name.
	actor.npc_id = &"not_a_character"
	plate.character_id = &"not_a_character"
	plate.refresh()
	if not plate.text.is_empty():
		_failures.append("An unknown character produced a label: '%s'." % plate.text)
	actor.queue_free()
	await process_frame


func _check_development_switch() -> void:
	var packed: PackedScene = load(NPC_SCENE)
	var actor: NpcActor = packed.instantiate()
	actor.npc_id = &"n"
	root.add_child(actor)
	await process_frame
	var plate := _nameplates(actor)[0]
	if not plate.visible:
		_failures.append("The label is not visible before the switch is touched.")

	ProjectSettings.set_setting(CharacterNameplate.SETTING, false)
	plate.refresh()
	if plate.visible:
		_failures.append("The project switch did not hide the label.")
	ProjectSettings.set_setting(CharacterNameplate.SETTING, true)
	plate.refresh()
	if not plate.visible:
		_failures.append("The project switch did not show the label again.")

	# The scene-level switch is independent of the project one.
	plate.show_in_development = false
	plate.refresh()
	if plate.visible:
		_failures.append("The scene-level switch did not hide the label.")
	plate.show_in_development = true
	plate.refresh()

	ProjectSettings.set_setting(CharacterNameplate.SETTING, null)
	if ProjectSettings.has_setting(CharacterNameplate.SETTING):
		_failures.append("The test could not remove the project override.")
	plate.refresh()
	if plate.visible != OS.is_debug_build():
		_failures.append(
			"Without an override the label should follow the build type (debug=%s)."
			% str(OS.is_debug_build())
		)
	actor.queue_free()
	await process_frame


func _check_no_duplicates() -> void:
	# Two instances of the classroom would duplicate everyone; the labels must stay one
	# per actor, and freeing an actor must take its label with it.
	var packed: PackedScene = load(NPC_SCENE)
	var actors: Array[NpcActor] = []
	for index in 3:
		var actor: NpcActor = packed.instantiate()
		actor.npc_id = &"q"
		root.add_child(actor)
		actors.append(actor)
	await process_frame
	await process_frame
	for index in actors.size():
		if _nameplates(actors[index]).size() != 1:
			_failures.append("Actor %d has %d labels." % [index, _nameplates(actors[index]).size()])
	if _nameplates(root).size() < 3:
		_failures.append("The three actors do not add up to three labels in the tree.")
	actors[0].queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(actors[1]) and _nameplates(actors[1]).size() != 1:
		_failures.append("Freeing one actor disturbed another actor's label.")
	for actor in actors:
		if is_instance_valid(actor):
			actor.queue_free()
	await process_frame


## The classroom is the scene the game actually starts in: Q and N exist, B does not,
## and no label was created for someone who is not there.
func _check_classroom() -> void:
	var packed: PackedScene = load(CLASSROOM_SCENE)
	if packed == null:
		_failures.append("%s could not be loaded." % CLASSROOM_SCENE)
		return
	var classroom: Node3D = packed.instantiate()
	root.add_child(classroom)
	await process_frame
	await process_frame

	var actors: Node = classroom.get_node_or_null("Actors")
	if actors == null:
		_failures.append("The classroom has no Actors node.")
		classroom.queue_free()
		return
	for required: String in ["Q", "N"]:
		var actor: Node = actors.get_node_or_null(required)
		if actor == null:
			_failures.append("The classroom is missing '%s'." % required)
			continue
		var plates := _nameplates(actor)
		if plates.size() != 1:
			_failures.append("Classroom %s has %d name labels." % [required, plates.size()])
		elif plates[0].text != required:
			_failures.append("Classroom %s is labelled '%s'." % [required, plates[0].text])
	if actors.get_node_or_null("B") != null:
		_failures.append("A character was added to the classroom just to label them.")
	var every_plate := _nameplates(classroom)
	if every_plate.size() < 2:
		_failures.append("The classroom holds only %d labels." % every_plate.size())
	for plate in every_plate:
		if _physics_nodes(plate).size() != 0:
			_failures.append("A classroom label contains physics nodes.")

	classroom.queue_free()
	await process_frame


func _nameplates(node: Node) -> Array[CharacterNameplate]:
	var found: Array[CharacterNameplate] = []
	if node is CharacterNameplate:
		found.append(node as CharacterNameplate)
	for child in node.get_children():
		found.append_array(_nameplates(child))
	return found


func _physics_nodes(node: Node) -> Array[String]:
	var found: Array[String] = []
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		found.append(String(node.name))
	for child in node.get_children():
		found.append_array(_physics_nodes(child))
	return found


func _has_cjk(text: String) -> bool:
	for index in text.length():
		var code := text.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			return true
	return false
