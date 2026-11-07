class_name CheckResolver
extends RefCounted
## The one dice core both visible and hidden checks go through.
##
## Rules are deliberately small enough to explain in one line:
##
##     d10 + ability value + situational modifier  >=  difficulty  -> success
##
## Three properties matter more than the numbers:
##
## - **One code path.** A visible check (the player picked an inner voice) and a
##   hidden check (a voice speaks up on its own) differ only in whether the result
##   is shown. They cannot drift into two different systems.
## - **The die is a function of the run and the check, not of the moment.** The
##   face comes from `hash(session seed, key)`, so the same check always falls the
##   same way inside one session. Reloading a scene or clicking the same option
##   again cannot reroll it, which is exactly the exploit a plain `randi()` invites.
## - **Testable without the engine's clock.** `session_seed` is injected, so a test
##   fixes it, computes what the die must be and asserts the whole result.
##
## The resolver knows nothing about content, UI, or story flags: callers pass the
## ability value, the difficulty and the situational modifier they already worked
## out. That keeps it usable from the dialogue runtime, from a passive-ability
## trigger, and from a unit test that has no scene at all.

## Faces on the die. Kept in one constant so the maths can be read in one place.
const DIE_FACES := 10
## Content validation refuses values outside this range; the resolver clamps, so a
## hand-edited file can never produce a negative difficulty or a 0-face die.
const MIN_DIFFICULTY := 1
const MAX_DIFFICULTY := 30

## The seed of this play session. Injected by whoever owns the resolver.
var _session_seed: int = 0


func _init(session_seed: int = 0) -> void:
	_session_seed = session_seed


func get_session_seed() -> int:
	return _session_seed


func set_session_seed(session_seed: int) -> void:
	_session_seed = session_seed


## The face a given check shows in this session. Exposed so a test can predict the
## outcome instead of looping until the roll happens to be interesting.
func face_for(key: String) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%s" % [_session_seed, key])
	return rng.randi_range(1, DIE_FACES)


## Rolls one check and returns the whole result as data, not as a boolean: the
## presentation layer needs the number the player saw, and the content layer needs
## to know which branch to take.
##
## Modifiers may be negative (a distracting noise, a punished memory).
func roll(
	ability_id: StringName,
	ability_value: int,
	difficulty: int,
	modifier: int = 0,
	key: String = ""
) -> Dictionary:
	var safe_difficulty := clampi(difficulty, MIN_DIFFICULTY, MAX_DIFFICULTY)
	var die := face_for(key)
	var total := die + ability_value + modifier
	return {
		"ability": ability_id,
		"ability_value": ability_value,
		"die": die,
		"die_faces": DIE_FACES,
		"modifier": modifier,
		"total": total,
		"difficulty": safe_difficulty,
		"margin": total - safe_difficulty,
		"success": total >= safe_difficulty,
		"key": key,
	}


## Rebuilds a result dictionary from a recorded one, so re-entering a check that
## already happened reports the same die instead of pretending to roll again. The
## `reused` flag is what the panel uses to avoid showing a second animation.
static func reuse(recorded: Dictionary) -> Dictionary:
	var copy := recorded.duplicate()
	copy["reused"] = true
	return copy


## Sums the situational modifier a check declares (a list of flag/value pairs).
## Missing flags contribute nothing, so content can gate a bonus on something the
## player may never have done.
static func modifier_for(modifier_table: Array, flag_lookup: Callable) -> int:
	var total := 0
	for entry: Variant in modifier_table:
		if not (entry is Dictionary):
			continue
		var data: Dictionary = entry
		var flag := StringName(String(data.get("flag", "")))
		if String(flag).is_empty():
			continue
		if flag_lookup.call(flag, false) == true:
			total += int(data.get("value", 0))
	return total


static func is_valid_difficulty(value: int) -> bool:
	return value >= MIN_DIFFICULTY and value <= MAX_DIFFICULTY


## One readable line for logs and failure reports: "ledger 3 + d10 7 + 0 = 10 vs 11".
static func describe(result: Dictionary) -> String:
	return "%s %d + d%d %d %s%d = %d vs %d (%s)" % [
		String(result.get("ability", "")),
		int(result.get("ability_value", 0)),
		int(result.get("die_faces", DIE_FACES)),
		int(result.get("die", 0)),
		"+" if int(result.get("modifier", 0)) >= 0 else "-",
		absi(int(result.get("modifier", 0))),
		int(result.get("total", 0)),
		int(result.get("difficulty", 0)),
		"success" if result.get("success", false) == true else "failure",
	]
