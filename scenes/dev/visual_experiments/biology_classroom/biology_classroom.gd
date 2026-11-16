extends Node3D
## 生物课教室美术重构实验 — the biology classroom, redrawn. Open
## `biology_classroom.tscn` and press F6.
##
## The idea (docs/BIOLOGY_CLASSROOM_EXPERIMENT.md has the long form): the room is not a
## place with a mood on top, it is a drawing whose **register** changes with what the
## protagonist is attending to. One material carries the whole interior, and the story
## beats move its few controls:
##
##   1 醒来 wake        the room arrives around one desk: everything else sunk in shade
##                      until he stands up
##   2 生物课 lesson    B is mentioned and B is not here. The lectern's shadow climbs the
##                      front wall as somebody tall and stooped; the set square's shadow
##                      runs across the floor to his desk; the warm room cools to ink;
##                      the lectern is taller than it is. Stronger the nearer you go.
##   3 没有课本 no book the room is ordinary again; the desk holds the outline of a book
##                      that is not there
##   4 铃声与 N bell    the fluorescent hour: colour drains, the tubes come on, N walks in
##                      from the corridor and stands beside the lectern, not behind it
##
## and two moments that are not beats:
##
##   the curtain        behind it is a blank sheet. Drawing it puts the picture itself on
##                      paper: the room becomes a pencil drawing on an answer sheet,
##                      spreading from the window, and a red pencil circles where you
##                      stand. Lean out and the blank gives way: you fall into colour,
##                      into the yard below
##   the door           opens onto an open corridor in daylight. Q comes to the doorway
##                      and no further
##
## The dialogue strip at the bottom shows *where* lines would sit and how the impression
## of B presses on them; it carries stage notes, never lines (the script is not ours).
##
## Controls (also on the HUD): WASD walk (relative to the camera), Shift faster, Q / E turn
## the view, wheel zoom, R reset the view, F free camera, Space interact, 1-4 jump to a
## beat, 0 start over, M paper on/off, H hide the HUD, P print a performance sample.

const Room := preload("res://scenes/dev/visual_experiments/biology_classroom/room.gd")
const Art := preload("res://scenes/dev/visual_experiments/biology_classroom/room_art.gd")
const QPresence := preload("res://scenes/dev/visual_experiments/biology_classroom/q_presence.gd")
const Kit := preload("res://scenes/dev/visual_experiments/collage_kit.gd")
const N_SCENE := preload("res://scenes/environment/characters/teacher_n.tscn")

const WAKE := 1
const LESSON := 2
const NO_BOOK := 3
const BELL := 4
const BEAT_TITLES := {
	WAKE: "第 1 段 · 醒来",
	LESSON: "第 2 段 · 生物课",
	NO_BOOK: "第 3 段 · 没有课本",
	BELL: "第 4 段 · 铃声与 N",
}

## Framings: (yaw degrees, pitch degrees, distance). Yaw 0 = camera south looking north,
## 90 = camera east looking west (the visual lab's observer).
const FRAMING_ROOM := Vector3(40.0, 50.0, 9.5)
const FRAMING_SEATED := Vector3(26.0, 34.0, 4.6)
const FRAMING_LECTERN := Vector3(24.0, 15.0, 4.8)
const FRAMING_CURTAIN := Vector3(100.0, 28.0, 6.2)
const FRAMING_CORRIDOR := Vector3(90.0, 36.0, 7.5)
const FRAMING_YARD := Vector3(-90.0, 12.0, 10.0)

const INTERACT_RADIUS := 1.5
const PAPER_ON_DISTANCE := 4.5
const PAPER_OFF_DISTANCE := 5.5
const GET_UP_SECONDS := 1.3
const SLUMP_DEGREES := 12.0
const LEAN_SECONDS := 0.75
const LEAN_DEGREES := 38.0
const DROP_SECONDS := 0.45
const DROP_DEGREES := 85.0
const DROP_DEPTH := 2.4
const FALL_ROLL_DEGREES := -9.0
const N_WALK_SPEED := 1.3
const N_SPOT := Vector3(0.6, Room.PLATFORM_HEIGHT, -3.2)
const N_ROUTE: Array[Vector3] = [
	Vector3(9.8, 0.0, -6.6), Vector3(9.8, 0.0, -4.4), Vector3(8.0, 0.0, -3.55),
	Vector3(6.4, 0.0, -3.55), Vector3(4.4, 0.0, -1.5), Vector3(0.6, 0.0, -1.5), N_SPOT,
]
const CORRIDOR_ARRIVAL := Vector3(8.0, 0.0, -4.85)
const YARD_DOOR_FEET := Vector3(-8.0, Room.YARD_Y, Room.YARD_DOOR_Z)

