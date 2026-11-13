extends SceneTree
## Every interactable the game ships is highlighted by an outline of something the player
## can see, and nothing authored can be mistaken for an outline.
##
## `tests/interaction_cue_test.gd` proves the outline machinery on synthetic props. This test
## asks the shipped content the questions that machinery depends on:
##
## 1. every interactable in every location (and the companion's "ask along") resolves at
##    least one visible mesh to trace - so the fallback diamond is never what a player sees,
##    and an `outline_paths` entry that stopped resolving after a scene edit is caught here
##    instead of as a silent fallback in a playtest;
## 2. every authored support path resolves, so line-of-sight checks can look through the
##    actual frame or stair geometry attached to an exit instead of losing the target;
## 3. every outlined object can be pointed at where it is drawn: each outline mesh that
##    qualifies (`Interactable.gets_pick_box`) has a pick box; objects that are only floor
##    paint or longer than a pick box are listed in the log as anchor-only;
## 4. no shipped mesh is authored on `OutlineOverlay.MASK_LAYER`. The overlay renders that
##    layer and nothing else into its silhouette mask; a prop authored on it would be
##    outlined all the time;
## 5. the overlay in the main scene sits under the UI, so an outline never draws over a
##    dialogue box.

const Harness = preload("res://tests/test_harness.gd")

const LOCATIONS := [
	"res://scenes/locations/classroom/classroom.tscn",
	"res://scenes/locations/corridor/corridor.tscn",
	"res://scenes/locations/street/street.tscn",
	"res://scenes/locations/residential/residential.tscn",
	"res://scenes/locations/alley/alley.tscn",
	"res://scenes/locations/playground/playground.tscn",
]

var _failures: Array[String] = []
var _main: Node = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "interaction_outline_content_test.gd")
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
	await _physics_frames(4)

	Harness.stage = "main scene"
	_check_overlay_under_ui()
	_check_no_mask_layer(_main, "main")
	var ask_along := _main.get_node_or_null("Companion/AskAlong") as Interactable
	if ask_along == null:
		_failures.append("main: the companion's AskAlong interactable is missing.")
	else:
		# Q has not joined at boot, so the companion is hidden and has nothing visible to
		# trace. Shown, it must trace its model, and its pick boxes must follow the change
		# of visibility rather than staying as they were measured at boot.
		var companion := _main.get_node_or_null("Companion") as Node3D
		var was_visible := companion.visible if companion != null else true
		if companion != null:
			companion.visible = true
		await process_frame
		await process_frame
		_check_interactable(ask_along, "main")
		if companion != null:
			companion.visible = was_visible
		await process_frame

	var container := Node3D.new()
	container.name = "OutlineContent"
	root.add_child(container)
	var total := 0
	for path: String in LOCATIONS:
		Harness.stage = path.get_file()
		var packed_location: PackedScene = load(path)
		if packed_location == null:
			_failures.append("Could not load %s." % path)
			continue
		var location := packed_location.instantiate() as LocationRoot
		if location == null:
			_failures.append("%s is not a LocationRoot." % path)
			continue
		# Outlines are a question about meshes and physics shapes, not about walking.
		var nav := location.get_node_or_null("Navigation")
		if nav != null:
			location.remove_child(nav)
			nav.queue_free()
		container.add_child(location)
		await _physics_frames(3)
		var label := String(location.location_id)
		_check_no_mask_layer(location, label)
		var count := 0
		for interactable: Interactable in location.get_interactables():
			if not is_instance_valid(interactable):
				continue
			count += 1
			total += 1
			_check_interactable(interactable, label)
		print("OUTLINE %s: %d interactable(s) checked." % [label, count])
		container.remove_child(location)
		location.queue_free()
		await _physics_frames(2)

	container.queue_free()
	Harness.finish(
		self,
		_failures,
		"all %d shipped interactables (and the companion) resolve support paths, outline a "
		% total
		+ "visible mesh and have its pick box; no authored mesh is on the outline layer."
	)


func _check_interactable(interactable: Interactable, label: String) -> void:
	var id := String(interactable.interact_id)
	for support_path: String in interactable.support_paths:
		if interactable.get_node_or_null(NodePath(support_path)) == null:
			_failures.append(
				"%s: '%s' has unresolved support path '%s'." % [label, id, support_path]
			)
	var meshes := interactable.get_outline_meshes()
	if meshes.is_empty():
		_failures.append(
			"%s: '%s' has nothing to outline; set outline_paths to the meshes the player sees."
			% [label, id]
		)
		return
	var expected := 0
	for mesh in meshes:
		if interactable.gets_pick_box(mesh):
			expected += 1
	if interactable.get_pick_shapes().size() != expected:
		_failures.append(
			"%s: '%s' has %d pick box(es) for %d outline mesh(es) that should each have one."
			% [label, id, interactable.get_pick_shapes().size(), expected]
		)
	elif expected == 0:
		# Floor paint or something longer than a pick box: found by its anchor alone. Said
		# out loud so the choice is visible in the log, not failed.
		print("OUTLINE %s: '%s' is pointable by its anchor only." % [label, id])


func _check_no_mask_layer(scope: Node, label: String) -> void:
	for node: Node in scope.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual.layers & OutlineOverlay.MASK_LAYER != 0:
			_failures.append(
				"%s: '%s' is authored on visual layer 20, which the outline overlay reserves."
				% [label, String(scope.get_path_to(visual))]
			)


func _check_overlay_under_ui() -> void:
	var overlay := _main.get_node_or_null("OutlineOverlay") as OutlineOverlay
	if overlay == null:
		_failures.append("main: there is no OutlineOverlay node.")
		return
	if not overlay.is_in_group(OutlineOverlay.GROUP):
		_failures.append("main: the OutlineOverlay is not in its group, so cues would make their own.")
	for node: Node in _main.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer == overlay or layer.get_parent() == overlay:
			continue
		if layer.layer <= overlay.layer:
			_failures.append(
				"main: CanvasLayer '%s' (layer %d) is not above the outline overlay (layer %d)."
				% [String(_main.get_path_to(layer)), layer.layer, overlay.layer]
			)


func _physics_frames(count: int) -> void:
	for _index in count:
		await physics_frame
