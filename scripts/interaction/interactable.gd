class_name Interactable
extends Area3D
## An authored interaction point in the world.
##
## An interactable declares *what* it offers (an inspection id, a conversation
## route, or an exit) and emits a signal. It never opens UI and never decides how
## the request is presented: the location's sequence director routes it.
##
## Interaction areas live on their own collision layer so the player's interaction
## sensor finds them and the player body ignores them.

signal activated(interactable: Interactable)

const INTERACTION_LAYER := 2
## Pick boxes are the outline meshes' bounds grown by this much on every side, so a pointer
## on the edge of a thin pole or a sheet of paper still finds it.
const PICK_PADDING := 0.05
## No pick box is thinner than this: a notice sheet is 2 cm deep and a ray at a grazing
## angle would slip past it.
const PICK_MIN_THICKNESS := 0.12
## Meshes larger than this along any axis get no pick box: the court markings run the
## length of the yard, and a box around them would swallow every click on the court. The
## longest outlined object that should still be pointable is the schoolyard's 11 m fence
## run with the gap in it.
const PICK_MAX_EXTENT := 12.0
## A mesh thinner than this whose top is more than `FLOOR_PAINT_BELOW_ANCHOR` under the
## anchor is paint on the floor (court markings, a puddle): see `gets_pick_box`.
const FLOOR_PAINT_THICKNESS := 0.05
const FLOOR_PAINT_BELOW_ANCHOR := 0.25

## Stable id used by tests and routing tables.
@export var interact_id: StringName = &""
## Prompt used when no other source describes this object. Authored text is kept
## as a developer fallback; the game normally resolves a locale key instead.
@export var prompt_text: String = "Look at"
## Locale key for the contextual prompt, e.g. "prompt.door_try". Optional: an
## interactable with an inspection uses that inspection's localized prompt.
@export var prompt_key: String = ""
## Speaker this interactable represents, so prompts can name them ("Talk to Q").
@export var speaker_id: StringName = &""
## Set for objects the player examines.
@export var inspection_id: StringName = &""
## Set for characters the player can talk to; treated as a route id, not a
## conversation id, so the routing table can pick a conversation from flags.
@export var conversation_route: StringName = &""
## Radius of the interaction area, applied to the child CollisionShape3D at
## runtime so each instance can be tuned without editing the shared shape.
@export var radius: float = 1.0:
	set(value):
		radius = value
		_apply_radius()
@export var interaction_enabled: bool = true:
	set(value):
		interaction_enabled = value
		if is_inside_tree():
			_refresh_monitorable()

## Whether being highlighted makes a sound. On for props, and left on: the tick is the one
## piece of feedback that says "the pointer found something" without the player having to
## look for the outline. It is rate-limited in `scripts/audio/cue_audio.gd`, not here.
@export var hover_cue_audio: bool = true

## The bodies that belong to this object, or to the structure it is mounted on: the
## desk a schoolbag sits on, the wall a timetable is pinned to, a door's frame.
##
## Paths are relative to this node and may name the collision body itself or a prop
## root, in which case every collision body under it counts. Only these are looked
## through by the line-of-sight probe. Nothing is ever ignored because it happens to
## stand near the object: a wall beside a notice stays a wall, and blocks the view of
## the notice from the other side.
@export var support_paths: PackedStringArray = []

## The meshes the highlight outline traces: the object itself, as the player would point at
## it. Paths are relative to this node and may name a mesh or any node above meshes (a prop
## root, an actor), in which case every visible mesh under it is traced.
##
## Separate from `support_paths` on purpose. Support is what the line-of-sight probe may look
## through, and that includes the wall a timetable is pinned to; the outline is what the
## player is being told about, and that is the sheet, not the wall. When this is empty the
## support paths are used, and meshes parented under this node are always included.
@export var outline_paths: PackedStringArray = []

var _prompt_override: String = ""
var _highlighted := false
var _cue: HoverCue = null
## Resolved `support_paths`, or an empty array while unresolved. Rebuilt lazily so the
## probe does not look up node paths on every frame of every target.
var _support_rids: Array[RID] = []
var _support_resolved := false
## The extra collision shapes built from the outline meshes; see `_build_pick_shapes`.
var _pick_shapes: Array[CollisionShape3D] = []
var _pick_rebuild_queued := false