## The current beat (1-4).
var beat: int = WAKE
## True while the protagonist sits at his desk.
var seated: bool = false
## True while a scripted moment holds the controls (getting up, the fall, a fade).
var locked: bool = false
var curtain_open: bool = false
var searched: bool = false
var door_open: bool = false
var falls: int = 0
## Smoothed registers (0-1), applied to the room every frame.
var b_weight: float = 0.0
var dull: float = 0.0
var focus: float = 0.0
var outside: float = 0.0
var lamp_level: float = 0.0

var _curtain_amount: float = 0.0
var _door_amount: float = 0.0
var _book_amount: float = 0.0
var _ring_amount: float = 0.0
var _ring_drawing: bool = false
var _forced_b: float = -1.0
var _bell_timer: float = -1.0
var _flicker: float = 0.0
var _observing: bool = false
var _framing_key: Vector3 = Vector3.ZERO
var _say_timer: float = 0.0
var _n: Node3D = null
var _n_route: Array[Vector3] = []
var _n_delay: float = 0.0
var _n_standing: bool = false
var _hud_shown: bool = true

@onready var room: Node3D = $Room
@onready var observer: CharacterBody3D = $Observer
@onready var camera: Camera3D = $Observer/CameraRig/Camera3D
@onready var paper: Node = $PaperSwitch
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var q: Node3D = null
var _hud: CanvasLayer = null
var _hud_text: Label = null
var _prompt: Label = null
var _dialogue: Control = null
var _speaker: Label = null
var _line: Label = null
var _intrusion: Polygon2D = null
var _fade: ColorRect = null


func _ready() -> void:
	_build_environment()
	q = QPresence.new()
	q.name = "QPresence"
	add_child(q)
	paper.call("bind", camera)
	paper.call("set_origin", Room.opening_centre())
	_build_hud()
	reset_experiment()


# --- Public: the captures and the test drive the scene through these ----------------------


## Back to the start: seated at the desk, beat 1, curtain shut, door shut, Q at home.
func reset_experiment() -> void:
	locked = false
	_observing = false
	curtain_open = false
	searched = false
	door_open = false
	_curtain_amount = 0.0
	_door_amount = 0.0
	_book_amount = 0.0
	_ring_amount = 0.0
	_ring_drawing = false
	_bell_timer = -1.0
	_forced_b = -1.0
	room.call("set_curtain_open", 0.0)
	room.call("set_door_open", 0.0)
	(room.get("ring_mark") as Node3D).visible = false
	(room.get("blank_sheet") as Node3D).visible = true
	paper.call("set_paper", false, true)
	_remove_n()
	beat = WAKE
	q.call("set_place_instant", QPresence.Place.HOME)
	room.call("set_clock", 10, 52)
	_sit_down(true)
	focus = 1.0
	snap_registers()
	_say("", "")


func set_beat(value: int, instant: bool = false) -> void:
	var previous := beat
	beat = clampi(value, WAKE, BELL)
	if beat == BELL and previous != BELL:
		_start_bell(instant)
	elif beat != BELL and previous == BELL:
		_remove_n()
		room.call("set_clock", 10, 52)
		q.call("go", QPresence.Place.HOME)
	if beat < NO_BOOK:
		searched = false
	if instant:
		snap_registers()


## Places the protagonist (standing) and asks for the framing of where he is.
func observe(feet: Vector3, target: Vector3, framing: Vector3 = Vector3.ZERO) -> void:
	if seated:
		_stand_up(true)
	observer.call("place", feet, target)
	_update_framing(true)
	if framing != Vector3.ZERO:
		observer.call("set_framing", framing, true)


## A free camera at `eye` looking at `target`; the character stays where it is.
func look_from(eye: Vector3, target: Vector3) -> void:
	observer.call("director", eye, target)


func set_hud_visible(shown: bool) -> void:
	_hud_shown = shown
	if _hud != null:
		_hud.visible = shown


## Overrides the impression of B (captures); a negative value hands it back to the beats.
func force_b(value: float) -> void:
	_forced_b = value


## Draws the curtain. `instant` skips the cloth's movement and the paper's spread.
func open_curtain(instant: bool = false) -> void:
	if curtain_open:
		return
	curtain_open = true
	q.call("go", QPresence.Place.WINDOW)
	if instant:
		_curtain_amount = 1.0
		room.call("set_curtain_open", 1.0)
		if _near_opening(PAPER_ON_DISTANCE):
			paper.call("set_paper", true, true)
			_place_ring()
			_ring_amount = 1.0
			_ring_drawing = false
			Room.set_mark_amount(room.get("ring_mark") as MeshInstance3D, 1.0)


func open_door(open: bool = true) -> void:
	door_open = open


