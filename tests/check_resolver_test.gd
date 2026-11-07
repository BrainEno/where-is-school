extends SceneTree
## Proves the dice core is small, explainable, and reproducible.
##
## The resolver is the one place a die is thrown. Everything asserted here is a
## property the rest of the game depends on:
##
## - the formula is exactly d10 + ability value + situational modifier >= difficulty;
## - both edges of the die behave (a 1 can still succeed, a 10 can still fail);
## - a fixed session seed reproduces every result, which is what makes the CI run
##   deterministic instead of lucky;
## - the same check in the same session always shows the same face, so walking away
##   and coming back is not a reroll;
## - reusing a recorded result reports `reused` and does not invent a new die.

const Harness = preload("res://tests/test_harness.gd")

const SEED := 424242
const ABILITY_VALUE := 4

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "check_resolver_test.gd")
	call_deferred("_run")


func _run() -> void:
	_check_formula()
	_check_edges()
	_check_determinism()
	_check_no_reroll_by_key()
	_check_modifiers()
	_check_clamping()
	_check_reuse()
	_check_describe()
	Harness.finish(self, _failures, "the dice core follows one formula, one seed, one result.")


# --- cases ------------------------------------------------------------------


## For every possible face, a difficulty of exactly `face + value` succeeds and one
## point more fails. That is the whole formula, checked ten times.
func _check_formula() -> void:
	var resolver := CheckResolver.new(SEED)
	for index in 10:
		var key := "formula/%d" % index
		var face := resolver.face_for(key)
		if face < 1 or face > CheckResolver.DIE_FACES:
			_failures.append("A d10 produced %d, which is not on the die." % face)
			return
		var exact := resolver.roll(&"boundary", ABILITY_VALUE, face + ABILITY_VALUE, 0, key)
		if not bool(exact["success"]):
			_failures.append(
				"face %d + value %d should meet difficulty %d but failed."
				% [face, ABILITY_VALUE, face + ABILITY_VALUE]
			)
		if int(exact["total"]) != face + ABILITY_VALUE:
			_failures.append("The total is not die + ability value (got %d)." % int(exact["total"]))
		if int(exact["margin"]) != 0:
			_failures.append("A success exactly on the difficulty should have margin 0.")
		var over := resolver.roll(&"boundary", ABILITY_VALUE, face + ABILITY_VALUE + 1, 0, key)
		if bool(over["success"]):
			_failures.append(
				"face %d + value %d should fail difficulty %d but succeeded."
				% [face, ABILITY_VALUE, face + ABILITY_VALUE + 1]
			)
		if int(over["margin"]) != -1:
			_failures.append("A one-point failure should have margin -1.")


## The two edges that make a roll feel like a roll: the worst die can still carry a
## strong attempt, and the best die cannot save an impossible one.
func _check_edges() -> void:
	var resolver := CheckResolver.new(SEED)
	var worst := _key_with_face(resolver, 1)
	var best := _key_with_face(resolver, CheckResolver.DIE_FACES)
	if worst.is_empty() or best.is_empty():
		_failures.append("Could not find keys for the lowest and highest faces.")
		return
	var hopeful := resolver.roll(&"boundary", 6, 7, 0, worst)
	if not bool(hopeful["success"]):
		_failures.append("A 1 with a value of 6 should still reach difficulty 7.")
	var hopeless := resolver.roll(&"boundary", 0, 11, 0, best)
	if bool(hopeless["success"]):
		_failures.append("A 10 against difficulty 11 should fail even on the best face.")


func _check_determinism() -> void:
	var first := CheckResolver.new(SEED)
	var second := CheckResolver.new(SEED)
	for index in 25:
		var key := "same/%d" % index
		var a := first.roll(&"ledger", 3, 9, 1, key)
		var b := second.roll(&"ledger", 3, 9, 1, key)
		if a != b:
			_failures.append("Two resolvers with seed %d disagreed on '%s'." % [SEED, key])
			return
	var other := CheckResolver.new(SEED + 1)
	if other.face_for("same/0") == first.face_for("same/0"):
		# Not a failure on its own, but with 10 faces a different seed that never
		# differs across 25 keys would mean the seed is ignored.
		var differs := false
		for index in 25:
			if other.face_for("same/%d" % index) != first.face_for("same/%d" % index):
				differs = true
				break
		if not differs:
			_failures.append("Changing the session seed never changed a die.")


