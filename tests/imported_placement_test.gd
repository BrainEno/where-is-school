extends SceneTree
## The four imported models, **in the game** rather than in a preview scene.
##
##   godot --headless --path . --script res://tests/imported_placement_test.gd
##
## `imported_assets_test.gd` measures the assets themselves: size, origin, facing, and
## the collision of the wrapper. That is necessary and not sufficient — a model in
## `assets/` that no location instantiates has no screen time, and a model dropped into
## a hand-built blockout brings its own ways to be wrong:
##
##  1. **The stand-in stays.** A graybox desk or a capsule left in the tree renders
##     inside or through the model, and nothing that measures the model notices.
##  2. **Two colliders, one desk.** The old body plus the model's wrapper collides twice,
##     which the navigation bake reads as a thicker obstacle and the interaction line of
##     sight reads as a wall that is drawn nowhere.
##  3. **Floating or sunk.** A model whose origin is not on its base, dropped at a y that
##     looked right for the previous asset, hovers over the floor or buries its feet.
##     The characters and the desk dressing are both in this category.
##  4. **Facing without a rule.** The two authored characters look down +Z, the pipeline
##     says −Z, and the player's turn and the NPC's turn each apply an angle. Get one of
##     them wrong and a character walks backwards while every size still matches.
##
## So this test loads the real scenes — `classroom.tscn`, `player.tscn`,
## `companion.tscn`, `npc_actor.tscn` — and checks what the player sees and bumps into.
## It does not photograph anything (that is `capture_playthrough.gd`) and it is not a
## layout review: the six desks are required to still be where they were.
##
## Where a number could be read off the thing being tested, it is read rather than
## copied: the desk's top is measured on the instantiated desk, and the character's feet
## are measured on the instantiated character.

const Harness = preload("res://tests/test_harness.gd")

const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const PLAYER := "res://scenes/actors/player/player.tscn"
const COMPANION := "res://scenes/actors/npc/companion.tscn"
const CLASSROOM_DESK := "res://scenes/environment/props/classroom_desk.tscn"
const SCHOOL_DESK := "res://scenes/environment/props/school_desk.tscn"
const TEACHER_DESK := "res://scenes/environment/props/teacher_desk.tscn"
const STATIONERY := "res://scenes/environment/props/stationery_supplies.tscn"
const PROTAGONIST := "res://scenes/environment/characters/protagonist.tscn"
const Q_CHARACTER := "res://scenes/environment/characters/q.tscn"

## The six student desks, exactly where the classroom has always put them. The round that
## swapped the model was allowed to move the chair inside the desk, not the furniture.
const DESKS := {
	"DeskA1": Vector3(-2.5, 0, -1.5),
	"DeskA2": Vector3(0, 0, -1.5),
	"DeskA3": Vector3(2.5, 0, -1.5),
	"DeskB1": Vector3(-2.5, 0, 0.2),
	"DeskB2": Vector3(0, 0, 0.2),
	"DeskB3": Vector3(2.5, 0, 0.2),
}
## The player's own desk, and therefore the one desk that carries the stationery.
const OWN_DESK := "DeskB2"
## How far off its surface a prop may sit before it is floating or sunk.
const CONTACT_TOLERANCE := 0.02
## How far past the desk's footprint the dressing may hang before it is on air.
const FOOTPRINT_SLACK := 0.01
## Measured in `imported_assets_test.gd`; repeated so a placement cannot hide a
## re-export that changed the size.
const DESK_SIZE := Vector3(0.7118, 0.8826, 0.5460)
const SIZE_TOLERANCE := 0.02
## The desk's collision box covers the whole desk, so it is centred at half its height.
const DESK_BODY_CENTER_Y := 0.4413
const BODY_CENTER_TOLERANCE := 0.01
## The chair's seat plane, and the gap between the seat's front edge and the desk's back.
const SEAT_HEIGHT := 0.45
const SEAT_HEIGHT_TOLERANCE := 0.02
const SEAT_GAP_MIN := 0.03
const SEAT_GAP_MAX := 0.25
## The protagonist's authored height and the 1.7 cm between its origin and its sole.
const PROTAGONIST_HEIGHT := 1.7269
const PROTAGONIST_SOLE_OFFSET := 0.0170
## Where the wake beat expects the visual pivot to rest (it writes this value).
const VISUAL_PIVOT_Y := 0.9
## The half turn `face_towards()` applies for a −Z model.
const NPC_TURN := PI
## The half turn the +Z characters need on their own visual node.
const VISUAL_CORRECTION := PI

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 240.0, "imported_placement_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)

	var holder := Node3D.new()
	holder.name = "ImportedPlacementHolder"
	root.add_child(holder)
	await process_frame

	Harness.stage = "classroom desks and dressing"
	await _check_classroom(holder)

	Harness.stage = "player"
	await _check_player(holder)

	Harness.stage = "q"
	await _check_q(holder)

	root.remove_child(holder)
	holder.free()

	Harness.finish(
		self, _failures,
		"the six student desks are the imported model with one collider each, the "
		+ "stationery sits on the player's own desk, the player and Q both wear their "
		+ "authored models with their feet on the floor, the grayboxes are retired, and "
		+ "N keeps his."
	)