## Shows the current beat's stage note in the dialogue strip without moving the story on.
func show_note_for_beat() -> void:
	match beat:
		WAKE:
			_say("Q", "［占位］Q 逗他。他还想不起 Q 是谁。")
		LESSON:
			_say("Q", "［占位］Q 提起上学期的白卷和零分，说 B 可能会打手心。")
		NO_BOOK:
			_say("Q", "［占位］他没有课本。Q 说可以去旁边的班要一本，或者在座位上再找找。")
		_:
			_say("N", "［占位］N 没有准备，说这节课自由活动。")


func search_desk() -> void:
	searched = true
	_say("书桌", "［占位］书桌里、书包里，都没有生物课本。只有它该在的地方。")
	if beat == NO_BOOK and _bell_timer < 0.0:
		_bell_timer = 2.8


## Snaps every smoothed register to its target (captures, tests, resets).
func snap_registers() -> void:
	b_weight = _b_target()
	dull = _dull_target()
	focus = _focus_target() if seated else 0.0
	outside = _outside_target()
	lamp_level = 1.0 if beat == BELL else 0.0
	_curtain_amount = 1.0 if curtain_open else 0.0
	_door_amount = 1.0 if door_open else 0.0
	room.call("set_curtain_open", _curtain_amount)
	room.call("set_door_open", _door_amount)
	_apply_registers()


func framing_at(point: Vector3) -> Vector3:
	if Room.is_in_yard(point):
		return FRAMING_YARD
	if Room.is_in_corridor(point):
		return FRAMING_CORRIDOR
	if seated:
		return FRAMING_SEATED
	if point.x < -2.8 and point.z < -0.9:
		return FRAMING_LECTERN
	if point.x < -4.4 and point.z > 0.2 and point.z < 4.2:
		return FRAMING_CURTAIN
	return FRAMING_ROOM


func current_zone() -> StringName:
	var feet := observer.global_position
	if Room.is_in_yard(feet):
		return &"yard"
	if Room.is_in_corridor(feet):
		return &"corridor"
	var framing := framing_at(feet)
	if framing == FRAMING_LECTERN:
		return &"lectern"
	if framing == FRAMING_CURTAIN:
		return &"curtain"
	return &"classroom"


func n_actor() -> Node3D:
	return _n


func is_n_standing() -> bool:
	return _n_standing


func sample_performance(frames: int = 30) -> Dictionary:
	var draw_calls := 0.0
	var primitives := 0.0
	var objects := 0.0
	var frame_ms := 0.0
	var worst_ms := 0.0
	var tree := get_tree()
	await tree.process_frame
	var last := Time.get_ticks_usec()
	for _frame in frames:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - last) / 1000.0
		last = now
		frame_ms += elapsed
		worst_ms = maxf(worst_ms, elapsed)
		draw_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		objects += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	var count := float(maxi(frames, 1))
	return {
		"renderer": RenderingServer.get_current_rendering_method(),
		"draw_calls": snappedf(draw_calls / count, 0.1),
		"primitives": int(primitives / count),
		"objects": snappedf(objects / count, 0.1),
		"frame_ms": snappedf(frame_ms / count, 0.01),
		"worst_ms": snappedf(worst_ms, 0.01),
		"video_mem_mib": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mib": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"generated_texture_kib": int((Art.generated_bytes() + Kit.generated_bytes()) / 1024),
		"paper": bool(paper.call("is_on")),
		"beat": beat,
	}


# --- Input ---------------------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE, KEY_ENTER:
			if not locked:
				_interact()
		KEY_1:
			set_beat(WAKE)
		KEY_2:
			set_beat(LESSON)
		KEY_3:
			set_beat(NO_BOOK)
		KEY_4:
			set_beat(BELL)
		KEY_0:
			reset_experiment()
		KEY_M:
			paper.call("set_paper", not bool(paper.call("is_on")))
		KEY_H:
			set_hud_visible(not _hud_shown)
		KEY_P:
			var sample: Dictionary = await sample_performance(30)
			print("BIOLOGY_CLASSROOM_PERF %s" % JSON.stringify(sample))


func _moving_keys_held() -> bool:
	for keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		if Input.is_key_pressed(keycode):
			return true
	return false


# --- Frame ---------------------------------------------------------------------------------


func _physics_process(_delta: float) -> void:
	if seated and not locked and _moving_keys_held():
		_stand_up(false)
	if _observing and _moving_keys_held():
		_observing = false
		observer.call("set_free_camera", false)
	var feet := observer.global_position
	q.set("look_target", feet)
	q.set("has_look_target", true)
	# Q's place follows what the protagonist does, never where he is: he comes to the
	# door when you go out of it, goes back when you come in.
	var in_corridor := Room.is_in_corridor(feet)
	if beat != BELL:
		if in_corridor:
			q.call("go", QPresence.Place.THRESHOLD)
		elif Room.is_inside_room(feet) and int(q.get("place")) == QPresence.Place.THRESHOLD:
			q.call("go", QPresence.Place.HOME)
	if curtain_open and not locked:
		if bool(paper.call("is_on")):
			if not _near_opening(PAPER_OFF_DISTANCE):
				paper.call("set_paper", false)
		elif _near_opening(PAPER_ON_DISTANCE):
			paper.call("set_paper", true)
	if not locked and not _observing:
		_update_framing(false)


