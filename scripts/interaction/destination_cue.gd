class_name DestinationCue
extends Node3D
## The mark drawn where a click lands - the only thing the mouse writes into the world.
##
## A thin ring with a dot in the middle, in the language of Disco Elysium's walk marker. The
## shape lives in `WorldCue` (`destination_ring_mesh`, `destination_dot_mesh`,
## `destination_echo_mesh`); this file decides the role, the surface, and one short gesture:
##
## * the **ring** lands: it starts wide and contracts onto its radius in a fifth of a second,
##   which is what makes it read as "put down here" rather than "uncovered here";
## * the **dot** pops in at the centre a moment later, so the point stays legible when the
##   ring is foreshortened by a low camera;
## * the **echo**, a thinner copy of the ring, goes outwards once and fades. It is the half of
##   the gesture that says the floor heard the click.
##
## After that the mark is still until the walk ends: the walk itself is the animation.
##
## The roles:
##
## * **destination** - a click on the floor. Bone-coloured.
## * **target** - a click on an object. The same mark in amber, where the walk ends; the
##   object itself keeps its outline (`HoverCue`), so the colour is the only difference
##   between "go there" and "go there and use that".
## * **refused** - the click was heard and refused. Rose, no dot and no echo, and the ring
##   *contracts* past its radius and is gone in a third of a second: an outward gesture
##   promises a walk, and here there is none.
##
## The mark lies on the surface it lands on: the caller passes the ground normal and the
## cue's basis puts +Y on it, so a ramp, a kerb or a tilted floor plate gets a mark that lies
## flat. Nothing here decides anything - `PointerNavigator` decides what a click meant.

## How long the ring takes to land.
const LAND_SECONDS := 0.2
## How wide the ring starts, as a multiple of its resting radius.
const LAND_SCALE_FROM := 1.9
## The dot follows the ring by this much, and takes this long to appear.
const DOT_DELAY := 0.06
const DOT_SECONDS := 0.12
## The echo: how far it travels and how long it takes.
const ECHO_SCALE_TO := 2.6
const ECHO_SECONDS := 0.5
const ECHO_ALPHA := 0.7
## How long the mark takes to leave when the walk ends.
const DISMISS_SECONDS := 0.14
## A refusal: in, then a contraction and out. One gesture, no flicker.
const REFUSAL_SECONDS := 0.32
## How far a refusal contracts before it disappears.
const REFUSAL_SCALE := 0.4
## Height above the surface, so the mark is not z-fighting with the floor it lies on.
const GROUND_OFFSET := 0.02

var _role: String = ""
var _shown: bool = false
var _opacity: float = 0.0
var _ring: MeshInstance3D = null
var _dot: MeshInstance3D = null
var _echo: MeshInstance3D = null
var _tween: Tween = null
var _echo_tween: Tween = null


func is_shown() -> bool:
	return _shown


## `"destination"`, `"target"`, `"refused"`, or `""` when nothing is drawn. The tests and
## the capture run read this instead of guessing from pixels.
func get_role() -> String:
	return _role


## The opacity of the mark itself (ring and dot). The echo fades on its own schedule.
func get_opacity() -> float:
	return _opacity


func get_parts() -> Dictionary:
	return {"ring": _ring, "dot": _dot, "echo": _echo}


## Half-width of the mark's resting footprint in metres, read off the ring it draws.
func get_footprint_radius() -> float:
	if _ring == null or _ring.mesh == null:
		return 0.0
	var box := _ring.mesh.get_aabb()
	return maxf(maxf(absf(box.position.x), absf(box.position.z)), maxf(box.end.x, box.end.z))


