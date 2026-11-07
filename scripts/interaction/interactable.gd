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

var _prompt_override: String = ""



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
