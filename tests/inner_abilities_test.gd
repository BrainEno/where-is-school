extends SceneTree
## Deterministic mechanics tests: no screen or real-time randomness required.
const Harness = preload("res://tests/test_harness.gd")
const StateScript = preload("res://scripts/autoload/game_state.gd")
const NarrativeScript = preload("res://scripts/autoload/narrative_state.gd")

class FixedRng extends RefCounted:
	var values: Array[int] = []
	var calls := 0
	func _init(sequence: Array[int]) -> void:
		values = sequence
	func randi_range(_minimum: int, _maximum: int) -> int:
		var value := values[calls % values.size()]
		calls += 1
		return value

var _failures: Array[String] = []


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "inner_abilities_test.gd")
	call_deferred("_run")


func _run() -> void:
	_check_ratings_and_dice()
	_check_seed_reproducibility()
	_check_passive_gating()
	_check_active_dialogue()
	L10n.set_locale("en")
	Harness.finish(self, _failures, "inner ability checks, passive pacing and active dialogue are deterministic.")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_ratings_and_dice() -> void:
	var state: Node = StateScript.new()
	var rng := FixedRng.new([4, 3, 1, 6])
	var checks := InnerCheckEngine.new(state, rng)
	_expect(InnerAbilities.get_rating(state, &"pattern") == 2, "Default pattern rating changed.")
	_expect(not InnerAbilities.set_rating(state, &"pattern", 5), "Out-of-range rating accepted.")
	var boundary := checks.attempt(&"boundary", &"pattern", 6, "active")
	_expect(int(boundary.get("roll", -1)) == 4 and int(boundary.get("total", -1)) == 6 \
		and bool(boundary.get("success", false)), "Equality at target must succeed.")
	var failure := checks.attempt(&"failure", &"pattern", 6, "active")
	_expect(int(failure.get("roll", -1)) == 3 and not bool(failure.get("success", true)), "Below target must fail.")
	_expect(InnerAbilities.set_rating(state, &"resonance", 0), "Minimum rating rejected.")
	var low := checks.attempt(&"minimum", &"resonance", 2, "passive")
	_expect(int(low.get("total", -1)) == 1 and not bool(low.get("success", true)), "Minimum die/rating failed.")
	_expect(InnerAbilities.set_rating(state, &"guard", 4), "Maximum rating rejected.")
	var high := checks.attempt(&"maximum", &"guard", 10, "active")
	_expect(int(high.get("total", -1)) == 10 and bool(high.get("success", false)), "Maximum die/rating failed.")
	var before := rng.calls
	InnerAbilities.set_rating(state, &"pattern", 4)
	var replay := checks.attempt(&"boundary", &"pattern", 6, "active")
	_expect(rng.calls == before and bool(replay.get("reused", false)), "Repeated check rolled again.")
	_expect(int(replay.get("rating", -1)) == 2 and int(replay.get("roll", -1)) == 4, "Repeated check changed its original result.")
	state.free()


func _check_seed_reproducibility() -> void:
	var first: Node = StateScript.new()
	var second: Node = StateScript.new()
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 419827
	b.seed = 419827
	var ca := InnerCheckEngine.new(first, a)
	var cb := InnerCheckEngine.new(second, b)
	for i in 12:
		var id := StringName("seed_%d" % i)
		var left := ca.attempt(id, &"pattern", 6, "active")
		var right := cb.attempt(id, &"pattern", 6, "active")
		_expect(left == right, "Equal seeds diverged at check %d." % i)
	first.free()
	second.free()