func _process(delta: float) -> void:
	_curtain_amount = move_toward(_curtain_amount, 1.0 if curtain_open else 0.0, delta / 1.2)
	room.call("set_curtain_open", _curtain_amount)
	_door_amount = move_toward(_door_amount, 1.0 if door_open else 0.0, delta / 0.6)
	room.call("set_door_open", _door_amount)
	if curtain_open and _curtain_amount >= 1.0 and bool(paper.call("is_on")) \
			and float(paper.call("get_reveal")) >= 0.98 and not _ring_drawing and _ring_amount <= 0.0:
		_place_ring()
		_ring_drawing = true
	if _ring_drawing:
		_ring_amount = move_toward(_ring_amount, 1.0, delta / 1.4)
		Room.set_mark_amount(room.get("ring_mark") as MeshInstance3D, _ring_amount)
		if _ring_amount >= 1.0:
			_ring_drawing = false
	_book_amount = move_toward(_book_amount, 1.0 if searched else 0.0, delta / 1.0)
	Room.set_mark_amount(room.get("book_mark") as MeshInstance3D, _book_amount)
	if _bell_timer >= 0.0:
		_bell_timer -= delta
		if _bell_timer < 0.0:
			set_beat(BELL)
	_update_n(delta)
	var rate_b := 0.7 * delta
	b_weight = move_toward(b_weight, _b_target(), rate_b)
	dull = move_toward(dull, _dull_target(), 0.8 * delta)
	focus = move_toward(focus, _focus_target(), 0.35 * delta)
	outside = move_toward(outside, _outside_target(), 1.2 * delta)
	_update_lamps(delta)
	_apply_registers()
	_update_hud(delta)


# --- Registers -----------------------------------------------------------------------------


func _lectern_nearness() -> float:
	var feet := observer.global_position
	var distance := Vector2(feet.x - Room.LECTERN.x, feet.z - Room.LECTERN.z).length()
	return clampf(1.0 - (distance - 1.3) / 3.2, 0.0, 1.0)


func _b_target() -> float:
	if _forced_b >= 0.0:
		return _forced_b
	var feet := observer.global_position
	if not Room.is_inside_room(feet):
		return 0.0
	var near := _lectern_nearness()
	match beat:
		LESSON:
			return 0.55 + 0.45 * near
		BELL:
			return 0.12 * near
		_:
			return 0.35 * near


func _dull_target() -> float:
	return 1.0 if beat == BELL else 0.0


func _focus_target() -> float:
	return 1.0 if seated and beat == WAKE else 0.0


func _outside_target() -> float:
	var feet := observer.global_position
	return 1.0 if Room.is_in_corridor(feet) or Room.is_in_yard(feet) else 0.0


func _apply_registers() -> void:
	var material := room.get("room_material") as ShaderMaterial
	material.set_shader_parameter("chill", b_weight * 0.85)
	material.set_shader_parameter("dull", dull * 0.6)
	material.set_shader_parameter("focus_amount", focus * 0.85)
	var warm := Color(1.0, 0.86, 0.66)
	var cold := Color(0.72, 0.8, 1.0)
	var fluorescent := Color(0.94, 0.98, 0.95)
	sun.light_color = warm.lerp(cold, b_weight).lerp(fluorescent, dull * 0.6)
	sun.light_energy = lerpf(1.35, 0.95, b_weight)
	var environment := world_environment.environment
	var inside_ambient := Color(0.44, 0.38, 0.52).lerp(Color(0.22, 0.26, 0.44), b_weight)
	inside_ambient = inside_ambient.lerp(Color(0.5, 0.52, 0.5), dull)
	environment.ambient_light_color = inside_ambient.lerp(Color(0.62, 0.66, 0.72), outside)
	var inside_background := Color(0.11, 0.09, 0.15).lerp(Color(0.05, 0.06, 0.12), b_weight)
	inside_background = inside_background.lerp(Color(0.16, 0.17, 0.16), dull)
	environment.background_color = inside_background.lerp(Color(0.72, 0.8, 0.86), outside)
	var b_shadow := room.get("b_shadow") as MeshInstance3D
	Room.set_mark_amount(b_shadow, smoothstep(0.12, 0.85, b_weight))
	Room.set_mark_amount(room.get("square_shadow") as MeshInstance3D, (b_weight - 0.45) / 0.45)
	Room.set_mark_opacity(room.get("chalk_overlay") as MeshInstance3D, 0.22 + 0.55 * b_weight)
	room.call("set_lectern_stretch", (b_weight - 0.3) / 0.6)
	if _intrusion != null:
		_intrusion.scale = Vector2.ONE * clampf((b_weight - 0.2) / 0.7, 0.0, 1.0)
		_intrusion.visible = _intrusion.scale.x > 0.01
		_dialogue.modulate = Color.WHITE.lerp(Color(0.78, 0.84, 1.0), b_weight)


