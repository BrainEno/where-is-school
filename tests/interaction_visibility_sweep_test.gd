extends SceneTree
## Every interactable in every authored location is visible from somewhere.
##
## `interaction_occlusion_test.gd` proves that walls block and that declared support
## structure is looked through. The risk of a rule that strict is the opposite failure:
## a real prop quietly becomes unusable because some collider nobody thought about now
## counts as a wall. This test is the guard against that.
##
## It builds each location scene on its own, strips its navigation region (this is a
## question about physics rays, not about walking), and asks the same visibility question
## the game asks, from a ring of standing positions around every interactable. A prop that
## is visible from nowhere gets named, together with the first surface the probe meets, so
## the fix is "declare this support" rather than "loosen the rule".

const Harness = preload("res://tests/test_harness.gd")

const LOCATIONS := [
	"res://scenes/locations/classroom/classroom.tscn",
	"res://scenes/locations/corridor/corridor.tscn",
	"res://scenes/locations/street/street.tscn",
	"res://scenes/locations/playground/playground.tscn",
	"res://scenes/locations/residential/residential.tscn",
	"res://scenes/locations/alley/alley.tscn",
]

var _failures: Array[String] = []
var _main: Node = null
var _player: PlayerController = null
var _interaction: InteractionController = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 200.0, "interaction_visibility_sweep_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null or autoloads["narrative_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence_node := _main.get_node_or_null("OpeningSequence")
	if sequence_node != null:
		sequence_node.set("autostart", false)
	root.add_child(_main)
	await process_frame
	await process_frame
	_player = _main.get_node_or_null("Player") as PlayerController
	if _player != null:
		_interaction = _player.get_node_or_null("InteractionController") as InteractionController
	if _player == null or _interaction == null:
		Harness.finish(self, ["Main did not expose the nodes this test needs."], "")
		return
	Engine.time_scale = 4.0
	await _physics_frames(2)

	var container := Node3D.new()
	container.name = "VisibilitySweep"
	root.add_child(container)
	var total := 0
	for path: String in LOCATIONS:
		var packed_location: PackedScene = load(path)
		if packed_location == null:
			_failures.append("Could not load %s." % path)
			continue
		var location := packed_location.instantiate() as LocationRoot
		if location == null:
			_failures.append("%s is not a LocationRoot." % path)
			continue
		# Physics only. The navigation region would bake on entering the tree, and this
		# test has no question about walking.
		var nav := location.get_node_or_null("Navigation")
		if nav != null:
			location.remove_child(nav)
			nav.queue_free()
		container.add_child(location)
		await _physics_frames(3)
		var seen := 0
		var hidden: Array[String] = []
		for interactable: Interactable in location.get_interactables():
			if not is_instance_valid(interactable):
				continue
			seen += 1
			total += 1
			if not _has_any_clear_view(interactable):
				hidden.append(
					"%s (%s)" % [String(interactable.interact_id), _blocker_of(interactable)]
				)
		if hidden.is_empty():
			print("SWEEP %s: %d interactable(s), all visible from somewhere." % [
				String(location.location_id), seen
			])
		else:
			for entry: String in hidden:
				_failures.append(
					"%s: '%s' cannot be seen from any standing position next to it."
					% [String(location.location_id), entry]
				)
		container.remove_child(location)
		location.queue_free()
		await _physics_frames(2)

	container.queue_free()
	Harness.finish(
		self, _failures,
		"all %d authored interactables are visible from at least one standing position." % total
	)


## Any ring position at one of three eye heights with a clear view of the object.
func _has_any_clear_view(interactable: Interactable) -> bool:
	var centre := interactable.global_position
	var radius := clampf(maxf(interactable.radius, 0.6), 0.6, 2.0)
	for height: float in [1.1, 0.6, 1.6]:
		for index in 16:
			var angle := TAU * float(index) / 16.0
			var eye := centre + Vector3(
				cos(angle) * radius, height - 0.6, sin(angle) * radius
			)
			if _interaction.has_line_of_sight_from(eye, interactable):
				return true
	return false


## The first thing a ray towards the object meets, named. A report that says which
## collider is in the way is a report that can be acted on.
func _blocker_of(interactable: Interactable) -> String:
	var space := _player.get_world_3d().direct_space_state
	var centre := interactable.global_position
	var from := centre + Vector3(0.0, 0.5, -1.5)
	var query := PhysicsRayQueryParameters3D.create(from, centre + Vector3.UP * 0.35, 1)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return "the probe met nothing; the target may be out of reach of every ring spot"
	var collider := hit.get("collider") as Node
	return "first hit: %s" % (String(collider.get_path()) if collider != null else "?")


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