func _ready() -> void:
	collision_layer = INTERACTION_LAYER
	monitoring = false
	monitorable = true
	_apply_radius()
	if prompt_text.is_empty():
		push_error("Interactable '%s' has an empty prompt_text." % interact_id)
	_refresh_monitorable()
	# Deferred so every sibling of the location (the props, the schoolyard's art) has had
	# its own _ready and its final transform before the boxes are measured.
	_queue_pick_rebuild()
	# Only visible meshes are traced, so the boxes are measured again whenever what is
	# visible changes: the companion is hidden until Q joins, and a hidden branch has no
	# box. `visibility_changed` reaches this node from any ancestor that is shown or hidden.
	_watch_visibility(self)
	var paths := outline_paths if not outline_paths.is_empty() else support_paths
	for path in paths:
		_watch_visibility(get_node_or_null(NodePath(path)))


func _watch_visibility(node: Node) -> void:
	var spatial := node as Node3D
	if spatial == null or spatial.visibility_changed.is_connected(_queue_pick_rebuild):
		return
	spatial.visibility_changed.connect(_queue_pick_rebuild)


func _queue_pick_rebuild() -> void:
	if _pick_rebuild_queued:
		return
	_pick_rebuild_queued = true
	_build_pick_shapes.call_deferred()


## The pointer finds an object where the object is.
##
## An interactable's own shape is a sphere around its anchor, and the anchor of a door or a
## notice is a point in front of it at chest height: the sphere is what the proximity
## sensor and the reach test are about, and as a pointer target it was off to one side of
## the thing on screen - the door's outline would light while the cursor was on the floor
## beside it, and not while the cursor was on the door. So each outline mesh adds a box of
## its own bounds to this area. The sphere stays (removing it would change what the
## proximity sensor sees); the boxes only add the object itself to what can be pointed at.
func _build_pick_shapes() -> void:
	_pick_rebuild_queued = false
	if not is_inside_tree():
		return
	for shape in _pick_shapes:
		if is_instance_valid(shape):
			shape.queue_free()
	_pick_shapes.clear()
	var to_local := global_transform.affine_inverse()
	for mesh in get_outline_meshes():
		if not gets_pick_box(mesh):
			continue
		var box := (to_local * mesh.global_transform) * mesh.get_aabb()
		box = box.grow(PICK_PADDING)
		var size := Vector3(
			maxf(box.size.x, PICK_MIN_THICKNESS),
			maxf(box.size.y, PICK_MIN_THICKNESS),
			maxf(box.size.z, PICK_MIN_THICKNESS)
		)
		var shape := BoxShape3D.new()
		shape.size = size
		var node := CollisionShape3D.new()
		node.name = "PickShape%d" % _pick_shapes.size()
		node.shape = shape
		node.position = box.get_center()
		add_child(node)
		_pick_shapes.append(node)


## Whether an outline mesh adds a pick box: not when it is longer than `PICK_MAX_EXTENT`,
## and not when it is paint on the floor (thinner than `FLOOR_PAINT_THICKNESS` and lying
## below the object's anchor). A box around a painted key would turn a click meant to walk onto it into
## an inspection; the object's anchor sphere still finds it.
func gets_pick_box(mesh: GeometryInstance3D) -> bool:
	if mesh == null or not mesh.is_inside_tree():
		return false
	var world_box := mesh.global_transform * mesh.get_aabb()
	if world_box.size.x > PICK_MAX_EXTENT or world_box.size.y > PICK_MAX_EXTENT \
			or world_box.size.z > PICK_MAX_EXTENT:
		return false
	var flat := world_box.size.y < FLOOR_PAINT_THICKNESS
	var below_anchor := world_box.end.y < global_position.y - FLOOR_PAINT_BELOW_ANCHOR
	return not (flat and below_anchor)


## The boxes the pointer can find this object by, besides its anchor sphere. Public for
## tests: every shipped object with an outline should also be pointable where it is drawn.
func get_pick_shapes() -> Array[CollisionShape3D]:
	return _pick_shapes


## The collision bodies the visibility probe may look through for this object.
##
## Built from the explicit `support_paths` plus anything parented under this node.
## Deliberately *not* "anything close by": that heuristic let a free-standing wall be
## mistaken for part of the object it stood next to.
func get_support_rids() -> Array[RID]:
	if _support_resolved:
		return _support_rids
	var rids: Array[RID] = []
	_collect_collider_rids(self, rids, true)
	for path in support_paths:
		var node := get_node_or_null(NodePath(path))
		if node == null:
			# A path that no longer resolves is a content bug, and a silent one: the
			# object would simply stop being visible from where it should be.
			push_error(
				"Interactable '%s': support path '%s' does not resolve." % [interact_id, path]
			)
			continue
		_collect_collider_rids(node, rids, false)
	_support_rids = rids
	_support_resolved = true
	return _support_rids