func _update_lamps(delta: float) -> void:
	var target := 1.0 if beat == BELL else 0.0
	if target > 0.0 and lamp_level < 1.0:
		# Fluorescent tubes do not fade up: they catch, fail, and catch.
		_flicker += delta
		lamp_level = minf(1.0, _flicker / 1.1)
		var shown := lamp_level if fmod(_flicker, 0.23) > 0.08 or lamp_level >= 1.0 else 0.15
		room.call("set_lamps", shown)
	elif target <= 0.0:
		_flicker = 0.0
		lamp_level = 0.0
		room.call("set_lamps", 0.0)
	else:
		room.call("set_lamps", 1.0)


func _update_framing(instant: bool) -> void:
	var framing := framing_at(observer.global_position)
	if not instant and framing == _framing_key:
		return
	_framing_key = framing
	observer.call("set_framing", framing, instant)


# --- Interactions --------------------------------------------------------------------------


## What Space would do here, as a key and a prompt; empty key = nothing.
func current_interaction() -> Array:
	var feet := observer.global_position
	if seated:
		return [&"", "移动键 站起来"]
	if Room.is_in_yard(feet):
		if _flat_distance(feet, YARD_DOOR_FEET) < 2.0:
			return [&"stair_up", "空格 上楼，回到走廊"]
		return [&"", ""]
	if Room.is_in_corridor(feet):
		if _flat_distance(feet, Room.door_centre()) < INTERACT_RADIUS:
			return [&"door", "空格 关门" if door_open else "空格 开门"]
		if feet.z < -4.0:
			return [&"stair_down", "空格 下楼，去操场"]
		if absf(feet.z - Room.NEIGHBOUR_DOOR_Z) < 1.2:
			return [&"neighbour", "空格 看看旁边的班"]
		return [&"", ""]
	if _n_standing and _flat_distance(feet, _n.global_position) < 1.8:
		return [&"n", "空格 问 N 关于 B"]
	if _flat_distance(feet, q.global_position) < 1.6:
		return [&"q", "空格 和 Q 说话"]
	if _flat_distance(feet, Room.door_centre()) < INTERACT_RADIUS:
		return [&"door", "空格 关门" if door_open else "空格 开门"]
	if _near_opening(2.2):
		return [&"curtain", "空格 探身出去" if curtain_open else "空格 拉开窗帘"]
	if _flat_distance(feet, Room.LECTERN) < 1.9:
		return [&"lectern", "空格 离开讲台" if _observing else "空格 看讲台"]
	if _flat_distance(feet, Room.seat_feet(Room.PLAYER_DESK)) < 1.1:
		if beat == NO_BOOK and not searched:
			return [&"search", "空格 翻书桌和书包"]
		return [&"sit", "空格 坐下"]
	return [&"", ""]


func _interact() -> void:
	var action: StringName = current_interaction()[0]
	match action:
		&"q":
			_talk_to_q()
		&"n":
			_say("N", "［占位］问起 B，N 答得含糊：他也不清楚，只说这节课自由活动。")
		&"door":
			open_door(not door_open)
		&"curtain":
			if curtain_open:
				_fall()
			else:
				open_curtain(false)
		&"lectern":
			_observe_lectern()
		&"search":
			search_desk()
		&"sit":
			_sit_down(false)
		&"stair_down":
			_travel(YARD_DOOR_FEET + Vector3(-0.8, 0.0, 0.0), YARD_DOOR_FEET + Vector3(-4.0, 0.0, 0.0))
		&"stair_up":
			_travel(CORRIDOR_ARRIVAL, CORRIDOR_ARRIVAL + Vector3(0.0, 0.0, 2.0))
		&"neighbour":
			_say("旁边的班", "［占位］门关着。去要课本的那一段，留给后续剧情。")


func _talk_to_q() -> void:
	if beat == BELL:
		_say("Q", "［占位］自由活动。Q 坐在自己的位子上，没有跟来。")
		return
	show_note_for_beat()
	if beat == WAKE:
		set_beat(LESSON)
	elif beat == LESSON:
		set_beat(NO_BOOK)


func _observe_lectern() -> void:
	if _observing:
		_observing = false
		observer.call("set_free_camera", false)
		return
	_observing = true
	var top := Room.LECTERN + Vector3(0.0, Room.LECTERN_SIZE.y, 0.0)
	look_from(top + Vector3(1.5, 0.9, 1.5), top + Vector3(-0.1, 0.0, 0.0))
	_say("讲台", "三角尺（裂过，用胶带缠着），点名册和一支红笔，粉笔盒，靠在一边的教杆。")


