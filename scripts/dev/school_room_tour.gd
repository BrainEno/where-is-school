extends Node
## F6 this scene to walk the actual teaching block before solving its gates.
## Everything here is excluded from export. No production script opts in.

const WORLD := preload("res://scenes/main/main.tscn")
const HALL := "res://scenes/locations/corridor/corridor.tscn"
const ROOMS := [&"archive", &"plan_room", &"projection_room", &"computer_room",
	&"vacant_office", &"principal_office"]


# SaveManager already routes its filesystem work through this seam. Even an
# explicit checkpoint cannot see, recover, quarantine or overwrite a real save.
class NoStoryFiles:
	func exists(_path: String) -> bool:
		return false

	func read_bytes(_path: String) -> PackedByteArray:
		return PackedByteArray()

	func write_bytes(_path: String, _data: PackedByteArray) -> int:
		return ERR_UNAVAILABLE

	func rename(_from: String, _to: String) -> int:
		return ERR_UNAVAILABLE

	func remove(_path: String) -> int:
		return ERR_UNAVAILABLE

	func list() -> PackedStringArray:
		return PackedStringArray()


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	var save := get_node(^"/root/Save")
	save.io = NoStoryFiles.new()
	save.suspend_writes(true)
	var world := WORLD.instantiate()
	var director := world.get_node(^"OpeningSequence") as OpeningSequence
	director.autostart = false
	director.autosave_enabled = false
	var host := world.get_node(^"LocationHost") as LocationHost
	host.location_entered.connect(_prepare_doors)
	add_child(world)
	# Do not offer the production session's destructive commands in a tour.
	var pause := world.get_node(^"PauseMenu") as PauseMenu
	pause.get_entry(&"new_game").hide()
	pause.get_entry(&"save_quit").hide()
	world.get_node(^"InnerVoiceDirector").set_process(false)

	# Main still mounts its default classroom with autostart off. Let that room's
	# deferred nav bake and chair binding run before the host detaches it.
	await get_tree().process_frame
	var player := world.get_node(^"Player") as PlayerController
	player.set_wake_pose(0.0)
	player.set_camera_roll(0.0)
	if not host.load_location(HALL, &"FromTeachingEntrance", player, &"corridor"):
		push_error("School room tour: the real teaching entrance could not be loaded.")
		return
	get_node(^"/root/GameState").set_flag(StoryFlags.CURRENT_LOCATION, &"corridor")
	(world.get_node(^"GameUI") as GameUI).fade.set_clear()
	director.allow_player_control()


func _prepare_doors(location: LocationRoot, _spawn: StringName) -> void:
	if location.location_id != &"corridor":
		return
	for id: StringName in ROOMS:
		var door := location.find_interactable(StringName("to_" + String(id))) as LocationExit
		var slide := location.find_interactable(StringName("align_" + String(id)))
		if door == null or slide == null or door.required_flag != StringName("annex.%s.aligned" % id):
			push_error("School room tour: missing fitted threshold for %s." % id)
			continue
		# Only these instantiated exits are changed, each time the real hall
		# reloads. Nothing writes a seen/check/aligned flag or changes a return.
		door.required_flag = &""
		slide.interaction_enabled = false
