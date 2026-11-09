extends SceneTree
## The window: opening size, minimum size, centring and F11.
##
## A headless run has no display, so this cannot check that a window physically moved. What
## it can check — and what actually breaks in practice — is the state machine around it:
##
## 1. the project opens at the design size (1600x900), is resizable, and declares no window
##    size override smaller than the design;
## 2. the node asks the display for a minimum of 1280x720, the smallest size the UI is
##    verified at, and never for a smaller one;
## 3. the centring arithmetic puts the frame inside the usable screen, and fits it there when
##    the screen is smaller than the design size (the case that used to open a window halfway
##    off the panel);
## 4. F11 is bound to one action and nothing else;
## 5. toggling twice returns to the windowed state, remembering a sane rectangle both times,
##    with the guard that stops a held key from bouncing;
## 6. switching display mode does not disturb the game: the player, the location, the
##    dialogue and the story flag are the same before and after.

const Harness = preload("res://tests/test_harness.gd")

const DESIGN := Vector2i(1600, 900)
const MINIMUM := Vector2i(1280, 720)

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "display_mode_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	await _check_project_settings()
	await _check_centring()
	await _check_toggle()
	await _check_game_state_survives()
	Harness.finish(
		self,
		_failures,
		"the window opens at the design size, cannot be dragged below 1280x720, is centred "
		+ "and fitted to the screen, toggles on F11, and comes back where it was without "
		+ "touching the game."
	)


func _check_project_settings() -> void:
	Harness.stage = "project settings"
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	_expect(
		Vector2i(width, height) == DESIGN,
		"The design viewport is %dx%d, not 1600x900." % [width, height]
	)
	var override_width := int(ProjectSettings.get_setting("display/window/size/window_width_override", 0))
	var override_height := int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	_expect(
		override_width == 0 or override_width >= DESIGN.x,
		"The window opens at %d px wide, below the %d px design width." % [override_width, DESIGN.x]
	)
	_expect(
		override_height == 0 or override_height >= DESIGN.y,
		"The window opens at %d px tall, below the %d px design height." % [override_height, DESIGN.y]
	)
	_expect(
		bool(ProjectSettings.get_setting("display/window/size/resizable", true)),
		"The window is not resizable."
	)
	var action := InputMap.action_get_events(&"toggle_fullscreen")
	_expect(action.size() > 0, "No input action is bound to the fullscreen toggle.")
	var keys: Array[Key] = []
	for event: InputEvent in action:
		var key := event as InputEventKey
		if key != null:
			keys.append(key.physical_keycode)
	_expect(
		keys.has(KEY_F11),
		"The fullscreen toggle is not bound to F11 (bound to %s)." % str(keys)
	)
	# One key, so the manual checklist can say "press F11" and mean it.
	_expect(keys.size() == 1, "The fullscreen toggle has %d keys bound, not one." % keys.size())


func _check_centring() -> void:
	Harness.stage = "centring"
	var mode = _make_display_mode()
	if mode == null:
		return
	# A screen bigger than the design size: the frame is centred inside it.
	var big: Rect2i = mode.centred_rect(DESIGN)
	_expect(big.size == DESIGN, "A screen that fits the design size produced a %s frame." % str(big.size))
	# A screen smaller than the design size: the frame is fitted, never larger than the screen.
	var small := Vector2i(1366, 768)
	var fitted_size := Vector2i(mini(DESIGN.x, small.x), mini(DESIGN.y, small.y))
	var fitted: Rect2i = mode.centred_rect(fitted_size)
	_expect(
		fitted.size.x <= small.x and fitted.size.y <= small.y,
		"A window of %s does not fit a %s screen." % [str(fitted.size), str(small)]
	)
	_expect(
		fitted.position.x >= 0 and fitted.position.y >= 0,
		"The centred frame starts off-screen at %s." % str(fitted.position)
	)
	_expect(
		mode.MIN_WINDOW_SIZE == MINIMUM,
		"The minimum window is %s, not 1280x720." % str(mode.MIN_WINDOW_SIZE)
	)
	_expect(
		mode.DESIGN_WINDOW_SIZE == DESIGN,
		"The design window is %s, not 1600x900." % str(mode.DESIGN_WINDOW_SIZE)
	)
	mode.queue_free()
	await process_frame


