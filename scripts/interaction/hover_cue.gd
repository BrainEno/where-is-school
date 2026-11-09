class_name HoverCue
extends Node3D
## The cue on the object the player can use right now — the thing E would act on.
##
## Three parts, and each one answers a different question:
##
## * **GroundRing** — a dashed ring on the floor under the object, slowly turning and
##   breathing. It answers "where do I stand", which is the question a click on a prop
##   actually asks, and its size is the interaction radius, so it also shows how close the
##   player has to be. The floor is passed in by `Interactable`, which finds it with one
##   downward ray: interactables are authored at the middle of the prop, so their own
##   height is not the ground.
## * **Halo** — a wider, fainter ring breathing out of step with the first one. Two rings
##   at different rhythms read as a deliberate mark; a single ring reads as interface.
## * **Shard** — a small tumbling diamond floating above the object. It answers "which
##   thing", and it keeps answering it when the object stands on a shelf, in a doorway or
##   behind a desk, where a ground ring would be hidden or ambiguous.
##
## Motion is the point. A static ring drawn on the floor looks like something the level
## baked in; something that moves looks like something the interface is pointing at. The
## motion is slow (a full turn in about forty seconds) so the cue never competes with the
## character, the dialogue band or the scene itself.
##
## The cue is built the first time it is needed and then reused. Its parts are
## `MeshInstance3D`s with the shared materials from `WorldCue`, and it fades through
## `GeometryInstance3D.transparency`, so revealing and concealing it costs a tween and no
## allocation.

## Ring radius is derived from the object's interaction radius, because a ring that
## ignores the object's size points at the wrong place: the interaction radius is where
## the player has to stand, which is exactly what the ring is for.
const RING_RADIUS_FACTOR := 0.62
const RING_RADIUS_MIN := 0.24
const RING_RADIUS_MAX := 0.92
const HALO_RADIUS_FACTOR := 1.55
const SHARD_SIZE := 0.045
## Where the shard floats: above the object's own origin, which is authored at the middle
## of the prop, so the shard always sits clear of it.
const SHARD_HEIGHT := 0.35
const SPIN_DEGREES_PER_SECOND := 9.0
const SHARD_TUMBLE_DEGREES_PER_SECOND := 26.0
const BOB_HEIGHT := 0.05
const BOB_SECONDS := 2.6
const BREATH_SECONDS := 3.4
const REVEAL_SECONDS := 0.14
const CONCEAL_SECONDS := 0.16
## Opacity of the halo at the bottom and the top of its breath.
const HALO_ALPHA_LOW := 0.15
const HALO_ALPHA_HIGH := 0.4

var _radius: float = 1.0
## Height of the ring in the object's own frame: negative when the object sits above the
## ground it stands over.
var _ring_y: float = 0.0
var _ring: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _shard: MeshInstance3D = null
var _revealed: bool = false
## 0 hidden, 1 fully drawn. The tween writes it; every part's transparency is derived
## from it, so a part that also animates on its own (the halo's breath) cannot fight the
## fade.
var _opacity: float = 0.0
var _age: float = 0.0
var _fade: Tween = null


## Builds the cue. Safe to call before the node is in the tree, which is what
## `Interactable` does; the parts are plain children and carry no process of their own.
## `ring_y` is the height of the surface under the object, in the object's own frame.
func setup(radius: float, ring_y: float) -> void:
	_radius = maxf(radius, 0.1)
	# Never above the object itself: a ring drawn over the prop would look like a hat.
	_ring_y = clampf(ring_y, -2.5, 0.0)
	_build()


func is_revealed() -> bool:
	return _revealed


func get_opacity() -> float:
	return _opacity


## The parts, by name, for the tests that assert the cue has the shape it promises.
func get_parts() -> Dictionary:
	return {"ring": _ring, "halo": _halo, "shard": _shard}


## Fades the cue in and starts its motion.
func reveal() -> void:
	_build()
	if _ring == null:
		return
	_revealed = true
	visible = true
	set_process(true)
	_kill_fade()
	_fade = create_tween()
	_fade.tween_method(_set_opacity, _opacity, 1.0, REVEAL_SECONDS)


## Fades the cue out and stops its motion. `immediate` is for the cases where the object
## is going away with the location: there is nothing to fade out of.
func conceal(immediate: bool = false) -> void:
	_revealed = false
	set_process(false)
	_kill_fade()
	if _ring == null:
		visible = false
		return
	if immediate:
		_set_opacity(0.0)
		visible = false
		return
	_fade = create_tween()
	_fade.tween_method(_set_opacity, _opacity, 0.0, CONCEAL_SECONDS)
	_fade.tween_callback(_finish_conceal)


func _build() -> void:
	if _ring != null:
		return
	var ring_radius := clampf(_radius * RING_RADIUS_FACTOR, RING_RADIUS_MIN, RING_RADIUS_MAX)
	_ring = _make_part("GroundRing", WorldCue.dashed_ring_mesh(ring_radius))
	_ring.position = Vector3(0.0, _ring_y + 0.012, 0.0)
	_halo = _make_part(
		"Halo", WorldCue.dashed_ring_mesh(ring_radius * HALO_RADIUS_FACTOR, WorldCue.RING_ARCS, 0.55)
	)
	_halo.position = Vector3(0.0, _ring_y + 0.008, 0.0)
	_shard = _make_part("Shard", WorldCue.shard_mesh(SHARD_SIZE))
	_shard.position = Vector3(0.0, SHARD_HEIGHT, 0.0)
	_set_opacity(0.0)
	visible = false
	set_process(false)


func _make_part(part_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.material_override = WorldCue.material_for(WorldCue.ROLE_TARGET)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	return part


func _process(delta: float) -> void:
	if not _revealed:
		return
	_age += delta
	var breath := 0.5 + 0.5 * sin(_age * TAU / BREATH_SECONDS)
	if _ring != null:
		# The dash pattern is the only reason this rotation is visible at all.
		_ring.rotation.y = fmod(_age * deg_to_rad(SPIN_DEGREES_PER_SECOND), TAU)
		_ring.scale = Vector3.ONE * lerpf(0.985, 1.015, breath)
		_ring.transparency = 1.0 - _opacity
	if _halo != null:
		_halo.rotation.y = -_ring.rotation.y * 0.6
		_halo.transparency = 1.0 - _opacity * lerpf(HALO_ALPHA_LOW, HALO_ALPHA_HIGH, breath)
	if _shard != null:
		var bob := sin(_age * TAU / BOB_SECONDS)
		_shard.position.y = SHARD_HEIGHT + bob * BOB_HEIGHT
		_shard.rotation.y = _age * deg_to_rad(SHARD_TUMBLE_DEGREES_PER_SECOND)
		_shard.rotation.x = _age * deg_to_rad(SHARD_TUMBLE_DEGREES_PER_SECOND * 0.45)
		_shard.transparency = 1.0 - _opacity


func _set_opacity(value: float) -> void:
	_opacity = clampf(value, 0.0, 1.0)
	if _ring == null:
		return
	_ring.transparency = 1.0 - _opacity
	_shard.transparency = 1.0 - _opacity
	if _halo != null:
		# While the cue is not processing (mid-fade-in or mid-fade-out) the halo simply
		# follows the fade; `_process` takes the breath over once the cue is on.
		_halo.transparency = 1.0 - _opacity * (0.5 * (HALO_ALPHA_LOW + HALO_ALPHA_HIGH))


func _finish_conceal() -> void:
	if _revealed:
		# A reveal arrived while the conceal tween was closing: keep the cue up.
		return
	visible = false


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
