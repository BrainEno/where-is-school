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
## The protagonist walks it in third person, followed by the lab's camera in each room's
## framing. It is moved along a fixed path (`glide_to`) rather than pushed by synthetic
## keys, so the recording is identical on every run; it turns and animates as if it had
## walked. Each leg starts from wherever the character actually is, so when the
## corridor's far door moves it forty metres back, the next leg walks on from there — the
## loop is in the film, not edited around. The medium switch is the lab's own: the
## character's body crossing the threshold triggers it.

const Harness = preload("res://tests/test_harness.gd")

const LAB := "res://scenes/dev/visual_experiments/visual_experiments.tscn"
const FPS := 24.0
const WALK := 3.6
const JOG := 5.6
## feet, metres per second (walk if omitted), or a hold in seconds.
const LEGS := [
	{"feet": Vector3(0.0, 0.0, -2.5)},
	{"feet": Vector3(2.0, 0.0, -4.0)},
	{"hold": 0.8},
	{"feet": Vector3(0.0, 0.0, -9.5)},
	{"feet": Vector3(0.0, 0.0, -14.0)},
	{"feet": Vector3(0.0, 0.0, -30.0), "speed": JOG},
	{"feet": Vector3(0.0, 0.0, -54.7), "speed": JOG},
	{"hold": 1.0},
	{"feet": Vector3(0.0, 0.0, -38.6), "speed": JOG},
	{"feet": Vector3(0.3, 0.0, -40.0)},
	{"feet": Vector3(2.5, 0.0, -40.0)},
	{"feet": Vector3(8.6, 0.0, -40.0)},
	{"feet": Vector3(11.0, 0.0, -37.6)},
	{"feet": Vector3(16.5, 0.0, -38.0)},
	{"hold": 0.8},
	{"feet": Vector3(19.5, 0.0, -40.0)},
	{"feet": Vector3(26.6, 0.0, -40.0)},
	{"feet": Vector3(29.7, 0.0, -39.6)},
	{"feet": Vector3(30.0, 0.0, -36.4)},
	{"hold": 0.8},
	{"feet": Vector3(34.5, 0.0, -40.0)},
	{"feet": Vector3(38.5, 0.0, -40.0)},
	{"hold": 1.2},
	{"feet": Vector3(44.0, 0.0, -41.8)},
	{"feet": Vector3(48.5, 0.0, -46.5)},
	{"feet": Vector3(51.0, 0.0, -46.5)},
	{"feet": Vector3(51.8, 0.0, -44.6)},
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
	_lab.call("observe", Vector3(0.0, 0.0, 4.2), Vector3(0.0, 0.0, -6.0))
	await _frames(12)
	var recorded := 0
	var step_seconds := 1.0 / FPS
	for leg: Dictionary in LEGS:
		if leg.has("hold"):
			for _step in int(round(float(leg["hold"]) * FPS)):
				_observer.call("glide_to", _observer.global_position, step_seconds)
				await _frames(1)
				recorded += 1
			continue
		var from_feet: Vector3 = _observer.global_position
		from_feet.y = 0.0
		var to_feet: Vector3 = leg["feet"]
		var speed := float(leg.get("speed", WALK))
		var steps := maxi(1, int(round(from_feet.distance_to(to_feet) / speed * FPS)))
		var teleports_before := int(_observer.get("teleports"))
		for step in steps:
			# The corridor's far door moved the character: this leg ends where it was sent.
			if int(_observer.get("teleports")) != teleports_before:
				break
			var t := float(step + 1) / float(steps)
			_observer.call("glide_to", from_feet.lerp(to_feet, t), step_seconds)
			await _frames(1)
			recorded += 1
	_observer.call("stop_gliding")
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
