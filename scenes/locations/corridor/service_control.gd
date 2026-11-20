extends StagedInteractable
## The two mechanical controls belong to the teaching block. Their final pose is
## a fact in GameState; only the first successful interaction plays the movement.

const SCREEN_TRAVEL := 2.62
const PRESS_TRAVEL := 0.034
const BELL_DELAYS: Array[float] = [0.12, 0.42, 1.20]

enum Mechanism { STAIR_SCREEN, BELL_REGISTER }

@export var mechanism: Mechanism = Mechanism.STAIR_SCREEN
@export var effect_path: NodePath

@onready var _effect := get_node_or_null(effect_path) as Node3D
@onready var _plunger: Node3D = $Plunger
@onready var _state := get_node_or_null(^"/root/GameState")
var _flag: StringName
var _screen_home_y := 0.0
var _plunger_home_z := 0.0
var _plates: Array[Node3D] = []
var _bell: AudioStreamPlayer3D = null
var _bell_db := 0.0


func _ready() -> void:
	super._ready()
	if _effect == null or _state == null:
		push_error("Service control '%s' is missing its mechanism or GameState." % interact_id)
		interaction_enabled = false
		return
	_plunger_home_z = _plunger.position.z
	if mechanism == Mechanism.STAIR_SCREEN:
		_flag = StoryFlags.CORRIDOR_SCREEN_RAISED
		_screen_home_y = _effect.position.y
	else:
		_flag = StoryFlags.CORRIDOR_BELL_TESTED
		_bell = _effect.get_node("Bell") as AudioStreamPlayer3D
		_bell_db = _bell.volume_db
		for i in BELL_DELAYS.size():
			_plates.append(_effect.get_node("Plate%d" % i) as Node3D)
	_restore_mechanism()
	_state.story_state_replaced.connect(_restore_mechanism)
	stage_handler = _press


func get_prompt_override() -> String:
	if _completed():
		return "prompt.service_result"
	return super.get_prompt_override()


func _completed() -> bool:
	return _state != null and _state.get_flag(_flag, false) == true


func _restore_mechanism() -> void:
	var done := _completed()
	_plunger.position.z = _plunger_home_z - PRESS_TRAVEL if done else _plunger_home_z
	if mechanism == Mechanism.STAIR_SCREEN:
		_effect.position.y = _screen_home_y + (SCREEN_TRAVEL if done else 0.0)
	else:
		for plate in _plates:
			plate.rotation.y = PI if done else 0.0


func _press(director: OpeningSequence) -> Dictionary:
	if _completed():
		return {"inspection": inspection_id}
	# Hold the existing camera/interaction beat through the movement and its line.
	await director.wait_seconds(0.50)
	var press := create_tween()
	press.tween_property(_plunger, ^"position:z", _plunger_home_z - PRESS_TRAVEL, 0.14)
	await press.finished
	if mechanism == Mechanism.STAIR_SCREEN:
		var audio := get_node_or_null(^"/root/WorldAudio")
		if audio != null:
			audio.play_door()
		var lift := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lift.tween_property(_effect, ^"position:y", _screen_home_y + SCREEN_TRAVEL, 1.55)
		await lift.finished
	else:
		_bell.volume_db = _bell_db
		_bell.play()
		var roll := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC)
		# A truncated test ring, not the entire prologue bell. The third plate
		# visibly misses the sound; its reverse is blank.
		roll.tween_property(_bell, ^"volume_db", -55.0, 0.38).set_delay(0.58)
		roll.tween_callback(_bell.stop).set_delay(0.98)
		for i in BELL_DELAYS.size():
			roll.tween_property(_plates[i], ^"rotation:y", PI, 0.38).set_delay(BELL_DELAYS[i])
		await roll.finished
	_state.set_flag(_flag, true)
	await director.play_conversation(
		&"corridor_screen_reveal" if mechanism == Mechanism.STAIR_SCREEN else &"corridor_bell_reveal"
	)
	return {"checkpoint": String(interact_id)}
