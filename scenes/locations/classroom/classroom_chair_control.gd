class_name ClassroomChairControl
extends Node
## Stages the two props at the protagonist's desk. The chair owns the floor mark;
## the schoolbag owns the hand marks. Neither beat changes what the story records.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const SeatOffer = preload("res://scripts/interaction/seated_chair_interactable.gd")
const Bag = preload("res://scenes/environment/props/schoolbag.gd")

@export var player_group: StringName = &"protagonist"
@export var chair_path: NodePath = ^"../Furniture/DeskB2/Chair"
@export var seat_interactable_path: NodePath = ^"../Furniture/DeskB2/Chair/ChairSit"
@export var bag_path: NodePath = ^"../Furniture/DeskB2/Schoolbag"
@export var bag_interactable_path: NodePath = ^"../Interactables/SchoolbagInspect"

@onready var _chair := get_node(chair_path) as PushableChair
@onready var _seat := get_node(seat_interactable_path) as SeatOffer
@onready var _bag := get_node(bag_path) as Bag
@onready var _inspect := get_node(bag_interactable_path) as StagedInteractable
var _shown := SeatOffer.Offer.NONE


func _ready() -> void:
	_seat.stage_handler = _stage_sit
	_inspect.stage_handler = _stage_search
	_bind_player.call_deferred()


func _bind_player() -> void:
	_seat.player = get_tree().get_first_node_in_group(player_group) as PlayerController
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
	else:
		_stop(player)
		if not await _approach(player, _chair.home_mark()):
			return {}
		await Motion.turn_to(player, -_chair.global_basis.z)
		player.sit_down(_chair)
	await _seat_transfer(player)
	return {}


func _stage_search(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	if player.is_seated():
		player.stand_up()
	await _seat_transfer(player)
	_stop(player)
	# Keep the original inspection usable if scenery is obstructed (including legacy
	# saves). Do not drag the body through the obstruction just to reach a mark.
	if await _approach(player, _bag.search_position()):
		await Motion.turn_to(player, -_bag.global_basis.z)
		await _bag.rummage(player)
	return {"inspection": _inspect.inspection_id}


func _seat_transfer(player: PlayerController) -> void:
	while player.is_seat_transition_active():
		await get_tree().physics_frame


func _stop(player: PlayerController) -> void:
	player.velocity.x = 0.0
	player.velocity.z = 0.0


## Try the direct path and the two flank routes around the desk/chair. Test the whole
## chosen route with the real capsule before moving; the section in front of the
## pushed chair is narrow enough that a diagonal corner-cut would hit the furniture.
func _approach(player: PlayerController, target: Vector3) -> bool:
	var start := player.global_position
	var origin := _chair.home_mark()
	var right := _chair.global_basis.x
	var forward := -_chair.global_basis.z
	var routes: Array[PackedVector3Array] = [PackedVector3Array([target])]
	for sign_side: float in [1.0, -1.0]:
		var flank := origin + right * sign_side * 0.81
		var same_row := flank + forward * forward.dot(start - flank)
		routes.append(PackedVector3Array([flank, target]))
		routes.append(PackedVector3Array([same_row, flank, target]))
		if target.distance_to(origin) > 0.1:
			# Bag at the other corner: cross the gap in front of the chair first.
			var aisle := origin + right * 0.81
			routes.append(PackedVector3Array([same_row, flank, aisle, target]))
	var best := PackedVector3Array()
	var best_length := INF
	for route in routes:
		var from := start
		var length := 0.0
		for point in route:
			point.y = start.y
			var leg := point - from
			var probe := Transform3D(player.global_basis, from + Vector3.UP * 0.035)
			if leg.length_squared() > 0.00001 and player.test_move(probe, leg):
				length = INF
				break
			length += leg.length()
			from = point
		if length < best_length:
			best_length = length
			best = route
	if best.is_empty():
		return false
	for point in best:
		if not await Motion.walk_to(player, point, 1.85):
			return false
	return true
