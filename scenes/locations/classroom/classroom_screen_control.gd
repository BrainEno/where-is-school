class_name ClassroomScreenControl
extends Node
## The pull cord of the biology classroom's projection screen (issue #159).
##
## The screen (`ProjectorScreen`) starts rolled up, so the whole blackboard is there
## for the lesson. Using its pull tab (`Interactables/ProjectorScreenPull`, a
## `StagedInteractable`) rolls it down over the left half of the board, and using it
## again rolls it back up. That is all it does: nothing is projected, nothing is said,
## and no story flag or save field is written - the screen is furniture, so a room that
## is loaded again starts with it rolled up, the way it was built.
##
## The roll runs inside the director's beat (see `StagedInteractable`), so the player
## stands still for the second and a half it takes and nothing else can start.

const PROMPT_DOWN := "prompt.projector_screen_down"
const PROMPT_UP := "prompt.projector_screen_up"

@export var screen_path: NodePath = ^"../WallNorth/ProjectorScreen"
@export var pull_path: NodePath = ^"../Interactables/ProjectorScreenPull"

var _screen: ProjectorScreen = null
var _pull: StagedInteractable = null


func _ready() -> void:
	_screen = get_node_or_null(screen_path) as ProjectorScreen
	_pull = get_node_or_null(pull_path) as StagedInteractable
	if _screen == null:
		push_error("ClassroomScreenControl: '%s' is missing or not a ProjectorScreen." % screen_path)
	if _pull == null:
		push_error("ClassroomScreenControl: '%s' is missing or not staged." % pull_path)
	if _screen == null or _pull == null:
		return
	_pull.stage_handler = _stage_pull
	_update_prompt()


func _stage_pull(_director: Node) -> Dictionary:
	await toggle_screen()
	return {}


## Rolls the screen down if it is up, up if it is down. Public for the tests.
func toggle_screen(animated: bool = true) -> void:
	if _screen == null:
		return
	await _screen.toggle(animated)
	_update_prompt()


func _update_prompt() -> void:
	if _pull != null and _screen != null:
		_pull.set_prompt(PROMPT_UP if _screen.is_unrolled() else PROMPT_DOWN)
