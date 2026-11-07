extends SceneTree
const Harness = preload("res://tests/test_harness.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	Harness.arm_watchdog(self, 90.0, "ability_checks_test")
	call_deferred("_run")

func _run() -> void:
	var state: Node = Harness.ensure_state_autoloads(self)["game_state"]
	state.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 401
	var reference := RandomNumberGenerator.new()
	reference.seed = 401
	var first_die := reference.randi_range(1, 12)
	var checks := AbilityChecks.new(state, rng)
	_check(checks.errors.is_empty(), "Abilities failed to load: %s" % checks.errors)
	for id: String in ["measure", "trace", "echo"]:
		_check(checks.level_of(id) > 0 and not checks.name_of(id, "zh-CN").is_empty(), "Missing ability %s" % id)
	var spec := {"ability": "measure", "difficulty": first_die + 2, "success": "yes", "failure": "no"}
	var boundary := checks.resolve(&"boundary", spec, true)
	_check(boundary.get("die") == first_die, "Seeded die is not reproducible.")
	_check(boundary.get("success") == true, "Equal-to-difficulty must succeed.")
	_check(boundary.get("total") == boundary.get("difficulty"), "Boundary total is incorrect.")
	_check(checks.visible_report(boundary, "en").contains("DC"), "Visible check lacks its DC and result.")
	_check(checks.visible_report(boundary, "zh-CN").contains("难度"), "Visible check is not translated.")
	var cached := checks.resolve(&"boundary", spec, true)
	_check(cached == boundary, "An interaction rerolled its cached check.")
	_check(checks.resolve(&"easy", {"ability":"trace", "difficulty":1, "success":"yes", "failure":"no"}, false).get("success") == true, "A guaranteed success failed.")
	var failed := checks.resolve(&"hard", {"ability":"echo", "difficulty":15, "success":"yes", "failure":"no"}, false)
	_check(failed.get("success") == false, "A guaranteed failure succeeded.")
	_check(checks.visible_report(failed, "en").is_empty(), "Hidden die leaked numbers.")
	_check(checks.passive_conversation(&"not_an_anchor") == &"", "An ineligible passive triggered.")
	var passive := checks.passive_conversation(&"yard_drain")
	_check(not String(passive).is_empty(), "Eligible passive failed to trigger.")
	_check(checks.passive_conversation(&"yard_drain") == &"", "Passive was presented twice.")
	_check(state.has_flag(&"check.yard_drain"), "Passive result was not saved.")
	state.clear()
	var same := RandomNumberGenerator.new()
	same.seed = 401
	var again := AbilityChecks.new(state, same).resolve(&"boundary", spec, true)
	_check(again == boundary, "The same seed and input changed the result.")
	_check(not checks.check_spec({"ability":"made_up", "difficulty":2,"success":"x","failure":"y"}), "Unknown ability accepted.")
	Harness.finish(self, _failures, "hybrid ability loading, seeded visible/hidden checks, boundaries and once-only reactions.")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