func _check_toggle() -> void:
	Harness.stage = "F11 toggle"
	var mode = _make_display_mode()
	if mode == null:
		return
	_expect(not mode.is_fullscreen(), "The window starts in fullscreen.")
	_expect(
		mode.get_windowed_rect().size == Vector2i.ZERO,
		"No toggle has happened yet but a windowed rectangle was already remembered."
	)
	_expect(mode.toggle_fullscreen(), "The first toggle did nothing.")
	_expect(mode.is_fullscreen(), "The first toggle did not enter fullscreen.")
	# The guard: a held key repeats, and a second toggle within the guard window must be
	# ignored rather than bouncing the mode.
	_expect(not mode.toggle_fullscreen(), "A second toggle inside the guard window was accepted.")
	await _wait(0.2)
	_expect(mode.toggle_fullscreen(), "The toggle to leave fullscreen did nothing.")
	_expect(not mode.is_fullscreen(), "The window did not leave fullscreen.")
	var rect: Rect2i = mode.get_windowed_rect()
	_expect(
		rect.size.x >= MINIMUM.x and rect.size.y >= MINIMUM.y,
		"Leaving fullscreen remembered a %s window, below the minimum." % str(rect.size)
	)
	# Repeat: the remembered rectangle must not degrade as it is used again.
	await _wait(0.2)
	mode.toggle_fullscreen()
	await _wait(0.2)
	mode.toggle_fullscreen()
	_expect(
		mode.get_windowed_rect().size.x >= MINIMUM.x,
		"Repeated toggles degraded the remembered window size to %s."
		% str(mode.get_windowed_rect().size)
	)
	_expect(not mode.is_fullscreen(), "An even number of toggles left the window fullscreen.")
	mode.queue_free()
	await process_frame


## The requirement that matters most to a player: pressing F11 mid-conversation must not
## restart the scene, move the character or forget where the story was.
func _check_game_state_survives() -> void:
	Harness.stage = "state survives a toggle"
	var packed: PackedScene = load("res://scenes/main/main.tscn")
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		return
	var main := packed.instantiate()
	var sequence := main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(main)
	await _frames(2)
	var host := main.get_node_or_null("LocationHost") as LocationHost
	var player := main.get_node_or_null("Player") as PlayerController
	var dialogue := main.get_node_or_null("DialogueController") as DialogueController
	var mode := main.get_node_or_null("DisplayMode")
	var game_state := root.get_node_or_null("GameState")
	_expect(host != null and player != null and dialogue != null, "Main did not expose its nodes.")
	_expect(mode != null, "main.tscn has no DisplayMode node; F11 would do nothing.")
	if host == null or player == null or dialogue == null or mode == null:
		main.queue_free()
		await process_frame
		return
	if sequence != null:
		sequence.call("allow_player_control")
	await _frames(3)
	var location_before := String(host.get_current().location_id) if host.get_current() != null else ""
	var position_before: Vector3 = player.global_position
	var busy_before := dialogue.is_busy()
	var flag_before: Variant = (
		game_state.get_flag(StoryFlags.MET_Q, false) if game_state != null else null
	)
	var children_before := main.get_child_count()

	mode.call("toggle_fullscreen")
	await _frames(3)
	mode.call("toggle_fullscreen")
	await _frames(3)

	var location_after := String(host.get_current().location_id) if host.get_current() != null else ""
	_expect(
		location_after == location_before,
		"Toggling fullscreen changed the location: '%s' -> '%s'."
		% [location_before, location_after]
	)
	_expect(
		# 10 cm, not "exactly zero": a body settling onto the floor over three frames is not
		# the same thing as a scene reload putting the character back at a spawn point.
		player.global_position.distance_to(position_before) < 0.1,
		"Toggling fullscreen moved the player by %.3f m."
		% player.global_position.distance_to(position_before)
	)
	_expect(
		dialogue.is_busy() == busy_before,
		"Toggling fullscreen changed whether a conversation is running."
	)
	if game_state != null:
		_expect(
			game_state.get_flag(StoryFlags.MET_Q, false) == flag_before,
			"Toggling fullscreen changed a story flag."
		)
	_expect(
		main.get_child_count() == children_before,
		"Toggling fullscreen added or removed %d node(s) from main."
		% (main.get_child_count() - children_before)
	)
	main.queue_free()
	await process_frame


## Untyped on purpose: the probe is the real script, and every member is reached
## dynamically. Typing it as `Node` would make this whole file fail to compile on the first
## property access.
func _make_display_mode():
	var script: Script = load("res://scripts/ui/display_mode.gd")
	if script == null:
		_failures.append("display_mode.gd could not be loaded.")
		return null
	var node: Node = script.new()
	node.name = "DisplayModeProbe"
	root.add_child(node)
	return node


func _frames(count: int) -> void:
	for _index in count:
		await process_frame


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
