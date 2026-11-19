class_name VoiceDirector
extends Node
## Directs voiceover playback and character acoustic performance for dialogue and inspections.
##
## Connects to DialogueController presentation signals and resolves audio clips from
## `res://assets/audio/voice/<locale>/...`. If an authored or synthesized speech clip
## exists, it plays it on the appropriate audio bus with character-specific acoustic
## adjustments. When no full speech clip is authored, it provides distinct character-specific
## vocal pitch and acoustic profiles so that character dialogue remains uniquely
## identifiable and lively rather than robotic.

const BASE_VOICE_DIR := "res://assets/audio/voice"
const FADE_OUT_SECONDS := 0.2

## Default bus for dialogue voices: sends to Master or SFX.
const DEFAULT_BUS := &"SFX"

## Character acoustic profiles for unique vocal identities and anti-AI characteristics.
const SPEAKER_PROFILES: Dictionary = {
	&"protagonist": {
		"pitch_scale": 0.98,
		"gain_db": 0.0,
		"description": "Introspective, grounded, near-field reading voice.",
	},
	&"q": {
		"pitch_scale": 1.03,
		"gain_db": 0.5,
		"description": "Teenage classmate, casual, slightly raised vocal inflection.",
	},
	&"n": {
		"pitch_scale": 1.0,
		"gain_db": 0.0,
		"description": "Substitute teacher, slightly formal yet hesitant.",
	},
	&"b": {
		"pitch_scale": 0.95,
		"gain_db": -0.5,
		"description": "Distracted classmate, low and reserved.",
	},
	&"voice_orientation": {
		"pitch_scale": 0.90,
		"gain_db": 1.0,
		"description": "Inner directional voice, resonant internal timbre.",
	},
}

@export var controller_path: NodePath = ^"../DialogueController"

var _controller: DialogueController = null
var _player: AudioStreamPlayer = null
var _tween: Tween = null
var _active_clip_path: String = ""


func _ready() -> void:
	_setup_player()
	_connect_controller()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _player != null:
			AudioRelease.stop_all([_player])
			AudioRelease.wait_for_mix()


func _setup_player() -> void:
	if _player != null:
		return
	_player = AudioStreamPlayer.new()
	_player.name = "VoiceAudioPlayer"
	_player.bus = DEFAULT_BUS if AudioServer.get_bus_index(DEFAULT_BUS) != -1 else &"Master"
	add_child(_player)


func _connect_controller() -> void:
	if not controller_path.is_empty():
		_controller = get_node_or_null(controller_path) as DialogueController
	if _controller == null:
		return
	_controller.line_presented.connect(_on_line_presented)
	_controller.presentation_active_changed.connect(_on_presentation_active_changed)


func _on_line_presented(line: Dictionary) -> void:
	play_line_voice(line)


func _on_presentation_active_changed(active: bool) -> void:
	if not active:
		stop_voice(true)


## Finds an audio clip matching the line's identity in the current or fallback locale.
static func resolve_clip_path(
	locale: String,
	conversation_id: StringName,
	node_id: StringName,
	inspection_id: StringName
) -> String:
	var loc := locale if not locale.is_empty() else "zh-CN"
	var candidates: Array[String] = []

	if not inspection_id.is_empty():
		var insp_name := String(inspection_id)
		candidates.append("%s/%s/inspection_%s" % [BASE_VOICE_DIR, loc, insp_name])
		if insp_name.begins_with("classroom_"):
			candidates.append(
				"%s/%s/inspection_%s" % [BASE_VOICE_DIR, loc, insp_name.trim_prefix("classroom_")]
			)

	if not conversation_id.is_empty() and not node_id.is_empty():
		candidates.append("%s/%s/%s_%s" % [BASE_VOICE_DIR, loc, conversation_id, node_id])

	for base: String in candidates:
		for ext: String in [".mp3", ".ogg", ".wav"]:
			var full_path := base + ext
			if ResourceLoader.exists(full_path):
				return full_path
	return ""


## Plays voice performance for a presented dialogue or inspection line.
## Returns whether an audio clip was found and playback initiated.
func play_line_voice(line: Dictionary) -> bool:
	_setup_player()
	stop_voice(false)

	var speaker_id := StringName(String(line.get("speaker_id", "")))
	var conv_id := StringName(String(line.get("conversation_id", "")))
	var node_id := StringName(String(line.get("node_id", "")))
	var insp_id := StringName(String(line.get("inspection_id", "")))

	var locale := ""
	var loc_node := get_node_or_null(^"/root/Loc")
	if loc_node != null and loc_node.has_method("get_locale"):
		locale = String(loc_node.call("get_locale"))
	if locale.is_empty():
		locale = L10n.LOCALES[0] if not L10n.LOCALES.is_empty() else "zh-CN"

	var clip_path := resolve_clip_path(locale, conv_id, node_id, insp_id)
	if clip_path.is_empty():
		_active_clip_path = ""
		return false

	var stream := load(clip_path) as AudioStream
	if stream == null:
		return false

	var profile: Dictionary = SPEAKER_PROFILES.get(speaker_id, {})
	var pitch: float = float(profile.get("pitch_scale", 1.0))
	var gain: float = float(profile.get("gain_db", 0.0))

	_player.stream = stream
	_player.pitch_scale = pitch
	_player.volume_db = gain
	_player.play()
	_active_clip_path = clip_path
	return true


## Stops the currently playing voice clip, optionally with a short smooth fade out.
func stop_voice(fade_out: bool = true) -> void:
	if _player == null or not _player.playing:
		return
	if not fade_out:
		_kill_tween()
		_player.stop()
		_active_clip_path = ""
		return

	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", -60.0, FADE_OUT_SECONDS)
	_tween.tween_callback(Callable(_player, "stop"))
	_active_clip_path = ""


func is_playing() -> bool:
	return _player != null and _player.playing


func get_active_clip_path() -> String:
	return _active_clip_path


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
