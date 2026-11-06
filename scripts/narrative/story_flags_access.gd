class_name StoryFlags
extends RefCounted
## Resolves the GameState autoload by path.
##
## Why not reference the `GameState` singleton identifier directly? A headless test
## run with `godot --headless --path . --script tests/foo.gd` never instantiates
## autoloads, so scripts that name the singleton fail to compile and the test
## suite cannot exercise them. Resolving `/root/GameState` at call time keeps the
## ownership model (GameState still owns all flags) while letting a test add a
## GameState instance itself.
##
## There is deliberately no caching: a test may free and re-add the node between
## cases, and a stale reference would hide that.

const AUTOLOAD_PATH := "/root/GameState"


static func node() -> Node:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("StoryFlags used before a SceneTree existed.")
		return null
	var state: Node = tree.root.get_node_or_null(AUTOLOAD_PATH)
	if state == null:
		push_error("StoryFlags could not find the GameState autoload at %s." % AUTOLOAD_PATH)
	return state


static func set_flag(flag: StringName, value: Variant = true) -> void:
	var state: Node = node()
	if state != null:
		state.call("set_flag", flag, value)


static func has_flag(flag: StringName) -> bool:
	var state: Node = node()
	return state != null and bool(state.call("has_flag", flag))


static func get_flag(flag: StringName, default_value: Variant = null) -> Variant:
	var state: Node = node()
	if state == null:
		return default_value
	return state.call("get_flag", flag, default_value)


static func snapshot() -> Dictionary:
	var state: Node = node()
	if state == null:
		return {}
	return state.call("get_snapshot") as Dictionary
