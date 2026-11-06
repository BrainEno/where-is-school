extends Node3D
class_name ClassroomLocation
## The classroom as a *place*: its markers, its room tone, and a few small
## state-driven visual rules.
##
## This node deliberately owns no narrative logic. It exposes named markers and
## a couple of presentation switches that [PrologueFlow] drives. If the flow
## wants the room lit differently during a rehearsal, it asks for it here; if it
## wants to know where the player wakes up, it asks for the marker.

@onready var seated_spawn: Marker3D = $SpawnSeated
@onready var standing_spawn: Marker3D = $SpawnStanding
@onready var front_focus: Marker3D = $CameraFocusFront
@onready var hall_focus: Marker3D = $CameraFocusHall
@onready var exit_point: Marker3D = $ExitPoint
@onready var npc_anchor_q: Marker3D = $NpcAnchorQ
@onready var teacher_anchor_n: Marker3D = $TeacherAnchorN
@onready var chalkboard: Node3D = $ChalkboardVisual
@onready var door_leaf: Node3D = $DoorLeaf

const ROOM_LIGHT := Color(1.0, 0.94, 0.86)
const REHEARSAL_LIGHT := Color(0.68, 0.76, 0.88)
const ROOM_ENERGY := 1.0
const REHEARSAL_ENERGY := 0.68

var _brownout: bool = false


func spawn_transform(kind: StringName = &"seated") -> Transform3D:
	var marker: Marker3D = seated_spawn if kind == &"seated" else standing_spawn
	return marker.global_transform


func id() -> StringName:
	return &"classroom"


## A restrained whole-room shift used only by the rehearsal beat: the light goes
## cooler and flatter, and nothing in the room actually moves. Because this only
## touches presentation, it cannot alter world state.
func set_rehearsal_lighting(active: bool) -> void:
	if _brownout == active:
		return
	_brownout = active
	for light in get_tree().get_nodes_in_group(&"room_light"):
		var omni := light as OmniLight3D
		if omni == null:
			continue
		omni.light_color = REHEARSAL_LIGHT if active else ROOM_LIGHT
		omni.light_energy = REHEARSAL_ENERGY if active else ROOM_ENERGY


func set_door_open(is_open: bool) -> void:
	if door_leaf == null:
		return
	door_leaf.rotation_degrees.y = -72.0 if is_open else 0.0