# --- the classroom ----------------------------------------------------------


func _check_classroom(holder: Node3D) -> void:
	var packed := load(CLASSROOM) as PackedScene
	if packed == null:
		_failures.append("The classroom scene could not be loaded.")
		return
	var location := packed.instantiate() as Node3D
	if location == null:
		_failures.append("The classroom scene is not a 3D scene.")
		return
	holder.add_child(location)
	await process_frame
	await process_frame

	_check_six_desks(location)
	_check_teacher_desk(location)
	_check_stationery(location)

	holder.remove_child(location)
	location.free()


func _check_six_desks(location: Node3D) -> void:
	var furniture := location.get_node_or_null(^"Furniture")
	if furniture == null:
		_failures.append("The classroom has no Furniture node.")
		return
	for desk_name: String in DESKS:
		var desk := furniture.get_node_or_null(NodePath(desk_name)) as Node3D
		if desk == null:
			_failures.append("The classroom has no desk named '%s'." % desk_name)
			continue
		var expected: Vector3 = DESKS[desk_name]
		if not desk.position.is_equal_approx(expected):
			_failures.append(
				"'%s' stands at %s; its row is %s. Swapping a model is not a layout change."
				% [desk_name, str(desk.position), str(expected)]
			)
		if desk.scene_file_path != CLASSROOM_DESK:
			_failures.append(
				"'%s' instances '%s' rather than the classroom desk wrapper."
				% [desk_name, desk.scene_file_path]
			)
			continue
		var model := desk.get_node_or_null(^"Desk") as Node3D
		_check_desk_body(desk_name, desk, model)
		_check_chair(desk_name, desk, model)