func _collect_collider_rids(node: Node, rids: Array[RID], skip_self: bool) -> void:
	if not skip_self:
		var body := node as CollisionObject3D
		if body != null:
			var rid := body.get_rid()
			if not rids.has(rid):
				rids.append(rid)
	for child in node.get_children():
		_collect_collider_rids(child, rids, false)


func can_interact() -> bool:
	return interaction_enabled


## The controller marks exactly one interactable as highlighted: the one E would use
## right now, and the one a click would walk to.
##
## The cue itself lives in `scripts/interaction/hover_cue.gd`: an outline traced around the
## meshes `get_outline_meshes` returns. It is built the first time the object is
## highlighted, and it fades in and out instead of switching: an outline that appears
## between two frames reads as a flicker, one that arrives reads as attention.
func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	_ensure_cue()
	if _cue == null:
		return
	if value:
		_cue.reveal()
		if hover_cue_audio:
			_play_hover_cue()
	else:
		_cue.conceal()


## The hover tick, looked up by path so a headless run without autoloads stays silent.
func _play_hover_cue() -> void:
	var audio := get_node_or_null("/root/CueAudio")
	if audio == null or not audio.has_method("play_hover"):
		return
	audio.play_hover()


func is_highlighted() -> bool:
	return _highlighted


func _ensure_cue() -> void:
	if _cue != null or not is_inside_tree():
		return
	_cue = HoverCue.new()
	_cue.name = "HoverCue"
	_cue.bind(self)
	add_child(_cue)


## Every visible mesh the highlight outline should trace, resolved now.
##
## Resolved on each call rather than cached: an actor's model is instanced at runtime, the
## schoolyard's art pass hides graybox meshes, and a mesh that was hidden when the room
## loaded may be visible by the time the player points at it.
func get_outline_meshes() -> Array[GeometryInstance3D]:
	var meshes: Array[GeometryInstance3D] = []
	var paths := outline_paths if not outline_paths.is_empty() else support_paths
	for path in paths:
		var node := get_node_or_null(NodePath(path))
		if node == null:
			push_error(
				"Interactable '%s': outline path '%s' does not resolve." % [interact_id, path]
			)
			continue
		_collect_meshes(node, meshes)
	for child in get_children():
		if child == _cue or child is CollisionShape3D:
			continue
		_collect_meshes(child, meshes)
	return meshes


func _collect_meshes(node: Node, meshes: Array[GeometryInstance3D]) -> void:
	if node is HoverCue or node is DestinationCue:
		return
	var visual := node as VisualInstance3D
	if visual != null and not visual.is_visible_in_tree():
		# A hidden branch is hidden for everything under it as well.
		return
	var mesh := node as MeshInstance3D
	if mesh != null and mesh.mesh != null and not meshes.has(mesh):
		meshes.append(mesh)
	for child in node.get_children():
		_collect_meshes(child, meshes)


## The cue this object draws while it is highlighted, or null before it has ever been
## highlighted. Public so a test can assert the shape of what the player sees; it
## deliberately does not build the cue, so asking the question costs nothing.
func get_cue() -> HoverCue:
	return _cue


func get_prompt() -> String:
	if not _prompt_override.is_empty():
		return _prompt_override
	return prompt_text


## Locale key override set at runtime (e.g. a door that unlocks). Empty by default.
func get_prompt_override() -> String:
	return _prompt_override


## Lets a location change the prompt after a state change (e.g. a door that
## becomes passable) without rebuilding the area. `prompt` may be a locale key;
## the dialogue controller translates it and falls back to it as literal text.
func set_prompt(prompt: String) -> void:
	_prompt_override = prompt


func clear_prompt_override() -> void:
	_prompt_override = ""


## Called by the player's interaction controller. Returns false when the
## interaction is currently disabled so callers do not need to pre-check.
func activate() -> bool:
	if not can_interact():
		return false
	activated.emit(self)
	return true



func _refresh_monitorable() -> void:
	monitorable = interaction_enabled


func _apply_radius() -> void:
	if not is_inside_tree():
		return
	var shape_node := get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		push_error("Interactable '%s' needs a CollisionShape3D child named 'CollisionShape3D'." % interact_id)
		return
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.1)
	shape_node.shape = sphere
