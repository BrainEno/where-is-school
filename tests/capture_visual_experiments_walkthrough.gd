extends SceneTree
## Records a walk through the visual experiments lab with Godot's movie maker: in through
## the collage room, down the corridor and through its loop, out by the giant door, across
## the staff room, through the classroom, over the threshold (the view turns into a
## painting) and round the back of the flats (it turns back).
##
##   xvfb-run -a godot --path . --resolution 960x540 --rendering-driver opengl3 \
##     --write-movie build/visual_walk/frame.png --fixed-fps 24 \
##     --script res://tests/capture_visual_experiments_walkthrough.gd
##
## The observer is placed on an eased path rather than pushed by synthetic keys, so the
## recording is identical on every run. Each leg starts from wherever the observer
## actually is, so when the corridor's far door moves it forty metres back, the next leg
## walks on from there — the loop is in the film, not edited around. The medium switch is
## the lab's own: the observer's body crossing the threshold triggers it.

const Harness = preload("res://tests/test_harness.gd")

const LAB := "res://scenes/dev/visual_experiments/visual_experiments.tscn"
const FPS := 24.0
## feet, what to look at, seconds for the leg (0 = hold where you are for `hold`).
const LEGS := [
	{"feet": Vector3(0.0, 0.0, -2.0), "look": Vector3(-3.0, 1.2, -10.0), "seconds": 3.0},
	{"feet": Vector3(0.8, 0.0, -3.2), "look": Vector3(1.9, 0.6, -4.6), "seconds": 2.5},
	{"feet": Vector3(0.0, 0.0, -9.5), "look": Vector3(0.0, 1.5, -14.0), "seconds": 2.6},
	{"feet": Vector3(0.0, 0.0, -14.0), "look": Vector3(0.0, 1.3, -40.0), "seconds": 2.0},
	{"feet": Vector3(0.0, 0.0, -30.0), "look": Vector3(0.0, 1.2, -56.0), "seconds": 4.0},
	{"feet": Vector3(0.0, 0.0, -54.7), "look": Vector3(0.0, 1.0, -58.0), "seconds": 4.0},
	{"hold": 1.2},
	{"feet": Vector3(0.0, 0.0, -39.6), "look": Vector3(1.4, 2.6, -40.0), "seconds": 5.0},
	{"feet": Vector3(2.5, 0.0, -40.0), "look": Vector3(8.0, 1.4, -40.0), "seconds": 2.0},
	{"feet": Vector3(8.6, 0.0, -40.0), "look": Vector3(14.0, 1.2, -40.0), "seconds": 2.6},
	{"feet": Vector3(11.0, 0.0, -37.5), "look": Vector3(14.4, 0.4, -40.4), "seconds": 3.0},
	{"feet": Vector3(19.5, 0.0, -40.0), "look": Vector3(26.0, 1.4, -40.0), "seconds": 3.0},
	{"feet": Vector3(26.6, 0.0, -40.0), "look": Vector3(32.0, 1.4, -39.0), "seconds": 2.4},
	{"feet": Vector3(29.7, 0.0, -39.6), "look": Vector3(36.0, 1.4, -40.0), "seconds": 1.8},
	{"feet": Vector3(29.7, 0.0, -36.4), "look": Vector3(30.0, 1.7, -34.1), "seconds": 2.2},
	{"feet": Vector3(34.6, 0.0, -36.8), "look": Vector3(38.0, 1.4, -40.0), "seconds": 2.0},
	{"feet": Vector3(34.5, 0.0, -40.0), "look": Vector3(40.0, 1.4, -40.0), "seconds": 2.0},
	{"feet": Vector3(38.5, 0.0, -40.0), "look": Vector3(48.0, 1.5, -40.0), "seconds": 2.2},
	{"hold": 1.2},
	{"feet": Vector3(44.0, 0.0, -41.8), "look": Vector3(47.6, 1.3, -39.1), "seconds": 3.0},
	{"feet": Vector3(48.5, 0.0, -46.5), "look": Vector3(52.0, 1.3, -46.5), "seconds": 3.0},
	{"feet": Vector3(51.0, 0.0, -46.5), "look": Vector3(52.0, 1.3, -44.0), "seconds": 1.8},
	{"feet": Vector3(51.8, 0.0, -44.6), "look": Vector3(46.0, 1.3, -39.0), "seconds": 2.4},
]
const FINAL_HOLD := 1.4

var _lab: Node3D = null
var _observer: Node3D = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 1800.0, "capture_visual_experiments_walkthrough.gd")
	call_deferred("_run")


func _run() -> void:
	var packed := load(LAB) as PackedScene
	if packed == null:
		Harness.finish(self, ["The visual experiments lab could not be loaded."], "")
		return
	_lab = packed.instantiate() as Node3D
	root.add_child(_lab)
	_lab.call("set_hud_visible", false)
	_observer = _lab.get_node("Observer") as Node3D
	_lab.call("observe", Vector3(0.0, 0.0, 4.2), Vector3(0.0, 1.4, -6.0))
	await _frames(12)
	var recorded := 0
	var look := Vector3(0.0, 1.4, -6.0)
	for leg: Dictionary in LEGS:
		if leg.has("hold"):
			for _step in int(round(float(leg["hold"]) * FPS)):
				await _frames(1)
				recorded += 1
			continue
		var from_feet: Vector3 = _observer.global_position
		from_feet.y = 0.0
		var from_look := look
		var to_feet: Vector3 = leg["feet"]
		var to_look: Vector3 = leg["look"]
		var steps := maxi(1, int(round(float(leg["seconds"]) * FPS)))
		var teleports_before := int(_observer.get("teleports"))
		for step in steps:
			# The corridor's far door moved the observer: this leg ends where it was sent.
			if int(_observer.get("teleports")) != teleports_before:
				break
			var t := float(step + 1) / float(steps)
			var eased := t * t * (3.0 - 2.0 * t)
			look = from_look.lerp(to_look, eased)
			_lab.call("observe", from_feet.lerp(to_feet, eased), look)
			await _frames(1)
			recorded += 1
	for _step in int(round(FINAL_HOLD * FPS)):
		await _frames(1)
		recorded += 1
	print(
		"VISUAL_LAB_WALKTHROUGH %d frame(s) at %.0f fps, loops %d, medium switches %d"
		% [
			recorded, FPS, int(_lab.get_node("Zones/Corridor").get("loop_count")),
			int(_lab.get_node("MediumSwitch").call("get_switch_count")),
		]
	)
	Harness.finish(self, [], "the visual experiments walkthrough was rendered")


func _frames(count: int) -> void:
	for _index in count:
		await process_frame