## The desk the classroom draws is the imported model, and the only solid part of the
## desk is that model's own wrapper: one body, one box, the size of the desk.
func _check_desk_body(desk_name: String, desk: Node3D, model: Node3D) -> void:
	if model == null:
		_failures.append(
			"'%s' has no 'Desk' child, so the old graybox body is still what is drawn."
			% desk_name
		)
		return
	if model.scene_file_path != SCHOOL_DESK:
		_failures.append(
			"'%s/Desk' instances '%s', not the school desk wrapper '%s'."
			% [desk_name, model.scene_file_path, SCHOOL_DESK]
		)
		return
	if not model.scale.is_equal_approx(Vector3.ONE):
		_failures.append(
			"'%s/Desk' is scaled to %s; the desk is used at its authored size."
			% [desk_name, str(model.scale)]
		)

	var bodies: Array[Node] = []
	var shapes: Array[Node] = []
	for node in _descendants(desk):
		if node is CollisionObject3D:
			bodies.append(node)
		if node is CollisionShape3D:
			shapes.append(node)

	if bodies.size() != 1:
		_failures.append(
			"'%s' has %d collision bodies; the model's wrapper is the only one a desk may "
			% [desk_name, bodies.size()]
			+ "have (a second one is the old graybox, colliding inside the model)."
		)
	if shapes.size() != 1:
		_failures.append(
			"'%s' has %d collision shapes; one box per desk, or the navigation bake carves "
			% [desk_name, shapes.size()]
			+ "two obstacles out of one desk."
		)
		return

	var body := bodies[0] as StaticBody3D
	if body == null or body != model:
		_failures.append(
			"'%s' is made solid by '%s', not by the school desk wrapper."
			% [desk_name, bodies[0].name]
		)
		return
	if not (body.collision_layer & 1):
		_failures.append(
			"'%s' is not on the world layer, so it neither blocks nor bakes." % desk_name
		)

	var shape_node := shapes[0] as CollisionShape3D
	var box := shape_node.shape as BoxShape3D
	if box == null:
		_failures.append("'%s' does not collide with a box; the desk is a box." % desk_name)
		return
	if not _sizes_within(box.size, DESK_SIZE):
		_failures.append(
			"'%s' collides %.3f x %.3f x %.3f m, the desk is %.3f x %.3f x %.3f."
			% [
				desk_name, box.size.x, box.size.y, box.size.z,
				DESK_SIZE.x, DESK_SIZE.y, DESK_SIZE.z,
			]
		)
	if absf(shape_node.position.y - DESK_BODY_CENTER_Y) > BODY_CENTER_TOLERANCE:
		_failures.append(
			"'%s' centres its collider at y = %.3f; a box on the floor is centred at %.3f."
			% [desk_name, shape_node.position.y, DESK_BODY_CENTER_Y]
		)

	# The visual the collider is supposed to cover: on the floor, at the authored height.
	var extent := _subtree_aabb(model)
	if absf(extent.position.y) > CONTACT_TOLERANCE:
		_failures.append(
			"'%s/Desk' has its base at y = %.3f m; the desk has to stand on the floor."
			% [desk_name, extent.position.y]
		)
	if absf(extent.end.y - DESK_SIZE.y) > CONTACT_TOLERANCE:
		_failures.append(
			"'%s/Desk' is %.3f m tall, the model is %.3f m."
			% [desk_name, extent.end.y, DESK_SIZE.y]
		)


## The chair is still the blockout, still without collision, and still at a desk.
func _check_chair(desk_name: String, desk: Node3D, model: Node3D) -> void:
	var chair := desk.get_node_or_null(^"Chair") as Node3D
	if chair == null:
		_failures.append("'%s' lost its Chair subtree." % desk_name)
		return
	for node in _descendants(chair):
		if node is CollisionObject3D or node is CollisionShape3D:
			_failures.append(
				"'%s/Chair/%s' collides; the chairs have never collided and the walk routes "
				% [desk_name, node.name]
				+ "are laid out on that."
			)
			break
	var seat := chair.get_node_or_null(^"Seat") as MeshInstance3D
	if seat == null:
		_failures.append("'%s/Chair' has no Seat." % desk_name)
		return
	var seat_height := seat.global_position.y - desk.global_position.y
	if absf(seat_height - SEAT_HEIGHT) > SEAT_HEIGHT_TOLERANCE:
		_failures.append(
			"'%s' seat plane is at %.3f m, the blockout has always been %.3f m."
			% [desk_name, seat_height, SEAT_HEIGHT]
		)
	if model == null:
		return
	# The seat has to sit at the desk's back edge: not under the middle of it, and not a
	# stride away. The imported desk is 0.55 m deep where the old one was 0.8 m.
	var seat_box := _subtree_aabb(seat)
	var desk_box := _subtree_aabb(model)
	var gap := seat_box.position.z - desk_box.end.z
	if gap < SEAT_GAP_MIN or gap > SEAT_GAP_MAX:
		_failures.append(
			"'%s' leaves %.3f m between the desk's back edge and the seat's front edge; "
			% [desk_name, gap]
			+ "expected %.2f-%.2f m for a chair someone sits on."
			% [SEAT_GAP_MIN, SEAT_GAP_MAX]
		)


## The teacher's desk is 1.9 m wide and is deliberately *not* the student model.
func _check_teacher_desk(location: Node3D) -> void:
	var furniture := location.get_node_or_null(^"Furniture")
	var teacher: Node3D = null
	if furniture != null:
		teacher = furniture.get_node_or_null(^"FrontDesk") as Node3D
	if teacher == null:
		_failures.append("The teacher's desk is gone from the classroom.")
		return
	if teacher.scene_file_path != TEACHER_DESK:
		_failures.append(
			"The teacher's desk instances '%s'; it is 1.9 m wide and is not a student desk."
			% teacher.scene_file_path
		)
		return
	var extent := _subtree_aabb(teacher)
	if extent.size.x < 1.5:
		_failures.append(
			"The teacher's desk is %.2f m wide; the 0.71 m student desk has been put where "
			% extent.size.x
			+ "the 1.9 m one belongs."
		)


