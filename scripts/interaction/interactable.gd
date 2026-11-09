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
## The layer static world geometry lives on. The cue's own downward ray uses it to find
## the floor under the object, and nothing else.
const WORLD_LAYER := 1

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

## Height of the cue's ground ring above the surface under the object. Small on purpose —
## the cue marks the object and the floor it stands on, it does not decorate either.
@export var hover_cue_height: float = 0.06

## Whether being highlighted makes a sound. On for props, and left on: the tick is the one
## piece of feedback that says "the pointer found something" without the player having to
## look at the ring. It is rate-limited in `scripts/audio/cue_audio.gd`, not here.
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

var _prompt_override: String = ""
var _highlighted := false
var _cue: HoverCue = null
## Resolved `support_paths`, or an empty array while unresolved. Rebuilt lazily so the
## probe does not look up node paths on every frame of every target.
var _support_rids: Array[RID] = []
var _support_resolved := false



func _ready() -> void:
	collision_layer = INTERACTION_LAYER
	monitoring = false
	monitorable = true
	_apply_radius()
	if prompt_text.is_empty():
		push_error("Interactable '%s' has an empty prompt_text." % interact_id)
	_refresh_monitorable()


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
## The cue itself lives in `scripts/interaction/hover_cue.gd` and is built the first time
## the object is highlighted, so no prop needs a scene edit and no art asset is involved.
## Highlighting starts and stops a short fade instead of switching a mesh on: a ring that
## appears between two frames reads as a bug, one that arrives reads as a mark.
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
	# The ring is sized from the interaction radius: the radius is where the player has to
	# stand, and the ring's job is to say so — on the floor under the object, which is not
	# where this node is.
	_cue.setup(radius, _cue_ring_height())
	add_child(_cue)


## How far below this node the ground under the object is, in the object's own frame.
##
## An interactable is authored at the middle of the prop — the timetable sheet sits at
## 0.6 m, the schoolbag at 0.2 m — so a ring drawn at the node's own height hangs in the
## air in front of a wall, or slices through a desk. The question the ring answers is
## "where do I stand", which is about the floor. One downward ray on the world layer, cast
## once, the first time the object is highlighted: the same kind of query `PointerNavigator`
## casts from a click. No hit keeps the ring where the node is.
func _cue_ring_height() -> float:
	var world := get_world_3d()
	if world == null:
		return 0.0
	var space := world.direct_space_state
	if space == null:
		return 0.0
	var from := global_position + Vector3.UP * 0.05
	var query := PhysicsRayQueryParameters3D.create(
		from, from + Vector3.DOWN * 3.0, WORLD_LAYER
	)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	var ground: Vector3 = hit.get("position", global_position)
	return clampf(ground.y + hover_cue_height - global_position.y, -2.5, 0.0)


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
