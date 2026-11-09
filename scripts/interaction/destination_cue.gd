class_name DestinationCue
extends Node3D
## The cue drawn where a click lands — the only thing the mouse writes into the world.
##
## Three roles, one shape, because the player has to be able to tell three answers apart
## at a glance:
##
## * **destination** — a click on the floor. Bone-coloured: a ripple expands once where
##   the click landed and fades, and a quiet dashed core stays while the character walks,
##   breathing so it cannot be mistaken for something the level baked into the floor.
## * **target** — a click on an object. The same shape in amber, standing on the spot the
##   character has to reach before touching it. The colour is the whole difference between
##   "go there" and "go there and use that", and it is the only place the cue raises its
##   voice.
## * **refused** — the click was heard and refused. Rose, and the ring *collapses inward*
##   instead of expanding: an expanding ring promises a walk, and a walk is what is not
##   going to happen. It flicks twice while it collapses so a refusal at the edge of the
##   screen is still legible.
##
## The cue is laid on the surface it lands on: the caller passes the ground normal, and a
## ramp, a kerb or a tilted floor plate gets a ring that lies flat on it. A flat ring on a
## slope floats on one side and sinks on the other, which reads as a rendering fault.
##
## Nothing here decides anything. `PointerNavigator` decides what a click meant and tells
## the cue; the cue has no notion of a target, a route or a walk.

## The ripple: one expanding ring, over once it has said what it had to say.
const RIPPLE_SECONDS := 0.55
const RIPPLE_RADIUS := 0.34
const RIPPLE_SCALE_FROM := 0.45
const RIPPLE_SCALE_TO := 1.85
## The core: the ring that stays while the character walks.
const CORE_RADIUS := 0.26
const CORE_SPIN_DEGREES_PER_SECOND := -7.0
const CORE_BREATH_SECONDS := 2.2
const CORE_ALPHA_LOW := 0.5
const CORE_ALPHA_HIGH := 0.92
## The refused ring: inward, quick, and gone.
const REFUSAL_SECONDS := 0.55
const REFUSAL_RADIUS := 0.3
const REFUSAL_SCALE_FROM := 1.25
const REFUSAL_SCALE_TO := 0.42
const DISMISS_SECONDS := 0.16
## Height above the surface, so the ring is not z-fighting with the floor it lies on.
const GROUND_OFFSET := 0.02

var _role: String = ""
var _shown: bool = false
var _dismissing: bool = false
var _age: float = 0.0
## 0 hidden, 1 fully drawn. Written by the dismiss tween and by `_finish()`.
var _opacity: float = 1.0
var _ripple: MeshInstance3D = null
var _dot: MeshInstance3D = null
var _core: MeshInstance3D = null
var _refusal: MeshInstance3D = null
var _fade: Tween = null


func is_shown() -> bool:
	return _shown


## `"destination"`, `"target"`, `"refused"`, or `""` when nothing is drawn. The tests and
## the capture run read this instead of guessing from pixels.
func get_role() -> String:
	return _role


func get_opacity() -> float:
	return _opacity


func get_parts() -> Dictionary:
	return {"ripple": _ripple, "dot": _dot, "core": _core, "refusal": _refusal}


