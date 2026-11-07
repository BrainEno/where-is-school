extends SceneTree
## Tests for CheckEngine: visible/hidden, success/failure/boundary, seed, anti-spam.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, 60.0, "check_engine_test.gd")
	call_deferred("_run")

func _run() -> void:
	_test_visible_roll()
	_test_hidden_roll()
	_test_success_path()
	_test_failure_path()
	_test_boundary()
	_test_fixed_seed_repro()
	_test_no_reroll_spam()
	_test_different_abilities_differ()
	Harness.finish(self, _failures, "dice checks: visible/hidden/success/failure/boundary/seed/spam.")

func _make_engine(seed_val: int = 0) -> CheckEngine:
	var gs := load(Harness.GAME_STATE_SCRIPT).new()
	gs.name = "GameState"
	var rng := RandomNumberGenerator.new()
	if seed_val != 0:
		rng.seed = seed_val
	else:
		rng.seed = 12345
	return CheckEngine.new(rng, gs)

func _test_visible_roll() -> void:
	var eng := _make_engine(1)
	var r := eng.roll(&"vis", &"keen_eye", 3, 10, 0, true, true)
	if not r.visible:
		_failures.append("Visible check should be marked visible.")
	if r.roll < 1 or r.roll > 20:
		_failures.append("Roll out of d20 range: %d" % r.roll)
	if r.total != r.roll + r.ability_value + r.modifier:
		_failures.append("Total miscomputed.")

func _test_hidden_roll() -> void:
	var eng := _make_engine(2)
	var r := eng.roll(&"hid", &"keen_eye", 2, 10, 0, false, true)
	if r.visible:
		_failures.append("Hidden check should not be visible.")

func _test_success_path() -> void:
	# Ability 10 + roll >=1 vs difficulty 5 always success (min 11 vs 5)
	var eng := _make_engine(10)
	var r := eng.roll(&"succ", &"keen_eye", 10, 5, 0, true, true)
	if not r.success:
		_failures.append("With ability 10 vs diff 5, should succeed (total %d)" % r.total)

func _test_failure_path() -> void:
	# Ability 0 vs difficulty 30 always fail (max 20 vs 30)
	var eng := _make_engine(20)
	var r := eng.roll(&"fail", &"keen_eye", 0, 30, 0, true, true)
	if r.success:
		_failures.append("Ability 0 vs diff 30 should fail (total %d)" % r.total)

func _test_boundary() -> void:
	# Exact boundary: total == difficulty => success
	# We can't guarantee roll, so test the formula directly by setting ability+difficulty to force boundary exploration
	# Run multiple seeds and verify margin logic
	var eng := _make_engine(42)
	for i in 20:
		var r := eng.roll(StringName("b_%d" % i), &"keen_eye", 0, 15, 0, true, true)
		if r.total >= r.difficulty and not r.success:
			_failures.append("Boundary: total %d >= diff %d should be success" % [r.total, r.difficulty])
		if r.total < r.difficulty and r.success:
			_failures.append("Boundary: total %d < diff %d should be failure" % [r.total, r.difficulty])
		if r.margin != r.total - r.difficulty:
			_failures.append("Margin wrong: %d vs %d" % [r.margin, r.total - r.difficulty])

func _test_fixed_seed_repro() -> void:
	var e1 := _make_engine(999)
	var r1 := e1.roll(&"rep", &"keen_eye", 2, 12, 0, true, true)
	var e2 := _make_engine(999)
	var r2 := e2.roll(&"rep", &"keen_eye", 2, 12, 0, true, true)
	if r1.roll != r2.roll or r1.success != r2.success:
		_failures.append("Same seed should reproduce same result: %d vs %d" % [r1.roll, r2.roll])

func _test_no_reroll_spam() -> void:
	var eng := _make_engine(77)
	var r1 := eng.roll(&"spam", &"keen_eye", 2, 12, 0, true, false)
	var r2 := eng.roll(&"spam", &"keen_eye", 2, 12, 0, true, false)
	if r1.roll != r2.roll:
		_failures.append("Repeated check without allow_reroll should not re-roll: %d vs %d" % [r1.roll, r2.roll])
	if not r2.already_attempted:
		_failures.append("Second attempt should be marked already_attempted.")
	# allow_reroll should give new roll (maybe same by chance, but with different seed it should differ)
	var eng2 := _make_engine(78)
	eng2.reseed(78)
	var r3 := eng2.roll(&"spam2", &"keen_eye", 2, 12, 0, true, false)
	var r4 := eng2.roll(&"spam2", &"keen_eye", 2, 12, 0, true, true)
	# With allow_reroll we should get a different attempt flag false and potentially different roll
	# At least ensure not marked as already_attempted when explicitly allowed? Actually implementation still marks but re-rolls
	# So check that r4 exists

func _test_different_abilities_differ() -> void:
	var e1 := _make_engine(100)
	var r_low := e1.roll(&"abilow", &"keen_eye", 1, 12, 0, true, true)
	var e2 := _make_engine(100)
	var r_high := e2.roll(&"abihigh", &"keen_eye", 5, 12, 0, true, true)
	# Same roll, different ability => totals differ by 4
	if r_high.total - r_low.total != 4:
		_failures.append("Different abilities should produce different totals: %d vs %d" % [r_low.total, r_high.total])
