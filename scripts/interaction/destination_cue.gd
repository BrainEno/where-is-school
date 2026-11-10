class_name DestinationCue
extends Node3D
## The mark drawn where a click lands — the only thing the mouse writes into the world.
##
## It is one small mark, not a ring, not a pulse, not a breathing decal. Four short unequal
## strokes are laid on the floor where the click was accepted, they ink in over a seventh of
## a second, and then they are still until the walk ends. All the shape lives in
## `WorldCue.destination_mark_mesh()`; this file only decides the role, the surface and the
## two fades:
##
## * **destination** — a click on the floor. Bone-coloured, and the whole mark.
## * **target** — a click on an object. The same mark in amber, standing where the walk ends,
##   so the colour is the only difference between "go there" and "go there and use that".
## * **refused** — the click was heard and refused. Rose, the mark *contracts* instead of
##   expanding, and is gone in a third of a second: a refusal is not something to look at.
##
## Two decisions worth recording, because both were the opposite way round before:
##
## - **No motion after the reveal.** A rotating, breathing ring asks to be looked at for as
##   long as the character walks; this mark does not. The walk itself is the animation, and
##   the mark only has to say "there".
## - **Small does not mean faint.** The footprint shrank by about three quarters while the
##   pen got slightly wider (`WorldCue.MARK_STROKE`), because at four metres the old pen was
##   one pixel across. The mark is checked in the capture run against the pixels it actually
##   puts on screen, not against its size in metres.
##
## The mark lies on the surface it lands on: the caller passes the ground normal and the
## cue's basis puts +Y on it, so a ramp, a kerb or a tilted floor plate gets a mark that lies
## flat. Nothing here decides anything — `PointerNavigator` decides what a click meant.

## How long the mark takes to ink in. Short on purpose: a mark that fades in slowly reads as
## an effect that is happening, not as a place.
const REVEAL_SECONDS := 0.14
## How long it takes to leave. Shorter still.
const DISMISS_SECONDS := 0.12
## A refusal: in, then a contraction and out. One gesture, no flicker.
const REFUSAL_SECONDS := 0.32
## The mark starts a little small and settles, which is what makes the reveal read as being
## made rather than as being uncovered.
const SETTLE_SCALE_FROM := 0.86
## How far a refusal contracts before it disappears.
const REFUSAL_SCALE := 0.72
## Height above the surface, so the mark is not z-fighting with the floor it lies on.
const GROUND_OFFSET := 0.02

var _role: String = ""
var _shown: bool = false
var _opacity: float = 0.0
var _mark: MeshInstance3D = null
var _tween: Tween = null


func is_shown() -> bool:
	return _shown


## `"destination"`, `"target"`, `"refused"`, or `""` when nothing is drawn. The tests and
## the capture run read this instead of guessing from pixels.
func get_role() -> String:
	return _role


func get_opacity() -> float:
	return _opacity


func get_parts() -> Dictionary:
	return {"mark": _mark}


## Half-width of the mark's footprint in metres, read off the mesh it actually draws.
func get_footprint_radius() -> float:
	if _mark == null or _mark.mesh == null:
		return 0.0
	var box := _mark.mesh.get_aabb()
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
	_kill_tween()
	if _mark == null:
		visible = false
		return
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
	if _mark == null:
		return
	_kill_tween()
	_role = role
	_shown = true
	visible = true
	var up := normal.normalized() if normal.length_squared() > 0.0001 else Vector3.UP
	global_transform = Transform3D(WorldCue.ground_basis(up), point + up * GROUND_OFFSET)
	_mark.material_override = WorldCue.material_for(role)
	_mark.scale = Vector3.ONE * SETTLE_SCALE_FROM
	_set_opacity(0.0)
	if not is_inside_tree():
		# A cue asked to appear outside the tree still ends up in the right place with the
		# right colour; it just cannot animate. Drawing it fully beats drawing nothing.
		_mark.scale = Vector3.ONE
		_set_opacity(1.0)
		return
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_method(_set_opacity, 0.0, 1.0, REVEAL_SECONDS)
	_tween.tween_property(_mark, "scale", Vector3.ONE, REVEAL_SECONDS)
	if role == WorldCue.ROLE_REFUSED:
		# Inward is the whole meaning: an outward gesture promises a walk, and a walk is
		# exactly what is not going to happen. One contraction, no flicker.
		_tween.chain().set_parallel(true)
		_tween.tween_method(_set_opacity, 1.0, 0.0, REFUSAL_SECONDS)
		_tween.tween_property(_mark, "scale", Vector3.ONE * REFUSAL_SCALE, REFUSAL_SECONDS)
		_tween.chain().tween_callback(_finish)


func _build() -> void:
	if _mark != null:
		return
	_mark = MeshInstance3D.new()
	_mark.name = "Mark"
	_mark.mesh = WorldCue.destination_mark_mesh()
	_mark.material_override = WorldCue.material_for(WorldCue.ROLE_DESTINATION)
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark.transparency = 1.0
	add_child(_mark)
	visible = false


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	if _mark != null:
		_mark.transparency = 1.0 - _opacity


func _finish() -> void:
	_shown = false
	_role = ""
	_set_opacity(0.0)
	visible = false


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