## A click on the floor was accepted.
func show_destination(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_show(WorldCue.ROLE_DESTINATION, point, normal)


## A click on an object was accepted: the mark stands where the walk ends.
func show_target(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_show(WorldCue.ROLE_TARGET, point, normal)


## A click was refused: contract, fade, and get out of the way.
func show_refused(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_show(WorldCue.ROLE_REFUSED, point, normal)


## Ends the cue. The walk ended, so the mark has nothing left to say; it fades rather than
## blinking out. `immediate` is for a location swap, where the mark is going away with the
## room it was drawn in.
func dismiss(immediate: bool = false) -> void:
	_shown = false
	_role = ""
	_kill_tweens()
	if _ring == null:
		visible = false
		return
	_set_echo(0.0)
	if immediate or not is_inside_tree() or _opacity <= 0.0:
		_set_opacity(0.0)
		visible = false
		return
	_tween = create_tween()
	_tween.tween_method(_set_opacity, _opacity, 0.0, DISMISS_SECONDS)
	_tween.tween_callback(_finish)


func _show(role: String, point: Vector3, normal: Vector3) -> void:
	if not WorldCue.is_known_role(role):
		push_error("DestinationCue: unknown role '%s'." % role)
		return
	_build()
	_kill_tweens()
	_role = role
	_shown = true
	visible = true
	var up := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	global_transform = Transform3D(WorldCue.ground_basis(up), point + up * GROUND_OFFSET)
	var material := WorldCue.material_for(role)
	_ring.material_override = material
	_dot.material_override = material
	_echo.material_override = material
	var refused := role == WorldCue.ROLE_REFUSED
	_dot.visible = not refused
	_echo.visible = not refused
	_set_opacity(0.0)
	_set_echo(0.0)
	if not is_inside_tree():
		# A cue asked to appear outside the tree still ends up in the right place with the
		# right colour; it just cannot animate. Drawing it fully beats drawing nothing.
		_ring.scale = Vector3.ONE
		_dot.scale = Vector3.ONE
		_set_opacity(1.0)
		return
	_ring.scale = Vector3.ONE * (1.0 if refused else LAND_SCALE_FROM)
	_dot.scale = Vector3.ONE * 0.01
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_opacity, 0.0, 1.0, LAND_SECONDS * 0.6)
	if refused:
		# Inward is the whole meaning: one contraction while it fades, no flicker.
		_tween.tween_method(_set_opacity, 1.0, 0.0, REFUSAL_SECONDS).set_delay(LAND_SECONDS * 0.6)
		_tween.tween_property(_ring, "scale", Vector3.ONE * REFUSAL_SCALE, REFUSAL_SECONDS + LAND_SECONDS * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.chain().tween_callback(_finish)
		return
	_tween.tween_property(_ring, "scale", Vector3.ONE, LAND_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_dot, "scale", Vector3.ONE, DOT_SECONDS) \
		.set_delay(DOT_DELAY).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# The echo leaves from where the ring lands, after it has landed.
	_echo.scale = Vector3.ONE
	_echo_tween = create_tween()
	_echo_tween.tween_interval(LAND_SECONDS * 0.8)
	_echo_tween.tween_callback(_set_echo.bind(ECHO_ALPHA))
	_echo_tween.set_parallel(true)
	_echo_tween.tween_property(_echo, "scale", Vector3.ONE * ECHO_SCALE_TO, ECHO_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_echo_tween.tween_method(_set_echo, ECHO_ALPHA, 0.0, ECHO_SECONDS) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _build() -> void:
	if _ring != null:
		return
	_ring = _part("Ring", WorldCue.destination_ring_mesh())
	_dot = _part("Dot", WorldCue.destination_dot_mesh())
	_echo = _part("Echo", WorldCue.destination_echo_mesh())
	visible = false


func _part(part_name: String, mesh: Mesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = WorldCue.material_for(WorldCue.ROLE_DESTINATION)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.transparency = 1.0
	add_child(part)
	return part


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	if _ring != null:
		_ring.transparency = 1.0 - _opacity
	if _dot != null:
		_dot.transparency = 1.0 - _opacity


func _set_echo(value: float) -> void:
	if _echo != null:
		_echo.transparency = 1.0 - clampf(value, 0.0, 1.0)


## The echo's current opacity: 0 before the mark lands and after the echo has gone.
func get_echo_opacity() -> float:
	if _echo == null:
		return 0.0
	return 1.0 - _echo.transparency


func _finish() -> void:
	_shown = false
	_role = ""
	_set_opacity(0.0)
	_set_echo(0.0)
	visible = false


func _kill_tweens() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _echo_tween != null and _echo_tween.is_valid():
		_echo_tween.kill()
	_echo_tween = null