func _check_stationery(location: Node3D) -> void:
	var found: Array[Node] = []
	for node in _descendants(location):
		if node is Node3D and node.scene_file_path == STATIONERY:
			found.append(node)
	if found.size() != 1:
		_failures.append(
			"The classroom holds %d stationery set(s); the player's desk is dressed once."
			% found.size()
		)
		if found.is_empty():
			return

	var set_node := found[0] as Node3D
	var parent := set_node.get_parent()
	var parent_path := String(parent.get_path()) if parent != null else "<none>"
	if not parent_path.ends_with("Furniture/%s" % OWN_DESK):
		_failures.append(
			"The stationery hangs under '%s', not under the player's own desk (%s)."
			% [parent_path, OWN_DESK]
		)

	# No collision of its own: dressing sits on furniture that already collides, and a
	# 0.16 m prop with a collider would carve a hole in the baked navigation mesh.
	for node in _descendants(set_node):
		if node is CollisionObject3D or node is CollisionShape3D:
			_failures.append(
				"The stationery set carries collision (%s); desk dressing must not."
				% node.name
			)
			break

	var desk := location.get_node_or_null(^"Furniture/DeskB2") as Node3D
	var desk_model: Node3D = null
	if desk != null:
		desk_model = desk.get_node_or_null(^"Desk") as Node3D
	if desk_model == null:
		_failures.append("The player's own desk has no model, so the dressing has no top.")
		return

	var set_box := _subtree_aabb(set_node)
	var desk_box := _subtree_aabb(desk_model)
	var top := desk_box.end.y
	if absf(set_box.position.y - top) > CONTACT_TOLERANCE:
		_failures.append(
			"The stationery's base is at y = %.3f m, the desk's top at %.3f m: %.1f cm off "
			% [set_box.position.y, top, (set_box.position.y - top) * 100.0]
			+ "the surface."
		)
	if set_box.position.x < desk_box.position.x - FOOTPRINT_SLACK:
		_failures.append("The stationery hangs off the left edge of the desk.")
	if set_box.end.x > desk_box.end.x + FOOTPRINT_SLACK:
		_failures.append("The stationery hangs off the right edge of the desk.")
	if set_box.position.z < desk_box.position.z - FOOTPRINT_SLACK:
		_failures.append("The stationery hangs off the far edge of the desk.")
	if set_box.end.z > desk_box.end.z + FOOTPRINT_SLACK:
		_failures.append(
			"The stationery hangs off the near edge of the desk, where the player sits."
		)
	if absf(set_box.size.y - 0.1643) > SIZE_TOLERANCE:
		_failures.append(
			"The stationery is %.3f m tall; the imported set is 0.164 m and is not scaled."
			% set_box.size.y
		)


# --- the player -------------------------------------------------------------


