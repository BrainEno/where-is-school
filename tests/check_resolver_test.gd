extends SceneTree
## Proves the dice core is small, explainable, and reproducible.
##
## The resolver is the one place a die is thrown. Everything asserted here is a
## property the rest of the game depends on:
##
## - the formula is exactly 2d6 + ability value + situational modifier >= difficulty;
## - both edges of the roll behave (a 2 can still succeed, a 12 can still fail);
## - the roll really is two six-sided dice and not one flat number;
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
	_check_two_dice()
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
		var face := resolver.dice_total_for(key)
		if face < CheckResolver.MIN_TOTAL or face > CheckResolver.MAX_TOTAL:
			_failures.append("2d6 produced %d, outside 2..12." % face)
			return
		var exact := resolver.roll(&"orientation", ABILITY_VALUE, face + ABILITY_VALUE, 0, key)
		if not bool(exact["success"]):
			_failures.append(
				"face %d + value %d should meet difficulty %d but failed."
				% [face, ABILITY_VALUE, face + ABILITY_VALUE]
			)
		if int(exact["total"]) != face + ABILITY_VALUE:
			_failures.append("The total is not die + ability value (got %d)." % int(exact["total"]))
		if int(exact["margin"]) != 0:
			_failures.append("A success exactly on the difficulty should have margin 0.")
		var over := resolver.roll(&"orientation", ABILITY_VALUE, face + ABILITY_VALUE + 1, 0, key)
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
	var worst := _key_with_roll(resolver, CheckResolver.MIN_TOTAL)
	var best := _key_with_roll(resolver, CheckResolver.MAX_TOTAL)
	if worst.is_empty() or best.is_empty():
		_failures.append("Could not find keys for the lowest and highest rolls.")
		return
	var hopeful := resolver.roll(&"orientation", 6, 8, 0, worst)
	if not bool(hopeful["success"]):
		_failures.append("A 2 with a value of 6 should still reach difficulty 8.")
	var hopeless := resolver.roll(&"orientation", 0, 13, 0, best)
	if bool(hopeless["success"]):
		_failures.append("A 12 against difficulty 13 should fail even on the best roll.")


## Two dice, not one: a single face is 1..6 and the sum is 2..12. Without this a
## resolver that quietly rolled one d12 would still pass the formula test.
func _check_two_dice() -> void:
	var resolver := CheckResolver.new(SEED)
	for index in 40:
		var key := "dice/%d" % index
		var roll := resolver.roll(&"orientation", 3, 9, 0, key)
		var faces: Array = roll.get("dice", [])
		if faces.size() != 2:
			_failures.append("A roll did not record two dice (got %d)." % faces.size())
			return
		for face: int in faces:
			if face < 1 or face > CheckResolver.DIE_FACES:
				_failures.append("A die showed %d, which is not on a d6." % face)
				return
		if int(roll["die"]) != int(faces[0]) + int(faces[1]):
			_failures.append("The recorded total is not the sum of its dice.")
			return
		if int(roll["die"]) < CheckResolver.MIN_TOTAL or int(roll["die"]) > CheckResolver.MAX_TOTAL:
			_failures.append("2d6 produced %d, outside 2..12." % int(roll["die"]))
			return
	# A flat distribution would make 4 and 10 equally common; 2d6 should not.
	var low := 0
	var high := 0
	for index in 400:
		var total := resolver.dice_total_for("bell/%d" % index)
		if total <= 5:
			low += 1
		elif total >= 10:
			high += 1
	if low == 0 or high == 0 or low == high:
		_failures.append("The roll does not look like a 2d6 bell curve (low %d, high %d)." % [low, high])


func _check_determinism() -> void:
	var first := CheckResolver.new(SEED)
	var second := CheckResolver.new(SEED)
	for index in 25:
		var key := "same/%d" % index
		var a := first.roll(&"orientation", 3, 9, 1, key)
		var b := second.roll(&"orientation", 3, 9, 1, key)
		if a != b:
			_failures.append("Two resolvers with seed %d disagreed on '%s'." % [SEED, key])
			return
	var other := CheckResolver.new(SEED + 1)
	if other.dice_total_for("same/0") == first.dice_total_for("same/0"):
		# Not a failure on its own, but with 2d6 a different seed that never
		# differs across 25 keys would mean the seed is ignored.
		var differs := false
		for index in 25:
			if other.dice_total_for("same/%d" % index) != first.dice_total_for("same/%d" % index):
				differs = true
				break
		if not differs:
			_failures.append("Changing the session seed never changed a die.")


## The anti-reroll property: one key, one face, forever — inside the session.
func _check_no_reroll_by_key() -> void:
	var resolver := CheckResolver.new(SEED)
	var first := resolver.roll(&"orientation", 4, 11, 0, "pg_shed/ps_boundary_check")
	for attempt in 5:
		var again := resolver.roll(&"orientation", 4, 11, 0, "pg_shed/ps_boundary_check")
		if int(again["die"]) != int(first["die"]) or bool(again["success"]) != bool(first["success"]):
			_failures.append("Re-rolling the same key changed the outcome on attempt %d." % attempt)
			return


func _check_modifiers() -> void:
	var resolver := CheckResolver.new(SEED)
	var key := "modifier/0"
	var face := resolver.dice_total_for(key)
	var difficulty := face + 3
	var plain := resolver.roll(&"orientation", 3, difficulty, 0, key)
	if not bool(plain["success"]):
		_failures.append("The unmodified baseline should succeed at the exact difficulty.")
	var helped := resolver.roll(&"orientation", 3, difficulty + 2, 2, key)
	if not bool(helped["success"]):
		_failures.append("A +2 modifier did not turn the same difficulty into a success.")
	var hurt := resolver.roll(&"orientation", 3, difficulty, -2, key)
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
	var low := resolver.roll(&"orientation", 0, -5, 0, "clamp/low")
	if int(low["difficulty"]) != CheckResolver.MIN_DIFFICULTY:
		_failures.append("A negative difficulty was not clamped to the minimum.")
	var high := resolver.roll(&"orientation", 0, 999, 0, "clamp/high")
	if int(high["difficulty"]) != CheckResolver.MAX_DIFFICULTY:
		_failures.append("An absurd difficulty was not clamped to the maximum.")
	if CheckResolver.is_valid_difficulty(0) or CheckResolver.is_valid_difficulty(99):
		_failures.append("is_valid_difficulty accepted a value outside its own range.")


func _check_reuse() -> void:
	var resolver := CheckResolver.new(SEED)
	var original := resolver.roll(&"orientation", 2, 8, 0, "reuse/0")
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
	var result := resolver.roll(&"orientation", 4, 11, -1, "describe/0")
	var line := CheckResolver.describe(result)
	if not line.begins_with("orientation 4 + 2d6 "):
		_failures.append("The readable form does not name the voice and the roll: '%s'" % line)
	if not (" vs 11 " in line):
		_failures.append("The readable form does not show the difficulty: '%s'" % line)


# --- helpers ----------------------------------------------------------------


func _key_with_roll(resolver: CheckResolver, wanted: int) -> String:
	for index in 4000:
		var key := "edge/%d" % index
		if resolver.dice_total_for(key) == wanted:
			return key
	return ""
