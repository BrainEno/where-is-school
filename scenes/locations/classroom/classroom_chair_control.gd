class_name ClassroomChairControl
extends Node
## Stages the wake desk's chair and bag, and seats both students for the lesson.
## The room owns the floor and grip marks; the director owns the beat lock.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const SeatMotion = preload("res://scripts/actors/player/classroom_seat_motion.gd")
const SeatOffer = preload("res://scripts/interaction/seated_chair_interactable.gd")
const Bag = preload("res://scenes/environment/props/schoolbag.gd")

## The seat lip needs 0.63 m to clear the stationary 0.35 m capsule. Leave 1 cm
## rather than trading a visibly shorter slide for a body inside the chair.
const CLASSROOM_SLIDE := 0.64
const PULL_FLANK := 0.67
# Halfway along the backrest's travel; the wrist can reach both stops.
const PULL_BEHIND := 0.44
const SEAT_FLANK := 0.81
const PERSON_GAP := 0.65
# Route around the desktop seam via the cross-aisle between rows A and B.
const FRONT_CROSS_AISLE := 1.4
const FAR_AISLE_FLANK := 1.52

@export var player_group: StringName = &"protagonist"
@export var chair_path: NodePath = ^"../Furniture/DeskB2/Chair"
@export var q_chair_path: NodePath = ^"../Furniture/DeskQ/Chair"
@export var seat_interactable_path: NodePath = ^"../Interactables/ChairSit"
@export var bag_path: NodePath = ^"../Furniture/DeskB2/Schoolbag"
@export var bag_interactable_path: NodePath = ^"../Interactables/SchoolbagInspect"

@onready var _chair := get_node(chair_path) as PushableChair
@onready var _q_chair := get_node(q_chair_path) as PushableChair
@onready var _seat := get_node(seat_interactable_path) as SeatOffer
@onready var _bag := get_node(bag_path) as Bag
@onready var _inspect := get_node(bag_interactable_path) as StagedInteractable
@onready var _navigation := get_node_or_null(^"../Navigation") as LocationNavigation
var _shown := SeatOffer.Offer.NONE
var _q_motion: SeatMotion


static func in_room(location: LocationRoot) -> ClassroomChairControl:
	if location == null or location.location_id != &"classroom":
		return null
	return location.get_node_or_null(^"ChairControl") as ClassroomChairControl


func _ready() -> void:
	_chair.set_slide_distance(CLASSROOM_SLIDE)
	_q_chair.set_slide_distance(CLASSROOM_SLIDE)
	_chair.bind_pick_target(_seat)
	_seat.chair = _chair
	_seat.stage_handler = _stage_sit
	_inspect.stage_handler = _stage_search
	_bind_player.call_deferred()


func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group(player_group) as PlayerController
	_seat.player = player
	# Continue restores a position, not an in-progress pose. At the wake mark,
	# a standing player needs the chair at the clear stop, even on an older save.
	if player != null and not player.is_seated() and player.global_position.distance_to(_chair.home_mark()) < 0.015:
		_chair.snap_back()
	_update_offer()


func _process(_delta: float) -> void:
	_update_offer()


func _update_offer() -> void:
	var offer := _seat.current_offer()
	if offer == _shown:
		return
	_shown = offer
	if offer == SeatOffer.Offer.SIT:
		_seat.set_prompt("prompt.sit")
	elif offer == SeatOffer.Offer.STAND:
		_seat.set_prompt("prompt.stand")


