extends Interactable
## The padlock key of the hoarding gate, lying in the chalk star inside the building under
## construction. Reading it (`site_key`) sets `StoryFlags.SITE_GATE_KEY` through the
## inspection's own effect; this script only makes the room agree: once the flag is set the
## key is gone from the floor and there is nothing left here to point at. The porch door
## (`site_interior_porch_door`) and the yard's gate (`site_gate.gd`) read the same flag.

@export var key_path: NodePath = ^"../../Key"

var _state: Node = null


func _ready() -> void:
	super()
	_state = get_node_or_null(^"/root/GameState")
	if _state != null:
		_state.story_flag_changed.connect(_on_story_flag_changed)
		_state.story_state_replaced.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_apply(_state != null and _state.get_flag(StoryFlags.SITE_GATE_KEY, false) == true)


func _on_story_flag_changed(flag: StringName, _previous: Variant, _value: Variant) -> void:
	if flag == StoryFlags.SITE_GATE_KEY:
		_refresh()


func _apply(taken: bool) -> void:
	interaction_enabled = not taken
	var key := get_node_or_null(key_path) as Node3D
	if key != null:
		key.visible = not taken