func _near_opening(distance: float) -> bool:
	var feet := observer.global_position
	return Room.is_inside_room(feet) and _flat_distance(feet, Room.opening_centre()) < distance


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _place_ring() -> void:
	var ring := room.get("ring_mark") as MeshInstance3D
	var feet := observer.global_position
	ring.global_position = Vector3(feet.x, feet.y + 0.008, feet.z)
	ring.visible = true
	_ring_amount = 0.0
	Room.set_mark_amount(ring, 0.0)


# --- Seated, standing ----------------------------------------------------------------------


func _sit_down(instant: bool) -> void:
	var feet := Room.seat_feet(Room.PLAYER_DESK)
	_observing = false
	observer.call("set_framing", FRAMING_SEATED, true)
	observer.call("place", feet, feet + Vector3(0.0, 0.0, -2.0))
	observer.set_physics_process(false)
	seated = true
	var visual := observer.get("visual") as Node3D
	visual.rotation_degrees.x = SLUMP_DEGREES
	var character := observer.call("character") as Node3D
	if character != null and character.has_method("set_seated"):
		character.call("set_seated", true)
	_framing_key = FRAMING_SEATED
	if not instant:
		focus = maxf(focus, 0.5)


func _stand_up(instant: bool) -> void:
	if not seated:
		return
	seated = false
	var visual := observer.get("visual") as Node3D
	var character := observer.call("character") as Node3D
	if character != null and character.has_method("set_seated"):
		character.call("set_seated", false)
	if instant:
		visual.rotation_degrees.x = 0.0
		observer.set_physics_process(true)
		return
	locked = true
	if character != null and character.has_method("play_action"):
		character.call("play_action", "get_up", GET_UP_SECONDS)
	var tween := create_tween()
	tween.tween_property(visual, "rotation_degrees:x", 0.0, GET_UP_SECONDS)
	await tween.finished
	observer.set_physics_process(true)
	locked = false
	_update_framing(false)


# --- The fall, and the ways back -----------------------------------------------------------


func _fall() -> void:
	locked = true
	falls += 1
	observer.set_physics_process(false)
	observer.call("stop_gliding")
	var visual := observer.get("visual") as Node3D
	var feet := observer.global_position
	var toward := Room.opening_centre() - feet
	toward.y = 0.0
	var yaw := atan2(toward.x, toward.z)
	visual.rotation = Vector3(0.0, yaw, 0.0)
	var forward := Vector3(sin(yaw), 0.0, cos(yaw))
	var distance := toward.length()
	var rest := visual.position
	var lean_reach := clampf(distance - 0.45, 0.3, 1.1)
	var lean := create_tween()
	lean.set_parallel(true)
	lean.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lean.tween_property(visual, "rotation_degrees:x", LEAN_DEGREES, LEAN_SECONDS)
	lean.tween_property(visual, "position", rest + Vector3(0.0, 0.3, 0.0) + forward * lean_reach, LEAN_SECONDS)
	await lean.finished
	# The blank gives way: the sheet is gone, the paper lifts, and he drops into colour.
	(room.get("blank_sheet") as Node3D).visible = false
	paper.call("set_paper", false)
	var drop := create_tween()
	drop.set_parallel(true)
	drop.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	drop.tween_property(visual, "rotation_degrees:x", DROP_DEGREES, DROP_SECONDS)
	drop.tween_property(visual, "position", rest + Vector3(0.0, -DROP_DEPTH, 0.0) + forward * (distance + 0.6), DROP_SECONDS)
	drop.tween_property(camera, "rotation_degrees:z", FALL_ROLL_DEGREES, DROP_SECONDS)
	await _fade_to(1.0, 0.6)
	paper.call("set_paper", false, true)
	visual.rotation = Vector3.ZERO
	visual.position = rest
	camera.rotation = Vector3.ZERO
	(room.get("blank_sheet") as Node3D).visible = true
	observer.call("set_framing", FRAMING_YARD, true)
	observer.call("place", Room.LANDING, Room.LANDING + Vector3(-3.0, 0.0, 0.0))
	_framing_key = FRAMING_YARD
	var character := observer.call("character") as Node3D
	if character != null and character.has_method("set_seated"):
		character.call("set_seated", true)
		character.call("set_seated", false)
		character.call("play_action", "get_up", GET_UP_SECONDS)
	await _fade_to(0.0, 0.9)
	observer.set_physics_process(true)
	locked = false


## Stairs: the screen goes dark, and you are at the other end.
func _travel(feet: Vector3, target: Vector3) -> void:
	locked = true
	await _fade_to(1.0, 0.45)
	observer.call("place", feet, target)
	_update_framing(true)
	await _fade_to(0.0, 0.55)
	locked = false


func _fade_to(alpha: float, seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, seconds)
	await tween.finished


