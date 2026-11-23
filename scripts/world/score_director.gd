class_name ScoreDirector
extends Node
## Chooses music for a committed location and the prologue's existing beats. Music
## remains the sole playback owner. The 04b/05b/07b files are shipped alternatives,
## not randomized: no narrative trigger for choosing one has been authored.

const BASE := "res://assets/audio/music/score/"
const ROOM_TRACKS := {
	&"classroom": "01_classroom_wake.mp3",
	&"corridor": "03_corridor_walk.mp3",
	&"front_yard": "03_corridor_walk.mp3",
	&"street": "04_street_load.mp3",
	&"residential": "05_residential_fuzz.mp3",
	&"container_yard": "05_residential_fuzz.mp3",
	&"alley": "06_alley_dub.mp3",
	&"playground": "07_yard_open.mp3",
	&"laboratory": "09_laboratory.mp3",
	&"staff_office": "10_dream_annex.mp3",
	&"archive": "10_dream_annex.mp3",
	&"plan_room": "10_dream_annex.mp3",
	&"projection_room": "10_dream_annex.mp3",
	&"computer_room": "10_dream_annex.mp3",
	&"vacant_office": "10_dream_annex.mp3",
	&"principal_office": "10_dream_annex.mp3",
	&"restroom": "03_corridor_walk.mp3",
	&"restroom_02": "03_corridor_walk.mp3",
	&"restroom_03": "03_corridor_walk.mp3",
}

var _host: LocationHost
var _player: Node3D
var _state: Node
var _music: Node
var _imagining := false
var _ending := false


func setup(host: LocationHost, player: Node3D, state: Node, music: Node) -> void:
	_host = host
	_player = player
	_state = state
	_music = music
	_host.location_entered.connect(_on_location_entered)
	_state.story_flag_changed.connect(_on_flag_changed)
	_state.story_state_replaced.connect(refresh)


func _process(_delta: float) -> void:
	# The stable is part of the corridor scene, not a LocationHost transition.
	# Check the player's feet, also covering an exact-position save restore.
	refresh()


func set_imagining(active: bool) -> void:
	_imagining = active
	refresh()


func show_ending() -> void:
	if _ending:
		return
	_ending = true
	if _music != null:
		_music.play_track(BASE + "11_end_card.mp3")


func refresh() -> void:
	if _music == null or _host == null:
		return
	var location := _host.get_current()
	if _ending:
		# A finished one-shot must stay finished, even if flags change later.
		return
	if location == null:
		return
	var path := track_for(location.location_id, _player.global_position, _imagining, _state)
	if not path.is_empty():
		_music.play_track(path)


static func track_for(id: StringName, position: Vector3, imagining: bool, state: Node) -> String:
	if imagining:
		return BASE + "08_imagined_lesson.mp3"
	if id == &"classroom" and state != null:
		# In old saves MET_Q implied Q's talk was already complete. New saves
		# distinguish his first line from the end of the conversation.
		var waiting := bool(state.get_flag(StoryFlags.Q_FIRST_TALK_DONE,
			state.get_flag(StoryFlags.MET_Q, false))) \
			or bool(state.get_flag(StoryFlags.TEXTBOOK_MISSING, false))
		var finished := bool(state.get_flag(StoryFlags.BELL_RUNG, false)) \
			or bool(state.get_flag(StoryFlags.CLASS_DISMISSED, false)) \
			or bool(state.get_flag(StoryFlags.SKIPPED_CLASS, false))
		if waiting and not finished:
			return BASE + "02_dread_expectation.mp3"
	# The walkable dream stable/approach lies west of the 01 glass entrance.
	# Other floors are the corridor: the same x coordinate there is not the yard.
	if id == &"corridor" and position.y < -2.0 and (
		(position.x < -30.0 and position.z > 3.0)
		or (position.x < -20.0 and position.z > 15.5)
	):
		return BASE + "10_dream_annex.mp3"
	var file := String(ROOM_TRACKS.get(id, ""))
	return BASE + file if not file.is_empty() else ""


func _on_location_entered(_location: LocationRoot, _spawn_id: StringName) -> void:
	refresh()


func _on_flag_changed(_flag: StringName, _previous: Variant, _value: Variant) -> void:
	refresh()