func _check_passive_gating() -> void:
	var state: Node = StateScript.new()
	var rng := FixedRng.new([6, 1])
	var checks := InnerCheckEngine.new(state, rng)
	var voices := PassiveVoices.new(state, checks)
	_expect(String(voices.after_interaction(&"pg_track")).is_empty() and rng.calls == 0, "Unobserved track triggered a voice.")
	state.set_flag(&"seen:pg_track", true)
	var first := voices.after_interaction(&"pg_track")
	_expect(first == &"inner_track_success" and rng.calls == 1, "Eligible track reaction did not use hidden check.")
	state.set_flag(&"seen:pg_hoop", true)
	_expect(String(voices.after_interaction(&"pg_hoop")).is_empty() and rng.calls == 1, "Cooldown did not suppress a second reaction.")
	voices.after_interaction(&"pg_bench")
	var second := voices.after_interaction(&"pg_hoop")
	_expect(second == &"inner_hoop_failure" and rng.calls == 2, "Eligible failure reaction was missing.")
	voices.after_interaction(&"pg_notice")
	voices.after_interaction(&"pg_notice")
	_expect(String(voices.after_interaction(&"pg_track")).is_empty() and rng.calls == 2, "A passive check repeated.")
	var passive_result: Dictionary = state.get_flag(InnerCheckEngine.flag_for(&"passive_hoop"), {})
	_expect(String(passive_result.get("visibility", "")) == "passive", "Passive result is not marked private.")
	state.free()


func _check_active_dialogue() -> void:
	L10n.set_locale("en")
	var library := DialogueLibrary.load_all()
	if not library.is_valid():
		_failures.append(library.describe_errors())
		return
	var state: Node = StateScript.new()
	var narrative: Node = NarrativeScript.new()
	var rng := FixedRng.new([4])
	var runtime := DialogueRuntime.new(state, narrative, null, rng)
	var graph := library.get_graph(&"playground_bench")
	_expect(runtime.start(graph, &"playground_bench"), "Could not start active bench dialogue.")
	var choices := runtime.get_current_choices()
	_expect(choices.size() == 3 and String(choices[0].get("text", "")).contains("target 6"), "Active choice hides its target.")
	_expect(runtime.choose(0), "Active check choice failed.")
	var line := runtime.get_current_line()
	_expect(String(line.get("node_id", "")) == "bench_p_yes", "Boundary success selected the wrong narrative branch.")
	var title := String(line.get("title", ""))
	_expect(title.contains("Thread") and title.contains("die 4") and title.contains("target 6") \
		and title.contains("success"), "Active check summary omits the ability, die, target or result: %s" % title)
	_expect(narrative.has_entry(&"thought_bench_p_yes") and \
		int(narrative.get_entry(&"thought_bench_p_yes").source) == NarrativeEntry.Source.IMAGINED,
		"Inner thought was not recorded as imagined.")
	L10n.set_locale("zh-CN")
	library.set_locale("zh-CN")
	_expect(runtime.rebind_graph(library.get_graph(&"playground_bench")), "Mid-result locale rebind failed.")
	_expect(String(runtime.get_current_line().get("title", "")).contains("骰子 4") and rng.calls == 1,
		"Locale switch re-rolled or failed to translate active result.")
	runtime.advance()
	_expect(runtime.start(library.get_graph(&"playground_bench"), &"playground_bench"), "Bench could not be revisited.")
	_expect(runtime.get_current_choices().size() == 2, "Once-only ability choice returned on revisit.")
	runtime.choose(1) # Leave, the remaining unchecked option.
	runtime.advance()
	_expect(rng.calls == 1, "Revisit caused a new roll.")
	state.free()
	narrative.free()

	# Failure has its own usable line and is still an imagined entry, not a gate.
	L10n.set_locale("en")
	library.set_locale("en")
	var fail_state: Node = StateScript.new()
	var fail_narrative: Node = NarrativeScript.new()
	var failing_rng := FixedRng.new([1])
	var failing := DialogueRuntime.new(fail_state, fail_narrative, null, failing_rng)
	failing.start(library.get_graph(&"playground_bench"), &"playground_bench")
	failing.choose(0)
	_expect(String(failing.get_current_node_id()) == "bench_p_no", "Failure did not select its distinct branch.")
	_expect(fail_narrative.has_entry(&"thought_bench_p_no"), "Failure branch recorded no useful thought.")
	_expect(String(failing.get_current_line().get("title", "")).contains("setback"), "Failure is not visible on active result.")
	failing.advance()
	_expect(not failing.is_active(), "Failed active check blocked the player.")
	failing.start(library.get_graph(&"inner_track_failure"), &"inner_track_failure")
	_expect(String(failing.get_current_line().get("title", "")).is_empty(), "Passive reaction exposed a die result.")
	failing.advance()
	fail_state.free()
	fail_narrative.free()
