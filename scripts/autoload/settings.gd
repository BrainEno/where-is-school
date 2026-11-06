extends Node
## Small, documented settings service.
## Owns accessibility text options only (typewriter speed and text scale).
## Persisted to user://settings.cfg. Story state lives in GameState, not here.

const TEXT_SPEEDS: Array[String] = ["slow", "normal", "fast"]
const TEXT_SCALES: Array[String] = ["small", "normal", "large"]
const SPEED_CPS: Dictionary = {
	"slow": 18.0,
	"normal": 45.0,
	"fast": 140.0,
}
const SCALE_FACTOR: Dictionary = {
	"small": 0.85,
	"normal": 1.0,
	"large": 1.25,
}

@export var save_path: String = "user://settings.cfg"

var text_speed: String = "normal"
var text_scale: String = "normal"


func _ready() -> void:
	load_settings()


func typewriter_cps() -> float:
	return float(SPEED_CPS.get(text_speed, SPEED_CPS["normal"]))


func font_scale() -> float:
	return float(SCALE_FACTOR.get(text_scale, SCALE_FACTOR["normal"]))


func set_text_speed(value: String) -> void:
	if not TEXT_SPEEDS.has(value):
		push_error("Settings.set_text_speed received unknown value: %s" % value)
		return
	text_speed = value
	save_settings()


func set_text_scale(value: String) -> void:
	if not TEXT_SCALES.has(value):
		push_error("Settings.set_text_scale received unknown value: %s" % value)
		return
	text_scale = value
	save_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(save_path)
	if err != OK:
		# Missing or unreadable settings are fine: keep defaults.
		return
	var speed: Variant = config.get_value("accessibility", "text_speed", "normal")
	var scale: Variant = config.get_value("accessibility", "text_scale", "normal")
	# Any missing or unknown value falls back to its default — corrupt
	# configs must never stick, no matter what the in-memory value was.
	text_speed = speed if (speed is String and TEXT_SPEEDS.has(speed)) else "normal"
	text_scale = scale if (scale is String and TEXT_SCALES.has(scale)) else "normal"


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("accessibility", "text_speed", text_speed)
	config.set_value("accessibility", "text_scale", text_scale)
	var err := config.save(save_path)
	if err != OK:
		push_error("Settings could not save %s (error %d)." % [save_path, err])