## The anti-reroll property: one key, one face, forever — inside the session.
func _check_no_reroll_by_key() -> void:
	var resolver := CheckResolver.new(SEED)
	var first := resolver.roll(&"boundary", 4, 11, 0, "pg_shed/ps_boundary_check")
	for attempt in 5:
		var again := resolver.roll(&"boundary", 4, 11, 0, "pg_shed/ps_boundary_check")
		if int(again["die"]) != int(first["die"]) or bool(again["success"]) != bool(first["success"]):
			_failures.append("Re-rolling the same key changed the outcome on attempt %d." % attempt)
			return


func _check_modifiers() -> void:
	var resolver := CheckResolver.new(SEED)
	var key := "modifier/0"
	var face := resolver.face_for(key)
	var difficulty := face + 3
	var plain := resolver.roll(&"onlooker", 3, difficulty, 0, key)
	if not bool(plain["success"]):
		_failures.append("The unmodified baseline should succeed at the exact difficulty.")
	var helped := resolver.roll(&"onlooker", 3, difficulty + 2, 2, key)
	if not bool(helped["success"]):
		_failures.append("A +2 modifier did not turn the same difficulty into a success.")
	var hurt := resolver.roll(&"onlooker", 3, difficulty, -2, key)
	if bool(hurt["success"]):
		_failures.append("A -2 modifier did not turn the same difficulty into a failure.")

	var table := [{"flag": &"saw_set_square", "value": 1}, {"flag": &"met_q", "value": 2}]
	var sum := CheckResolver.modifier_for(table, func(flag: StringName, default_value: Variant) -> Variant:
		return true if flag == &"met_q" else default_value
	)
	if sum != 2:
		_failures.append("A modifier table should only count flags that are set (got %d)." % sum)


func _check_clamping() -> void:
	var resolver := CheckResolver.new(SEED)
	var low := resolver.roll(&"echo", 0, -5, 0, "clamp/low")
	if int(low["difficulty"]) != CheckResolver.MIN_DIFFICULTY:
		_failures.append("A negative difficulty was not clamped to the minimum.")
	var high := resolver.roll(&"echo", 0, 999, 0, "clamp/high")
	if int(high["difficulty"]) != CheckResolver.MAX_DIFFICULTY:
		_failures.append("An absurd difficulty was not clamped to the maximum.")
	if CheckResolver.is_valid_difficulty(0) or CheckResolver.is_valid_difficulty(99):
		_failures.append("is_valid_difficulty accepted a value outside its own range.")


func _check_reuse() -> void:
	var resolver := CheckResolver.new(SEED)
	var original := resolver.roll(&"echo", 2, 8, 0, "reuse/0")
	var replayed := CheckResolver.reuse(original)
	if bool(original.get("reused", false)):
		_failures.append("A fresh roll should not be marked as reused.")
	if not bool(replayed.get("reused", false)):
		_failures.append("A replayed result should be marked as reused.")
	if int(replayed["die"]) != int(original["die"]) or int(replayed["total"]) != int(original["total"]):
		_failures.append("Reusing a result changed its numbers.")
	if replayed["ability"] != original["ability"]:
		_failures.append("Reusing a result changed the ability it belongs to.")


func _check_describe() -> void:
	var resolver := CheckResolver.new(SEED)
	var result := resolver.roll(&"boundary", 4, 11, -1, "describe/0")
	var line := CheckResolver.describe(result)
	if not line.begins_with("boundary 4 + d10 "):
		_failures.append("The readable form does not name the voice and the die: '%s'" % line)
	if not (" vs 11 " in line):
		_failures.append("The readable form does not show the difficulty: '%s'" % line)


# --- helpers ----------------------------------------------------------------


func _key_with_face(resolver: CheckResolver, wanted: int) -> String:
	for index in 2000:
		var key := "edge/%d" % index
		if resolver.face_for(key) == wanted:
			return key
	return ""
