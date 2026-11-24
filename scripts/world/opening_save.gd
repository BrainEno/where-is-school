class_name OpeningSave
extends RefCounted
## The director's half of saving: deciding that the world is at a checkpoint, reading a
## save at boot, and putting a restored room back on screen.
##
## What a save contains and why is ADR 0005; the bytes are the `Save` autoload's business.
## This object was split out of `OpeningSequence` (issue #223), which keeps *when* - it
## calls `autosave()` at beat boundaries and `restore()` before the first step is chosen -
## and its public `can_save()`, `autosave()` and `autosave_enabled`.
##
## A host without the `Save` autoload (most headless tests) gets an object that simply
## does not save: every call here is a no-op then.

const SAVE_NOTICE_SECONDS := 9.0
const SAVE_ERROR_TITLE_KEY := "save.error.title"
const SAVE_ERROR_ADVICE_KEY := "save.error.advice"
const SAVE_ERROR_QUARANTINE_KEY := "save.error.quarantined"

## The `Save` autoload, or null when this host has none.
var save: Node = null
## True when this session came out of a save file rather than a new game.
var restored := false
## What the save reader said when it refused the file, kept for the on-screen report.
var problem: Dictionary = {}


## Connects to the save autoload, if this host has one, and hands it the node a save
## describes: the room, the player and the dialogue controller are children of `world`.
func bind(director: Node, world: Node) -> void:
	var found := director.get_node_or_null(^"/root/Save")
	if found == null:
		return
	save = found
	if save.has_method("bind_world"):
		save.bind_world(world)


func can_save() -> bool:
	return save != null


## Writes a checkpoint, unless `enabled` is false or there is nothing to write to.
## Returns the save's result, or `{}` when nothing was attempted.
func autosave(why: String, enabled: bool) -> Dictionary:
	if not enabled or save == null or not save.has_method("save_game"):
		return {}
	var result: Dictionary = save.save_game()
	if result.get("ok", false) != true:
		push_error(
			"OpeningSequence: the checkpoint after '%s' was not written: %s"
			% [why, String(result.get("detail", ""))]
		)
	return result


## Reads the save and applies it, if there is one. Returns the `world` block (which may
## be empty) and sets `restored`. A file that cannot be trusted is refused with the
## reason kept in `problem` for `announce_problem()`; the session is untouched.
func restore() -> Dictionary:
	restored = false
	if save == null or not save.has_method("load_game") or not save.has_save():
		return {}
	var result: Dictionary = save.load_game()
	if result.get("ok", false) != true:
		problem = result
		push_error(
			"OpeningSequence: the save was refused (%s): %s"
			% [String(result.get("reason", "")), String(result.get("detail", ""))]
		)
		return {}
	restored = true
	var world: Variant = result.get("world", {})
	return world if world is Dictionary else {}


## Enters the room a restored `world` block names and stands the player where they
## stood. False - with the reason logged - when there is no block, the catalog does not
## know the room, or the room refuses to load; the caller then uses the start room.
func load_world(world: Dictionary, catalog: LocationCatalog, locations: LocationHost,
		player: PlayerController, game_state: Node) -> bool:
	if world.is_empty():
		return false
	var location_id := StringName(String(world.get("location_id", "")))
	var entry := catalog.get_entry(location_id) if catalog != null else null
	if entry == null:
		push_error(
			"OpeningSequence: the save names location '%s', which the catalog does not describe."
			% location_id
		)
		return false
	var spawn := StringName(String(world.get("spawn", "")))
	if not locations.load_location(entry.scene, spawn, player, location_id):
		push_error(
			"OpeningSequence: the save's location '%s' (spawn '%s') could not be entered."
			% [location_id, spawn]
		)
		return false
	game_state.set_flag(StoryFlags.CURRENT_LOCATION, location_id)
	if world.has("position"):
		var pose := saved_transform(world)
		# Earlier saves could record a position below the world. Keep the entry
		# LocationHost just placed rather than uncovering a void on Continue.
		if not locations.get_current().is_below_playable_space(pose.origin):
			player.teleport(pose)
			# teleport() keeps the current heading for an identity basis, which is what a
			# saved -Z heading produces. The entry has its own heading now, so the saved one
			# is restored explicitly.
			var facing := vec3(world.get("facing", null))
			if facing.length_squared() > 0.0001:
				player.face_toward(facing)
	return true


## Position and facing as a transform. `teleport()` reads the facing off the basis, so
## the player comes back looking where they were looking.
static func saved_transform(world: Dictionary) -> Transform3D:
	var position := vec3(world.get("position", null))
	var basis := Basis.IDENTITY
	var facing := vec3(world.get("facing", null))
	if facing.length_squared() > 0.0001:
		basis = Basis.looking_at(facing, Vector3.UP)
	return Transform3D(basis, position)


## A three-number array as a vector; zero for anything else.
static func vec3(value: Variant) -> Vector3:
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.ZERO
	var items: Array = value
	return Vector3(float(items[0]), float(items[1]), float(items[2]))


## Tells the player, on screen, that their save could not be read and what happened to
## it. A silent reset is the failure mode ADR 0005 exists to prevent. `director` provides
## the story clock (`wait_seconds`), so the notice stays up while the game is paused.
func announce_problem(ui: GameUI, director: Node) -> void:
	if ui == null or ui.end_card == null:
		return
	var detail := String(problem.get("detail", ""))
	var body := "%s\n%s" % [detail, L10n.t(SAVE_ERROR_ADVICE_KEY)]
	var hint := ""
	var quarantined_to := String(problem.get("quarantined_to", ""))
	if not quarantined_to.is_empty():
		hint = L10n.t(SAVE_ERROR_QUARANTINE_KEY, {"path": quarantined_to})
	ui.end_card.present(L10n.t(SAVE_ERROR_TITLE_KEY), body, hint)
	await director.wait_seconds(SAVE_NOTICE_SECONDS)
	ui.end_card.dismiss()
