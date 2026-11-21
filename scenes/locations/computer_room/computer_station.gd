extends Node
## Owns one station in this room, not a new player state. Both actions enter via
## OpeningInteractions.run_staged(); the world stays locked until the terminal is off.

const Motion = preload("res://scripts/actors/staged_actor_motion.gd")
const PowerTarget = preload("res://scenes/locations/computer_room/terminal_power_hotspot.gd")
const SessionView = preload("res://scenes/locations/computer_room/terminal_session.gd")
const SESSION_SCENE := preload("res://scenes/locations/computer_room/terminal_session.tscn")

@onready var _chair: PushableChair = $"../StationChair1"
@onready var _seat: StagedInteractable = $"../Interactables/TerminalSeat"
@onready var _power: PowerTarget = $"../Interactables/TerminalPower"
@onready var _raster: MeshInstance3D = $"../Station1/Right/Raster"
@onready var _led: MeshInstance3D = $"../Station1/Right/Power"
@onready var _glow: OmniLight3D = $"../Station1/Right/BootGlow"

var _player: PlayerController
var _panel: SessionView
var _introduced := false
var _black := StandardMaterial3D.new()
var _screen := StandardMaterial3D.new()
var _lamp := StandardMaterial3D.new()


func _ready() -> void:
	_black.albedo_color = Color("181b22")
	_black.roughness = 0.4
	_screen.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp.albedo_color = Color("93e3af")
	_chair.bind_pick_target(_seat)
	_chair.snap_back()
	_seat.stage_handler = _sit
	_power.stage_handler = _boot
	_set_power(false)


func _physics_process(_delta: float) -> void:
	# Movement/click-to-walk can stand up without powering on. Restore the offer
	# after that transfer; a destination change never carries a seated player over.
	if _player == null or _player.is_seat_transition_active():
		return
	if not _at_station(_player):
		_player = null
		_power.sitter = null
		_seat.interaction_enabled = true
		_power.interaction_enabled = false


func _at_station(player: PlayerController) -> bool:
	return player.is_seated() and player.global_position.distance_to(_chair.home_mark()) < 0.09


func _sit(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	if player.is_seated() or player.is_seat_transition_active():
		return {}
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	if not await _approach(player):
		return {}
	await Motion.turn_to(player, -_chair.global_basis.z)
	if player.sit_down(_chair):
		await _transfer(player)
		if _at_station(player):
			_player = player
			_power.sitter = player
			_seat.interaction_enabled = false
			_power.interaction_enabled = true
	return {}


func _boot(director: Node) -> Dictionary:
	var player: PlayerController = director.get_player()
	if player != _player or not _at_station(player):
		return {}
	if _panel == null:
		_panel = SESSION_SCENE.instantiate() as SessionView
		_panel.started.connect(func() -> void: _introduced = true)
		add_child(_panel)
		_screen.albedo_texture = _panel.screen_texture()
	# The real indicator lights up before the cut to the glass. No automatic
	# launch from sitting down, entering the room, or examining the other CRT.
	_set_power(true)
	_panel.start(not _introduced)
	await _panel.closed
	_set_power(false)
	player.stand_up()
	await _transfer(player)
	# The moving chair is not a nav obstacle. Step clear of its pulled stop
	# before handing back click-to-walk, like stepping out from a desk.
	for offset: float in [0.84, -0.84]:
		if await Motion.walk_to(player, _chair.home_mark() + _chair.global_basis.x * offset):
			break
	return {}


func _set_power(on: bool) -> void:
	_raster.material_override = _screen if on else _black
	_led.material_override = _lamp if on else _black
	_glow.visible = on


func _transfer(player: PlayerController) -> void:
	while player.is_seat_transition_active():
		await get_tree().physics_frame


func _approach(player: PlayerController) -> bool:
	# The chair pulls back behind a capsule-width space. Approach that space from
	# either flank if the straight shot would cut through the pulled-out chair.
	var start := player.global_position
	var home := _chair.home_mark()
	var forward := -_chair.global_basis.z
	var routes: Array[PackedVector3Array] = [PackedVector3Array([home])]
	for side: float in [-1.0, 1.0]:
		var flank := home + _chair.global_basis.x * (side * 0.76)
		var aisle := flank + forward * forward.dot(start - flank)
		routes.append(PackedVector3Array([flank, home]))
		routes.append(PackedVector3Array([aisle, flank, home]))
	var best := PackedVector3Array()
	var length := INF
	for route: PackedVector3Array in routes:
		var from := start
		var travel := 0.0
		for point: Vector3 in route:
			point.y = start.y
			var leg := point - from
			if leg.length_squared() > 0.00001 and player.test_move(
					Transform3D(player.global_basis, from + Vector3.UP * 0.035), leg):
				travel = INF
				break
			travel += leg.length()
			from = point
		if travel < length:
			best = route
			length = travel
	if best.is_empty():
		return false
	for point: Vector3 in best:
		if not await Motion.walk_to(player, point, 1.85):
			return false
	return true
