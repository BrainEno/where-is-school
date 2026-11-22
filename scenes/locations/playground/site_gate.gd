extends LocationExit
## The hoarding gate of the building under construction (建造中的大楼), once it opens.
##
## Until the protagonist holds the padlock key (`StoryFlags.SITE_GATE_KEY`, found inside the
## building) the gate is only looked at: this exit stays switched off and the yard's
## `SiteLook` (`pg_site`, with its framing of the whole building) answers at the same spot.
## With the key, the two swap: the look is switched off, the padlock and its chain are gone,
## the north leaf stands open and this exit leads in through the porch door.
## `required_flag` and `blocked_inspection_id` say the same thing again, so the door holds
## even if something enables it early.

## How far the north leaf swings in (degrees about its hinge post; negative is into the site).
const OPEN_LEAF_DEGREES := -38.0

@export var look_path: NodePath = ^"../SiteLook"
@export var gate_path: NodePath = ^"../../PlaygroundArt/BuildingSite/Gate"

var _state: Node = null


func _ready() -> void:
	super()
	_state = get_node_or_null(^"/root/GameState")
	if _state != null:
		_state.story_flag_changed.connect(_on_story_flag_changed)
		_state.story_state_replaced.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_apply(_state != null and _state.get_flag(required_flag, false) == true)


func _on_story_flag_changed(flag: StringName, _previous: Variant, _value: Variant) -> void:
	if flag == required_flag:
		_refresh()


func _apply(unlocked: bool) -> void:
	interaction_enabled = unlocked
	var look := get_node_or_null(look_path) as Interactable
	if look != null:
		look.interaction_enabled = not unlocked
	var gate := get_node_or_null(gate_path) as Node3D
	if gate == null:
		return
	for part: String in ["Padlock", "GateChain"]:
		var piece := gate.get_node_or_null(NodePath(part)) as Node3D
		if piece != null:
			piece.visible = not unlocked
	var leaf := gate.get_node_or_null(^"LeafNorth") as Node3D
	if leaf == null:
		return
	var swing := 0.0
	if unlocked:
		swing = OPEN_LEAF_DEGREES
	leaf.rotation_degrees.y = swing