func _stage_sit(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	if player.is_seated():
		player.stand_up()
		await _seat_transfer(player)
	else:
		_stop(player)
		await _return_player(player, _classmate())
	return {}


## The bell already owns the controls. Move one person at a time so a footprint
## stays predictable. If the protagonist is in Q's way, let them go ahead first.
func seat_for_class(player: PlayerController, q: NpcActor) -> void:
	_stop(player)
	await _seat_transfer(player)
	var q_ready := await _return_q(player, q)
	var player_ready := await _return_player(player, q)
	if not q_ready and player_ready:
		await _return_q(player, q)


## A fresh room after the bell needs the settled pose, not another scrape and walk.
func restore_q_seat(q: NpcActor) -> bool:
	var animator := q.get_character_animator()
	if animator == null or not animator.is_bound() or animator.is_seated():
		return false
	var home := _q_chair.home_mark()
	q.place_at(home, home - _q_chair.global_basis.z)
	_finish_q_seat(animator, SeatMotion.new(_q_chair, animator, animator, animator.position.y))
	return true


func _return_player(player: PlayerController, q: NpcActor) -> bool:
	if player.is_seated():
		return true
	if not _sweep_clear(_chair, q, player.navigation_agent.radius):
		return false
	if not _chair.is_pushed_back():
		var animator := player.get_character_animator()
		var flank := _outside_flank(_chair, _q_chair)
		if animator == null or not await _approach(player, _pull_mark(_chair, flank), _seat_blockers(q)):
			return false
		await Motion.turn_to(player, -_chair.global_basis.z)
		var motion := SeatMotion.new(_chair, player.visual, animator, PlayerController.STANDING_HIP_HEIGHT)
		await motion.pull_out(player, flank)
	if not await _approach(player, _chair.home_mark(), _seat_blockers(q)):
		return false
	await Motion.turn_to(player, -_chair.global_basis.z)
	if not player.sit_down(_chair):
		return false
	await _seat_transfer(player)
	return player.is_seated()


func _return_q(player: PlayerController, q: NpcActor) -> bool:
	if q == null or not q.is_visible_in_tree():
		return true
	var animator := q.get_character_animator()
	if animator == null or not animator.is_bound():
		return false
	if animator.is_seated():
		return true
	# If the player is still standing in this chair's track, let them sit first.
	if not _sweep_clear(_q_chair, player, player.navigation_agent.radius):
		return false
	var motion := SeatMotion.new(_q_chair, animator, animator, animator.position.y)
	if not _q_chair.is_pushed_back():
		var flank := _outside_flank(_q_chair, _chair)
		var pull_mark := _pull_mark(_q_chair, flank)
		var pull_route := _clear_route(player, _q_chair, q.global_position, pull_mark, _seat_blockers(player))
		if pull_route.is_empty():
			return false
		q.stop_watching()
		await q.walk_along(Array(pull_route))
		await _turn_q_to_chair(q)
		await motion.pull_out(q, flank)
	var route := _clear_route(player, _q_chair, q.global_position, _q_chair.home_mark(), _seat_blockers(player))
	if route.is_empty():
		return false
	await q.walk_along(Array(route))
	await _turn_q_to_chair(q)
	motion.start()
	var tween := q.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_method(motion.sample_sit, 0.0, 1.0, SeatMotion.SIT_SECONDS)
	await tween.finished
	_finish_q_seat(animator, motion)
	return true


func _turn_q_to_chair(q: NpcActor) -> void:
	var back := _q_chair.global_basis.z
	var turn := angle_difference(q.global_rotation.y, atan2(back.x, back.z))
	if absf(turn) < 0.05:
		return
	var tween := q.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(q, "global_rotation:y", q.global_rotation.y + turn, 0.24)
	await tween.finished


func _finish_q_seat(animator: CharacterVisualAnimation, motion: SeatMotion) -> void:
	_q_motion = motion
	_q_chair.snap_home()
	motion.set_seated_pivot(0.0)
	var mixer := animator.get_animation_player()
	if not mixer.mixer_applied.is_connected(_plant_q_feet):
		mixer.mixer_applied.connect(_plant_q_feet)
	animator.seated_dialogue_clip = "sit_talk"
	animator.set_seated(true)
	animator.release_sampled_action()


func _plant_q_feet() -> void:
	if _q_motion != null:
		_q_motion.plant_seated()


func _outside_flank(chair: PushableChair, neighbour: PushableChair) -> float:
	return signf(chair.global_basis.x.dot(chair.home_mark() - neighbour.home_mark()))


func _pull_mark(chair: PushableChair, flank: float) -> Vector3:
	return chair.home_mark() + chair.global_basis * Vector3(PULL_FLANK * flank, 0.0, PULL_BEHIND)


func _sweep_clear(chair: PushableChair, other: Node3D, radius: float) -> bool:
	if other == null or not other.is_visible_in_tree():
		return true
	var sweep := chair.sweep_bounds().grow(radius)
	var feet := other.global_position
	return not sweep.has_point(Vector3(feet.x, sweep.get_center().y, feet.z))


func _seat_blockers(other: Node3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	for node in get_tree().get_nodes_in_group(PlayerController.SEATED_CHAIR_GROUP):
		var chair := node as PushableChair
		if chair != null and get_parent().is_ancestor_of(chair):
			boxes.append(chair.mesh_bounds().grow(0.35))
	if other != null and other.is_visible_in_tree():
		var half := Vector3(PERSON_GAP, 0.45, PERSON_GAP)
		boxes.append(AABB(other.global_position - half, half * 2.0))
	return boxes


func _classmate() -> NpcActor:
	return (get_parent() as LocationRoot).find_actor(&"q")


func _stage_search(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	if player.is_seated():
		player.stand_up()
	await _seat_transfer(player)
	_stop(player)
	# Keep the original inspection usable if scenery is obstructed (including legacy
	# saves). Do not drag the body through the obstruction just to reach a mark.
	if await _approach(player, _bag.search_position(), _seat_blockers(_classmate())):
		await Motion.turn_to(player, -_bag.global_basis.z)
		await _bag.rummage(player)
	return {"inspection": _inspect.inspection_id}


func _seat_transfer(player: PlayerController) -> void:
	while player.is_seat_transition_active():
		await get_tree().physics_frame


func _stop(player: PlayerController) -> void:
	player.velocity.x = 0.0
	player.velocity.z = 0.0


func _approach(player: PlayerController, target: Vector3, blockers: Array[AABB] = []) -> bool:
	var route := _clear_route(player, _chair, player.global_position, target, blockers)
	if route.is_empty():
		return false
	for point in route:
		if not await Motion.walk_to(player, point, 1.85):
			return false
	return true


## Use the existing direct/flank approach near a desk, with a navmesh detour for
## the bell if someone is several rows away. Even the detour must pass the real
## capsule sweeps and clear the decorative chairs (which the bake cannot see).
func _clear_route(player: PlayerController, chair: PushableChair, start: Vector3,
		target: Vector3, blockers: Array[AABB]) -> PackedVector3Array:
	var origin := chair.home_mark()
	var right := chair.global_basis.x
	var forward := -chair.global_basis.z
	var routes: Array[PackedVector3Array] = [PackedVector3Array([target])]
	var neighbour := _q_chair if chair == _chair else _chair
	var outside := _outside_flank(chair, neighbour)
	var outside_mark := origin + right * outside * SEAT_FLANK
	for sign_side: float in [outside, -outside]:
		var flank := origin + right * sign_side * SEAT_FLANK
		var same_row := flank + forward * forward.dot(start - flank)
		routes.append(PackedVector3Array([flank, target]))
		routes.append(PackedVector3Array([same_row, flank, target]))
		if target.distance_to(origin) > 0.1:
			# Bag at the other corner: cross the gap in front of the chair first.
			routes.append(PackedVector3Array([same_row, flank, outside_mark, target]))
		if not blockers.is_empty() and _navigation != null and _navigation.is_synchronized():
			var map := _navigation.get_navigation_map()
			var detour := NavigationServer3D.map_get_path(map, start, flank, true)
			if detour.size() > 1:
				detour.append_array(PackedVector3Array([flank, target]))
				routes.append(detour)
	if not blockers.is_empty():
		# The bake can route between the chairs because it only sees the desks. If
		# that route is occupied, go around the pair via the front cross-aisle.
		var far := neighbour.home_mark() - right * outside * FAR_AISLE_FLANK
		var across := forward * FRONT_CROSS_AISLE
		var around := PackedVector3Array([far + across, outside_mark + across, outside_mark, target])
		routes.append(around)
		var along_flank := PackedVector3Array([far + forward * forward.dot(start - far)])
		along_flank.append_array(around)
		routes.append(along_flank)
	var best := PackedVector3Array()
	var best_length := INF
	for route in routes:
		var from := start
		var length := 0.0
		var grounded := PackedVector3Array()
		for point in route:
			point.y = start.y
			var leg := point - from
			var probe := Transform3D(player.global_basis, from + Vector3.UP * 0.035)
			if leg.length_squared() > 0.00001 and (player.test_move(probe, leg) or _blocked(from, point, blockers)):
				length = INF
				break
			grounded.append(point)
			length += leg.length()
			from = point
		if length < best_length:
			best_length = length
			best = grounded
	return best


func _blocked(from: Vector3, to: Vector3, blockers: Array[AABB]) -> bool:
	for box in blockers:
		var centre := box.get_center()
		var a := Vector3(from.x, centre.y, from.z)
		var b := Vector3(to.x, centre.y, to.z)
		# Free movement can leave someone close to a non-solid chair or classmate.
		# Let them step out of the padded footprint, never cross back through it.
		if box.has_point(a) and not box.has_point(b) and (a - centre).dot(b - a) > 0.0:
			continue
		if box.intersects_segment(a, b) != null:
			return true
	return false