# --- The bell and N ------------------------------------------------------------------------


func _start_bell(instant: bool) -> void:
	_say("", "［铃声］")
	q.call("go", QPresence.Place.SEAT)
	var clock := create_tween()
	clock.tween_method(_set_clock_minutes, 52.0, 60.0, 0.01 if instant else 0.8)
	_remove_n()
	_n = N_SCENE.instantiate() as Node3D
	_n.name = "TeacherN"
	add_child(_n)
	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.sync_to_physics = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.65
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.83, 0.0)
	body.add_child(shape)
	_n.add_child(body)
	if instant:
		_n.position = N_SPOT
		_face_n(Vector3(0.0, 0.0, 1.0), 1.0)
		_n_route.clear()
		_n_standing = true
		_say("N", "［占位］N 没有准备，说这节课自由活动。")
		return
	_n.position = N_ROUTE[0]
	_n_route = N_ROUTE.duplicate()
	_n_route.remove_at(0)
	_n_delay = 2.5
	_n.visible = false
	_n_standing = false


func _set_clock_minutes(minutes: float) -> void:
	var whole := int(round(minutes))
	if whole >= 60:
		room.call("set_clock", 11, 0)
	else:
		room.call("set_clock", 10, whole)


func _remove_n() -> void:
	if _n != null and is_instance_valid(_n):
		_n.queue_free()
	_n = null
	_n_route.clear()
	_n_standing = false


func _update_n(delta: float) -> void:
	if _n == null or _n_route.is_empty():
		return
	if _n_delay > 0.0:
		_n_delay -= delta
		if _n_delay <= 0.0:
			_n.visible = true
			door_open = true
		return
	var goal: Vector3 = _n_route[0]
	var to_goal := goal - _n.position
	to_goal.y = 0.0
	var step := N_WALK_SPEED * delta
	var moved := to_goal
	if to_goal.length() <= step:
		_n_route.remove_at(0)
	else:
		moved = to_goal.normalized() * step
	_n.position += moved
	# Up the platform's ramp.
	if _n.position.x < Room.PLATFORM_MAX.x:
		var onto := clampf((Room.PLATFORM_MAX.y + Room.RAMP - _n.position.z) / Room.RAMP, 0.0, 1.0)
		_n.position.y = Room.PLATFORM_HEIGHT * onto
	if moved.length() > 0.0001:
		_face_n(moved, clampf(6.0 * delta, 0.0, 1.0))
	if _n.has_method("report_velocity"):
		_n.call("report_velocity", moved / maxf(delta, 0.0001))
	if _n_route.is_empty():
		if _n.has_method("report_velocity"):
			_n.call("report_velocity", Vector3.ZERO)
		_n_standing = true
		_face_n(Vector3(0.3, 0.0, 1.0), 1.0)
		_say("N", "［占位］N 没有准备，说这节课自由活动。")


## N's model looks down -Z: turn it half a turn further than Q or the protagonist.
func _face_n(direction: Vector3, weight: float) -> void:
	var angle := atan2(direction.x, direction.z) + PI
	_n.rotation.y = lerp_angle(_n.rotation.y, angle, weight)


