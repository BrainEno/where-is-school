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

## Height of the hover cue above the interaction point. Small on purpose: the cue
## marks the object, it does not decorate it.
@export var hover_cue_height: float = 0.06

var _prompt_override: String = ""
var _highlighted := false
var _cue: MeshInstance3D = null



func _ready() -> void:
	collision_layer = INTERACTION_LAYER
	monitoring = false
	monitorable = true
	_apply_radius()
	if prompt_text.is_empty():
		push_error("Interactable '%s' has an empty prompt_text." % interact_id)
	_refresh_monitorable()


func can_interact() -> bool:
	return interaction_enabled


## The controller marks exactly one interactable as highlighted: the one E would
## use right now. The cue is built in code from a torus, so it needs no art asset
## and no scene edit per prop.
func set_highlighted(value: bool) -> void:
	if _highlighted == value:
		return
	_highlighted = value
	_ensure_cue()
	if _cue != null:
		_cue.visible = value


func is_highlighted() -> bool:
	return _highlighted


func _ensure_cue() -> void:
	if _cue != null or not is_inside_tree():
		return
	_cue = MeshInstance3D.new()
	_cue.name = "HoverCue"
	var ring := TorusMesh.new()
	ring.inner_radius = maxf(radius * 0.5, 0.16)
	ring.outer_radius = maxf(radius * 0.72, 0.26)
	ring.rings = 24
	ring.ring_segments = 8
	_cue.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.96, 0.87, 0.63, 0.9)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(1.0, 0.86, 0.55)
	material.emission_energy_multiplier = 1.5
	_cue.material_override = material
	_cue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cue.position = Vector3(0.0, hover_cue_height, 0.0)
	add_child(_cue)
	_cue.visible = false


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