func _check_player(holder: Node3D) -> void:
	var packed := load(PLAYER) as PackedScene
	if packed == null:
		_failures.append("The player scene could not be loaded.")
		return
	var player := packed.instantiate() as PlayerController
	if player == null:
		_failures.append("The player scene is not a PlayerController.")
		return
	holder.add_child(player)
	await process_frame
	await process_frame

	var visual := player.get_node_or_null(^"%Visual") as Node3D
	if visual == null:
		_failures.append(
			"%Visual is gone or is no longer a Node3D; the wake beat tilts this node."
		)
		holder.remove_child(player)
		player.free()
		return
	if visual is MeshInstance3D:
		_failures.append("%Visual is still the graybox capsule mesh.")
	if not visual.position.is_equal_approx(Vector3(0.0, VISUAL_PIVOT_Y, 0.0)):
		_failures.append(
			"%Visual rests at %s; the wake beat writes y = %.2f, so those have to agree."
			% [str(visual.position), VISUAL_PIVOT_Y]
		)
	if not visual.scale.is_equal_approx(Vector3.ONE):
		_failures.append("%Visual is scaled to %s; the model is used at its size." % str(visual.scale))
	# Two corrections cancel out and the mistake then looks like a distant bug: the model
	# is dropped in straight, and the only yaw is the controller's own `atan2`.
	if absf(angle_difference(visual.rotation.y, 0.0)) > 0.001:
		_failures.append(
			"%Visual is turned %.1f degrees; the protagonist looks down +Z already."
			% rad_to_deg(visual.rotation.y)
		)

	var model := visual.get_node_or_null(^"Model") as Node3D
	if model == null:
		_failures.append("The player's visual carries no 'Model'.")
		holder.remove_child(player)
		player.free()
		return
	if model.scene_file_path != PROTAGONIST:
		_failures.append(
			"The player's visual instances '%s', not the authored protagonist."
			% model.scene_file_path
		)
	# pivot + model offset + the authored sole offset = the floor.
	var expected_model_y := -(VISUAL_PIVOT_Y + PROTAGONIST_SOLE_OFFSET)
	if absf(model.position.y - expected_model_y) > 0.005:
		_failures.append(
			"The model hangs at y = %.4f under the pivot; %.4f puts its feet on the floor."
			% [model.position.y, expected_model_y]
		)

	var extent := _subtree_aabb(visual)
	if absf(extent.position.y - player.global_position.y) > CONTACT_TOLERANCE:
		_failures.append(
			"The protagonist's lowest point is at y = %.3f m while the player stands at "
			% extent.position.y
			+ "%.3f m: the feet hover or sink." % player.global_position.y
		)
	if absf(extent.size.y - PROTAGONIST_HEIGHT) > SIZE_TOLERANCE:
		_failures.append(
			"The protagonist measures %.3f m; the authored character is %.3f m."
			% [extent.size.y, PROTAGONIST_HEIGHT]
		)

	# The turn: the model faces where the body walks, with no extra half turn.
	player._facing_direction = Vector3(1.0, 0.0, 0.0)
	player.turn_speed = 30.0
	for _frame in 20:
		await physics_frame
	var pivot := player.get_node_or_null(^"%VisualPivot") as Node3D
	if pivot == null:
		_failures.append("%VisualPivot is gone; the model has nothing to turn.")
	else:
		var expected_angle := atan2(1.0, 0.0)
		if absf(angle_difference(pivot.rotation.y, expected_angle)) > 0.02:
			_failures.append(
				"The player faces +X but the pivot sits at %.1f degrees, not %.1f: the turn "
				% [rad_to_deg(pivot.rotation.y), rad_to_deg(expected_angle)]
				+ "is not atan2(facing.x, facing.z)."
			)
		var forward := pivot.global_basis * Vector3(0.0, 0.0, 1.0)
		forward.y = 0.0
		if forward.length() > 0.0001:
			if forward.normalized().dot(Vector3(1.0, 0.0, 0.0)) < 0.99:
				_failures.append(
					"The model's +Z points %s while the player walks +X: the character "
					% str(forward.normalized())
					+ "would walk backwards."
				)

	# The wake beat still owns the pivot, and the feet do not leave the floor with it.
	player.set_wake_pose(1.0)
	if absf(visual.position.y - (VISUAL_PIVOT_Y - 0.06)) > 0.001:
		_failures.append(
			"The wake slump leaves the pivot at y = %.3f; the beat writes %.2f."
			% [visual.position.y, VISUAL_PIVOT_Y - 0.06]
		)
	if absf(rad_to_deg(visual.rotation.x) - player.wake_tilt_degrees) > 0.01:
		_failures.append(
			"The wake slump tilts the visual %.1f degrees, the beat asks for %.1f."
			% [rad_to_deg(visual.rotation.x), player.wake_tilt_degrees]
		)
	var slumped := _subtree_aabb(visual)
	if slumped.position.y > CONTACT_TOLERANCE:
		_failures.append(
			"Slumped, the model's lowest point is %.3f m above the floor; the shoulders "
			% slumped.position.y
			+ "slump, the feet stay down."
		)
	player.set_wake_pose(0.0)

	holder.remove_child(player)
	player.free()


# --- Q ----------------------------------------------------------------------