## A click on the floor was accepted: ripple, then a quiet ring while the character walks.
func show_destination(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_show(WorldCue.ROLE_DESTINATION, point, normal)


## A click on an object was accepted: the ring stands on the spot the walk ends at, in
## amber, so the walk visibly has a purpose beyond arriving.
func show_target(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_show(WorldCue.ROLE_TARGET, point, normal)


## A click was refused: collapse inward and get out of the way.
func show_refused(point: Vector3, normal: Vector3 = Vector3.UP) -> void:
	_show(WorldCue.ROLE_REFUSED, point, normal)


## Ends the cue. The walk ended, so the ring has nothing left to say; it collapses and
## fades rather than blinking out. `immediate` is for a location swap, where the cue is
## going away with the room it was drawn in.
func dismiss(immediate: bool = false) -> void:
	_shown = false
	_role = ""
	set_process(false)
	_kill_fade()
	if _ripple == null:
		visible = false
		return
	if immediate or not is_inside_tree():
		_opacity = 0.0
		visible = false
		_dismissing = false
		return
	_dismissing = true
	set_process(true)
	_fade = create_tween()
	_fade.tween_method(_set_opacity, _opacity, 0.0, DISMISS_SECONDS)
	_fade.tween_callback(_finish_dismiss)


func _show(role: String, point: Vector3, normal: Vector3) -> void:
	if not WorldCue.is_known_role(role):
		push_error("DestinationCue: unknown role '%s'." % role)
		return
	_build()
	if _core == null:
		return
	_kill_fade()
	_dismissing = false
	_role = role
	_shown = true
	_age = 0.0
	_opacity = 1.0
	visible = true
	set_process(true)
	global_transform = Transform3D(WorldCue.ground_basis(normal), point + normal.normalized() * GROUND_OFFSET)
	_apply_role()
	# The ripple and the refusal ring are alternatives, never both: an expanding ring and
	# a collapsing one in the same place would say "walk" and "no" at the same time.
	var expanding := role != WorldCue.ROLE_REFUSED
	_ripple.visible = expanding
	_dot.visible = expanding
	_refusal.visible = not expanding
	_core.visible = expanding
	_ripple.scale = Vector3.ONE * RIPPLE_SCALE_FROM
	_refusal.scale = Vector3.ONE * REFUSAL_SCALE_FROM
	_core.rotation.y = 0.0
	_core.scale = Vector3.ONE
	# The parts were possibly faded out by a dismissal a moment ago; a cue that is shown
	# again has to be fully drawn on its first frame, not one frame later.
	_set_opacity(1.0)


func _build() -> void:
	if _core != null:
		return
	_ripple = _make_part("Ripple", WorldCue.dashed_ring_mesh(RIPPLE_RADIUS, 10, 0.5))
	_dot = _make_part("Dot", WorldCue.disc_mesh(0.045))
	_dot.position = Vector3(0.0, 0.001, 0.0)
	_core = _make_part("Core", WorldCue.dashed_ring_mesh(CORE_RADIUS))
	_refusal = _make_part("Refusal", WorldCue.dashed_ring_mesh(REFUSAL_RADIUS, 6, 0.36))
	_ripple.visible = false
	_dot.visible = false
	_core.visible = false
	_refusal.visible = false
	visible = false
	set_process(false)


func _make_part(part_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = WorldCue.material_for(WorldCue.ROLE_DESTINATION)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


func _apply_role() -> void:
	var material := WorldCue.material_for(_role)
	for part: MeshInstance3D in [_ripple, _dot, _core, _refusal]:
		if part != null:
			part.material_override = material


func _process(delta: float) -> void:
	if _dismissing or not _shown:
		return
	_age += delta
	if _role == WorldCue.ROLE_REFUSED:
		_animate_refusal()
		return
	_animate_destination()


func _animate_destination() -> void:
	var progress := clampf(_age / RIPPLE_SECONDS, 0.0, 1.0)
	if _ripple != null:
		if progress >= 1.0:
			if _ripple.visible:
				_ripple.visible = false
				_dot.visible = false
		else:
			# Fast out, slow in: the ripple is a gesture, not a pulse.
			var eased := 1.0 - pow(1.0 - progress, 2.2)
			var scale := lerpf(RIPPLE_SCALE_FROM, RIPPLE_SCALE_TO, eased)
			_ripple.scale = Vector3.ONE * scale
			_ripple.transparency = 1.0 - _opacity * (1.0 - progress) * 0.95
			_dot.scale = Vector3.ONE * lerpf(1.0, 0.55, progress)
			_dot.transparency = 1.0 - _opacity * (1.0 - progress)
	if _core == null:
		return
	var breath := 0.5 + 0.5 * sin(_age * TAU / CORE_BREATH_SECONDS)
	_core.rotation.y = fmod(_age * deg_to_rad(CORE_SPIN_DEGREES_PER_SECOND), TAU)
	_core.scale = Vector3.ONE * lerpf(0.97, 1.04, breath)
	_core.transparency = 1.0 - _opacity * lerpf(CORE_ALPHA_LOW, CORE_ALPHA_HIGH, breath)


func _animate_refusal() -> void:
	var progress := clampf(_age / REFUSAL_SECONDS, 0.0, 1.0)
	if _refusal != null:
		_refusal.scale = Vector3.ONE * lerpf(REFUSAL_SCALE_FROM, REFUSAL_SCALE_TO, sqrt(progress))
		# Two flicks, so the refusal is legible even at the edge of the eye.
		var flicker := 0.5 + 0.5 * sin(_age * TAU * 3.2)
		_refusal.transparency = 1.0 - _opacity * (1.0 - progress) * (0.55 + 0.45 * flicker)
	if progress >= 1.0:
		_shown = false
		_role = ""
		_opacity = 0.0
		visible = false
		set_process(false)


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	if _core == null:
		return
	# The dismiss tween owns every part's transparency while it runs; the per-role
	# animation is not running at the same time (`_dismissing` gates it).
	var base := 1.0 - _opacity
	_ripple.transparency = base if _ripple.visible else 1.0
	_dot.transparency = base if _dot.visible else 1.0
	_core.transparency = base
	_refusal.transparency = base if _refusal.visible else 1.0


func _finish_dismiss() -> void:
	if not _dismissing:
		return
	_dismissing = false
	visible = false
	set_process(false)


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
