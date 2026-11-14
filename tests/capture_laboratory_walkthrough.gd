extends SceneTree
## Records the laboratory walkthrough: the route a player actually takes from the entrance,
## past the drum, along the aisle, through the narrow door and into the room behind it.
##
## This is a *recording*, not a screenshot run: it is meant to be executed with Godot's
## movie maker, which renders at a fixed step and writes every frame to a file, so the
## result is reproducible frame for frame:
##
##   xvfb-run -a godot --path . --resolution 960x540 --rendering-driver opengl3 \
##     --write-movie build/walkthrough/frame.png --fixed-fps 24 \
##     --script res://tests/capture_laboratory_walkthrough.gd
##
## The camera is the game's own: the *player* is moved along the waypoints below and the
## follow camera (`CameraRig`) frames it, exactly as it does when someone holds W. The
## player is placed rather than pushed by synthetic input because the recording has to be
## the same every time it is rendered; what is being demonstrated is the space and the
## route through it, not the control system.
##
## The last frame is held for a second so the recording does not stop mid-move, then the
## loop quits. Nothing here runs in the headless checks.

const Harness = preload("res://tests/test_harness.gd")

const LABORATORY := "res://scenes/locations/laboratory/laboratory.tscn"
const FPS := 24.0
## feet, then what the player is looking at. Seconds after the previous waypoint.
const WAYPOINTS := [
	{"feet": Vector3(-2.4, 0.0, 2.8), "look": Vector3(0.7, 1.4, 1.0), "hold": 0.0},
	{"feet": Vector3(-3.1, 0.0, 2.6), "look": Vector3(-0.6, 1.3, 0.9), "hold": 2.6},
	{"feet": Vector3(-1.2, 0.0, 2.8), "look": Vector3(0.7, 1.3, 1.0), "hold": 2.4},
	{"feet": Vector3(1.3, 0.0, 2.3), "look": Vector3(1.4, 0.2, 0.2), "hold": 2.4},
	{"feet": Vector3(1.75, 0.0, 0.3), "look": Vector3(1.9, 0.4, -1.6), "hold": 2.6},
	{"feet": Vector3(1.8, 0.0, -1.9), "look": Vector3(2.5, 1.1, -2.85), "hold": 2.2},
	{"feet": Vector3(2.9, 0.0, -2.6), "look": Vector3(5.2, 1.6, -3.6), "hold": 2.4},
	{"feet": Vector3(4.3, 0.0, -2.9), "look": Vector3(6.8, 2.4, -3.5), "hold": 2.6},
	{"feet": Vector3(4.3, 0.0, -3.4), "look": Vector3(4.3, 1.3, -8.2), "hold": 2.8},
]
const FINAL_HOLD := 1.2

var _main: Node = null
var _player: PlayerController = null
var _rig: Node3D = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 900.0, "capture_laboratory_walkthrough.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)

	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		Harness.finish(self, ["main.tscn could not be loaded."], "")
		return
	_main = packed.instantiate()
	var sequence := _main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(_main)
	await _frames(4)

	var host := _main.get_node_or_null("LocationHost") as LocationHost
	_player = _main.get_node_or_null("Player") as PlayerController
	_rig = _main.get_node_or_null("CameraRig") as Node3D
	if host == null or _player == null or _rig == null:
		Harness.finish(self, ["main.tscn did not expose LocationHost, Player and CameraRig."], "")
		return
	var ui := _main.get_node_or_null("GameUI")
	if ui is CanvasLayer:
		(ui as CanvasLayer).visible = false
	if not host.load_location(LABORATORY, &"Entry", _player, &"laboratory"):
		Harness.finish(self, ["The laboratory did not load."], "")
		return
	await _frames(8)
	if sequence != null and sequence.has_method("allow_player_control"):
		sequence.call("allow_player_control")

	var first: Dictionary = WAYPOINTS[0]
	_place(first["feet"], first["look"])
	await _frames(4)

	var recorded := 0
	for index in range(1, WAYPOINTS.size()):
		var from: Dictionary = WAYPOINTS[index - 1]
		var to: Dictionary = WAYPOINTS[index]
		var seconds: float = float(to["hold"])
		var steps := maxi(1, int(round(seconds * FPS)))
		for step in steps:
			var t := float(step) / float(steps)
			var eased := t * t * (3.0 - 2.0 * t)
			_place(
				(from["feet"] as Vector3).lerp(to["feet"], eased),
				(from["look"] as Vector3).lerp(to["look"], eased)
			)
			await _frames(1)
			recorded += 1
	# Hold the last view, so the recording ends on the space rather than mid-move.
	for _step in int(round(FINAL_HOLD * FPS)):
		await _frames(1)
		recorded += 1
	print("LABORATORY_WALKTHROUGH %d frame(s) at %.0f fps" % [recorded, FPS])
	Harness.finish(self, [], "the walkthrough was rendered")


func _place(feet: Vector3, look: Vector3) -> void:
	var direction := look - feet
	var yaw := atan2(-direction.x, -direction.z)
	_player.teleport(Transform3D(Basis(Vector3.UP, yaw), feet))
	if _rig.has_method("snap"):
		_rig.call("snap")


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