func _check_q(holder: Node3D) -> void:
	var packed := load(CLASSROOM) as PackedScene
	if packed == null:
		_failures.append("The classroom scene could not be loaded for the Q checks.")
		return
	var location := packed.instantiate() as Node3D
	if location == null:
		return
	holder.add_child(location)
	await process_frame
	await process_frame
	var actors := location.get_node_or_null(^"Actors")
	var classroom_q: NpcActor = null
	var classroom_n: NpcActor = null
	if actors != null:
		classroom_q = actors.get_node_or_null(^"Q") as NpcActor
		classroom_n = actors.get_node_or_null(^"N") as NpcActor
	if classroom_q == null:
		_failures.append("The classroom's Q is gone.")
	else:
		_check_authored_actor("The classroom Q", classroom_q, Q_CHARACTER)
		_check_actor_turn("The classroom Q", classroom_q)
	if classroom_n == null:
		_failures.append("The classroom's N is gone.")
	else:
		_check_graybox_actor("The classroom N", classroom_n)
	holder.remove_child(location)
	location.free()

	# The companion is the second Q, and the one a model swap forgets: the director
	# spawns it, so nothing about the classroom proves it wears the same model.
	var stub_root := Node3D.new()
	stub_root.name = "CompanionHolder"
	holder.add_child(stub_root)
	var stub_player := Node3D.new()
	stub_player.name = "Player"
	stub_root.add_child(stub_player)
	var stub_host := LocationHost.new()
	stub_host.name = "LocationHost"
	stub_root.add_child(stub_host)
	var companion_packed := load(COMPANION) as PackedScene
	if companion_packed == null:
		_failures.append("The companion scene could not be loaded.")
	else:
		var companion := companion_packed.instantiate() as CharacterBody3D
		if companion == null:
			_failures.append("The companion scene is not a CharacterBody3D.")
		else:
			stub_root.add_child(companion)
			await process_frame
			await process_frame
			var actor := companion.get_node_or_null(^"Actor") as NpcActor
			if actor == null:
				_failures.append("The companion has no Actor.")
			else:
				_check_authored_actor("The companion's Q", actor, Q_CHARACTER)
				_check_actor_turn("The companion's Q", actor)
			# The model is a visual: the body's capsule is still the only thing the
			# companion collides with, and the Ask Along hotspot is its own Area3D, which
			# is not part of either.
			var body_shape := companion.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
			if body_shape == null or not (body_shape.shape is CapsuleShape3D):
				_failures.append("The companion's body has no capsule any more.")
			if actor != null:
				for node in _descendants(actor):
					if node is CollisionObject3D or node is CollisionShape3D:
						_failures.append(
							"The companion's Q carries a collider (%s); the model is a "
							% node.name
							+ "visual and the body owns the capsule."
						)
						break
			stub_root.remove_child(companion)
			companion.free()
	holder.remove_child(stub_root)
	stub_root.free()