# --- Environment and HUD -------------------------------------------------------------------


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.11, 0.09, 0.15)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.44, 0.38, 0.52)
	environment.ambient_light_energy = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world_environment.environment = environment
	# The sun comes from the west, through the window wall, 42 degrees up: the wall's
	# shadow covers the window side of the room, and the front window lays its patch
	# across the lectern.
	var elevation := deg_to_rad(42.0)
	var direction := Vector3(cos(elevation) * 0.96, -sin(elevation), cos(elevation) * 0.28).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(direction, Vector3.UP), Vector3(0.0, 10.0, 0.0))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "HUD"
	_hud.layer = 10
	add_child(_hud)
	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.color = Color(0.06, 0.05, 0.08, 0.78)
	panel.position = Vector2(12, 12)
	panel.size = Vector2(560, 132)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	_hud_text = Label.new()
	_hud_text.name = "Text"
	_hud_text.position = Vector2(12, 8)
	_hud_text.size = Vector2(540, 120)
	_hud_text.add_theme_font_size_override("font_size", 14)
	_hud_text.add_theme_color_override("font_color", Color(0.94, 0.91, 0.82))
	panel.add_child(_hud_text)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_anchor_bottom_centre(_prompt, Vector2(520, 30), 206.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.add_theme_color_override("font_color", Color(0.98, 0.94, 0.84))
	_prompt.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.1))
	_prompt.add_theme_constant_override("outline_size", 6)
	_hud.add_child(_prompt)
	# The dialogue strip: torn paper pinned along the bottom. The impression of B is an ink
	# wedge (the set square's corner) that pushes in over its top-left corner.
	_dialogue = Control.new()
	_dialogue.name = "Dialogue"
	_anchor_bottom_centre(_dialogue, Vector2(640, 160), 172.0)
	_dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its own layer, above the paper and below the fade, and not hidden with the HUD: it is
	# part of what is being proposed, not a debugging aid.
	var stage := CanvasLayer.new()
	stage.name = "DialogueLayer"
	stage.layer = 9
	add_child(stage)
	stage.add_child(_dialogue)
	var strip := TextureRect.new()
	strip.name = "Paper"
	strip.texture = Art.dialogue_paper()
	strip.size = Vector2(640, 160)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue.add_child(strip)
	_speaker = Label.new()
	_speaker.name = "Speaker"
	_speaker.position = Vector2(80, 22)
	_speaker.size = Vector2(300, 26)
	_speaker.add_theme_font_size_override("font_size", 17)
	_speaker.add_theme_color_override("font_color", Color(0.3, 0.16, 0.2))
	_dialogue.add_child(_speaker)
	_line = Label.new()
	_line.name = "Line"
	_line.position = Vector2(80, 52)
	_line.size = Vector2(530, 80)
	_line.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_line.add_theme_font_size_override("font_size", 16)
	_line.add_theme_color_override("font_color", Color(0.16, 0.14, 0.2))
	_dialogue.add_child(_line)
	var note := Label.new()
	note.name = "Note"
	note.position = Vector2(400, 128)
	note.size = Vector2(220, 20)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.45, 0.42, 0.44))
	note.text = "对白框位置示意 · 不是正式台词"
	_dialogue.add_child(note)
	_intrusion = Polygon2D.new()
	_intrusion.name = "Intrusion"
	_intrusion.color = Color(0.12, 0.1, 0.22, 0.92)
	_intrusion.polygon = PackedVector2Array([Vector2(0, 0), Vector2(250, 0), Vector2(0, 120)])
	_intrusion.position = Vector2(-18, -10)
	_dialogue.add_child(_intrusion)
	# The set square's own hole, drawn as a pale line inside the wedge.
	var hole := Line2D.new()
	hole.name = "Hole"
	hole.width = 2.0
	hole.default_color = Color(0.88, 0.83, 0.7, 0.8)
	hole.points = PackedVector2Array([
		Vector2(26, 18), Vector2(140, 18), Vector2(26, 74), Vector2(26, 18)
	])
	_intrusion.add_child(hole)
	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.03, 0.02, 0.05, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var curtain_layer := CanvasLayer.new()
	curtain_layer.name = "FadeLayer"
	curtain_layer.layer = 12
	add_child(curtain_layer)
	curtain_layer.add_child(_fade)


func _anchor_bottom_centre(control: Control, size: Vector2, from_bottom: float) -> void:
	control.anchor_left = 0.5
	control.anchor_right = 0.5
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = -size.x * 0.5
	control.offset_right = size.x * 0.5
	control.offset_top = -from_bottom
	control.offset_bottom = -from_bottom + size.y


func _say(speaker: String, text: String) -> void:
	if _speaker == null:
		return
	_speaker.text = speaker
	_line.text = text
	_say_timer = 6.0 if not text.is_empty() else 0.0


func _update_hud(delta: float) -> void:
	if _hud_text == null:
		return
	if _say_timer > 0.0:
		_say_timer -= delta
	var talking := _say_timer > 0.0
	# The strip stays up while B presses on it, so the pressure can be seen, empty or not.
	_dialogue.visible = talking or b_weight > 0.35
	if not talking:
		_speaker.text = ""
		_line.text = ""
	var interaction := current_interaction()
	_prompt.text = "" if locked else String(interaction[1])
	var place := {
		&"yard": "操场", &"corridor": "走廊", &"lectern": "讲台旁", &"curtain": "窗帘旁",
		&"classroom": "教室",
	}
	var lines: Array[String] = [
		"生物课教室 · 重画实验      %s      位置：%s" % [
			String(BEAT_TITLES.get(beat, "")), String(place.get(current_zone(), "教室"))
		],
		"WASD 移动   Shift 快走   Q/E 转视角   滚轮 缩放   R 复位视角   F 自由镜头",
		"空格 互动   1–4 切换剧情段   0 重新开始   M 纸面开关   H 隐藏界面",
		"B 的印象 %.2f   褪色 %.2f   纸面 %s   Q：%s" % [
			b_weight, dull, "开" if bool(paper.call("is_on")) else "关", _q_state_text()
		],
	]
	_hud_text.text = "\n".join(lines)


func _q_state_text() -> String:
	var walking := bool(q.call("is_walking"))
	var names := {
		QPresence.Place.HOME: "在过道", QPresence.Place.WINDOW: "在窗边",
		QPresence.Place.THRESHOLD: "在门口（不出门）", QPresence.Place.SEAT: "在座位上",
	}
	var where: String = names.get(int(q.get("place")), "")
	return ("走向" if walking else "") + where
