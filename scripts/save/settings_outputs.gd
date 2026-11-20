class_name SettingsOutputs
extends RefCounted
## Where the player's settings reach the engine: the audio bus levels the volume dials
## produce, and the factor the 2D layer is drawn at.
##
## Split out of the `Settings` autoload (`settings_manager.gd`, issue #223). `Settings`
## keeps the choices, stores them and decides *when* they apply; this static script holds
## the arithmetic and the engine calls, so both can be read - and tested - without a
## settings file. `Settings` re-exports the constants and `effective_ui_scale` under their
## old names.

const MobileLayout := preload("res://scripts/ui/mobile_layout.gd")

const VOLUME_KEYS: Array[StringName] = [&"master", &"music", &"sfx"]
const VOLUME_BUS: Dictionary = {&"master": &"Master", &"music": &"Music", &"sfx": &"SFX"}
## The level a muted dial sends a bus to, in dB.
const SILENT_DB := -80.0

const UI_SCALES: Array[StringName] = [&"auto", &"100", &"125", &"150", &"200"]
## The window size the interface is designed and checked at (CI measures 1280x720 to
## 1920x1080). "Auto" starts enlarging the 2D layer only beyond the largest of those.
const UI_REFERENCE_SIZE := Vector2(1920.0, 1080.0)
## The smallest logical size the layout is verified at. A manual scale is capped so the
## interface never gets less room than this.
const UI_MINIMUM_LOGICAL := Vector2(1280.0, 720.0)


# --- Sound -----------------------------------------------------------------------


## The trim of every dial's bus: the level `default_bus_layout.tres` gives it, read from
## the file rather than from the live bus, which may already carry a dial's setting.
## `{volume_key: dB}`.
static func capture_bus_trim() -> Dictionary:
	var trim: Dictionary = {}
	var authored := authored_bus_levels()
	for key: StringName in VOLUME_KEYS:
		var bus_name := String(VOLUME_BUS[key])
		if authored.has(bus_name):
			trim[key] = float(authored[bus_name])
			continue
		var index := AudioServer.get_bus_index(VOLUME_BUS[key])
		trim[key] = AudioServer.get_bus_volume_db(index) if index != -1 else 0.0
	return trim


## `{bus_name: dB}` as the project's bus layout file authors it; empty without one.
static func authored_bus_levels() -> Dictionary:
	var levels: Dictionary = {}
	var path := String(
		ProjectSettings.get_setting("audio/buses/default_bus_layout", "res://default_bus_layout.tres")
	)
	if not ResourceLoader.exists(path):
		return levels
	var layout := load(path) as AudioBusLayout
	if layout == null:
		return levels
	for index in 16:
		var bus_name: Variant = layout.get("bus/%d/name" % index)
		if bus_name == null:
			break
		var level: Variant = layout.get("bus/%d/volume_db" % index)
		levels[String(bus_name)] = float(level) if level != null else 0.0
	return levels


## The level a bus is actually at for a percentage: the layout's own trim plus the dial.
static func bus_db(trim_db: float, percent: int) -> float:
	if percent <= 0:
		return SILENT_DB
	return trim_db + linear_to_db(float(percent) / 100.0)


## Sets the bus of `key` to `percent` (muted at 0). The SFX dial also reaches the
## interaction cues, which own no bus by design (`cue_audio.gd`), through `cues`' own gain.
static func apply_volume(key: StringName, percent: int, trim_db: float, cues: Node) -> void:
	var index := AudioServer.get_bus_index(VOLUME_BUS[key])
	if index != -1:
		AudioServer.set_bus_mute(index, percent <= 0)
		AudioServer.set_bus_volume_db(index, bus_db(trim_db, percent))
	if key == &"sfx" and cues != null and cues.has_method("set_gain_db"):
		var gain := SILENT_DB if percent <= 0 else linear_to_db(float(percent) / 100.0)
		cues.call("set_gain_db", gain)


## Room tones (`AmbiencePlayer`) are authored in location scenes on the default bus. They
## are sound effects as far as the player is concerned, so they are moved onto `SFX` as
## they enter the tree - the location scenes themselves stay as they are.
static func route_ambience(node: Node) -> void:
	var player := node as AudioStreamPlayer
	if player == null:
		return
	if player is AmbiencePlayer and player.bus == &"Master":
		player.bus = &"SFX"


# --- Display -------------------------------------------------------------------------


## The factor the 2D layer is drawn at for a window size and a choice.
##
## The layouts are measured at 1280x720, 1600x900 and 1920x1080, in real pixels. On a
## bigger window ("auto") the whole interface layer is enlarged in quarter steps so a 4K
## screen draws it like 1080p at twice the density, instead of as a postage stamp. A
## manual choice is capped so the logical size never drops below 1280x720, the smallest
## size the layout is checked at; at the three verified sizes "auto" is exactly 1.
static func effective_ui_scale(window_size: Vector2, choice: StringName) -> float:
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return 1.0
	var room := minf(
		window_size.x / UI_MINIMUM_LOGICAL.x, window_size.y / UI_MINIMUM_LOGICAL.y
	)
	var wanted := 1.0
	if choice == &"auto" or not UI_SCALES.has(choice):
		var ratio := minf(
			window_size.x / UI_REFERENCE_SIZE.x, window_size.y / UI_REFERENCE_SIZE.y
		)
		wanted = floorf(ratio * 4.0) / 4.0
	else:
		wanted = float(String(choice).to_int()) / 100.0
	return maxf(1.0, minf(wanted, floorf(room * 4.0) / 4.0))


## Applies `choice` to the root window and returns the factor it is now drawn at.
##
## On mobile the layout is always the design size, stretched to the screen, and the
## choice does not apply. Elsewhere the window keeps real pixels at 1x and draws the
## canvas at a smaller logical size above that. Properties are only written when they
## change: writing `content_scale_size` resizes the root, which calls this again.
static func apply_ui_scale(root: Window, choice: StringName) -> float:
	if MobileLayout.enabled:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_size = MobileLayout.DESIGN_SIZE
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		return root.get_final_transform().get_scale().y
	var window_size := Vector2(root.size)
	var factor := effective_ui_scale(window_size, choice)
	if is_equal_approx(factor, 1.0):
		if root.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
			root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	else:
		var logical := Vector2i(
			roundi(window_size.x / factor), roundi(window_size.y / factor)
		)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		if root.content_scale_size != logical:
			root.content_scale_size = logical
	return factor