## An actor with an authored model: the model is there, turned to match the actor's −Z
## convention, standing on the actor's floor, with the graybox behind it not drawn.
func _check_authored_actor(label: String, actor: NpcActor, expected_scene: String) -> void:
	if actor.visual_scene == null:
		_failures.append("%s has no visual_scene, so it is still drawn as the capsule." % label)
		return
	var visual := actor.get_visual()
	if visual == null:
		_failures.append("%s did not build its visual." % label)
		return
	if visual.scene_file_path != expected_scene:
		_failures.append(
			"%s draws '%s', not '%s'." % [label, visual.scene_file_path, expected_scene]
		)
	if String(visual.name) != "Visual":
		_failures.append(
			"%s's model is named '%s'; the tree and the tests call it 'Visual'."
			% [label, visual.name]
		)
	if absf(angle_difference(visual.rotation.y, VISUAL_CORRECTION)) > 0.001:
		_failures.append(
			"%s's model is turned %.1f degrees on its own axis; a +Z character needs %.0f."
			% [label, rad_to_deg(visual.rotation.y), rad_to_deg(VISUAL_CORRECTION)]
		)
	if not visual.scale.is_equal_approx(Vector3.ONE):
		_failures.append("%s's model is scaled to %s." % [label, str(visual.scale)])

	# Feet on the floor: the actor's own origin is the floor for both the classroom Q
	# (placed at y = 0) and the companion (a body standing on it).
	var extent := _subtree_aabb(visual)
	if absf(extent.position.y - actor.global_position.y) > CONTACT_TOLERANCE:
		_failures.append(
			"%s's feet are at y = %.3f m while the actor stands at %.3f m."
			% [label, extent.position.y, actor.global_position.y]
		)
	# 1.6466 m, the rigged asset: the rig bake dropped the ~9° authored tilt on Q's head and
	# hair nodes instead of applying it to the vertices, so the crown is 1.5 cm lower than the
	# unrigged 1.662 m. `imported_assets_test.gd` records the same number for the same reason.
	if absf(extent.size.y - 1.6466) > SIZE_TOLERANCE:
		_failures.append(
			"%s's model measures %.3f m; the rigged authored character is 1.647 m."
			% [label, extent.size.y]
		)

	var body := actor.get_node_or_null(^"Body") as MeshInstance3D
	var head := actor.get_node_or_null(^"Head") as MeshInstance3D
	if body == null or head == null:
		_failures.append("%s lost its Body or Head node instead of hiding it." % label)
	else:
		if body.visible or head.visible:
			_failures.append(
				"%s still draws the graybox capsule and head inside the model." % label
			)
	var nameplate := actor.get_node_or_null(^"Nameplate") as Label3D
	if nameplate == null or not nameplate.visible:
		_failures.append("%s has no nameplate any more." % label)
	elif String(nameplate.text) != "Q":
		_failures.append("%s's nameplate reads '%s'." % [label, nameplate.text])
	# A model is not a body: nothing under the actor may collide.
	for node in _descendants(actor):
		if node is CollisionObject3D or node is CollisionShape3D:
			_failures.append(
				"%s carries a collider (%s); the model is a visual and the controller owns "
				% [label, node.name]
				+ "the capsule."
			)
			break


## The actor's own turn is unchanged, and the model ends up looking at the target.
func _check_actor_turn(label: String, actor: NpcActor) -> void:
	var visual := actor.get_visual()
	if visual == null:
		return
	var saved := actor.global_transform
	actor.global_position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	var target := Vector3(1.0, 0.0, 0.0)
	actor.face_towards(target)
	var expected := atan2(target.x, target.z) + NPC_TURN
	if absf(angle_difference(actor.rotation.y, expected)) > 0.001:
		_failures.append(
			"%s turns %.1f degrees to face +X; face_towards() has always applied the half "
			% [label, rad_to_deg(actor.rotation.y)]
			+ "turn for a −Z model, and this round does not change that."
		)
	var model_forward := (actor.global_basis * visual.transform.basis) * Vector3(0.0, 0.0, 1.0)
	model_forward.y = 0.0
	if model_forward.length() > 0.0001:
		if model_forward.normalized().dot(target.normalized()) < 0.99:
			_failures.append(
				"%s's model looks %s while the actor was told to face %s: the character "
				% [label, str(model_forward.normalized()), str(target)]
				+ "walks backwards."
			)
	actor.global_transform = saved


## An actor with no `visual_scene` keeps the blockout it always had.
func _check_graybox_actor(label: String, actor: NpcActor) -> void:
	if actor.visual_scene != null:
		_failures.append("%s was given an authored model; N is still a graybox." % label)
	if actor.get_visual() != null:
		_failures.append("%s built a visual it was not given." % label)
	var body := actor.get_node_or_null(^"Body") as MeshInstance3D
	var head := actor.get_node_or_null(^"Head") as MeshInstance3D
	if body == null or head == null:
		_failures.append("%s has no Body or Head." % label)
		return
	if not body.visible or not head.visible:
		_failures.append("%s's graybox is hidden although it has no model to draw." % label)


# --- helpers ----------------------------------------------------------------


func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in node.get_children():
		result.append(child)
		result.append_array(_descendants(child))
	return result


## The world-space box around everything a node draws, **including the node itself**.
## The chair's `Seat` is a mesh with no children, so a version that only walked the
## children measured an empty box and reported a 1.2 m gap that was not there.
func _subtree_aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		for child in current.get_children():
			pending.append(child)
		var instance := current as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var box := instance.global_transform * instance.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result


func _sizes_within(a: Vector3, b: Vector3) -> bool:
	return (
		absf(a.x - b.x) <= SIZE_TOLERANCE
		and absf(a.y - b.y) <= SIZE_TOLERANCE
		and absf(a.z - b.z) <= SIZE_TOLERANCE
	)
