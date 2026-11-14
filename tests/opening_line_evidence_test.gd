extends SceneTree
## #186: the committed pictures of the opening line say what the game says.
##
## `docs/screenshots/` once kept a frame of the opening reading "Oh - you're up..." days
## after the line had been rewritten, because nothing tied a committed frame to the content
## it showed. `tools/screenshot_evidence.py` compares the manifest with the JSON; this check
## compares both with the **running game**, headless:
##
## 1. **The comparator can fail.** `EvidenceContract.compare_panel()` is asked about the
##    wrong node and the wrong language and must object, and `authored_node()` must refuse a
##    conversation and a node that do not exist - a comparison that cannot say no proves
##    nothing.
## 2. **The first line on screen is the authored start of the opening.** The real
##    `main.tscn` boots from a clean session; the first line shown belongs to `q_wake`, is
##    its `start` node in `data/dialogue/en/prologue.json`, and the panel draws exactly that
##    sentence once the reveal ends.
## 3. **Both languages.** Switching to Chinese re-renders the same node, and the panel
##    draws the `zh-CN` sentence; switching back restores the English one.
## 4. **The committed evidence is of this line.** Every `current` frame in
##    `docs/screenshots/MANIFEST.json` that shows the opening names the node the game just
##    showed and the sentence the game just drew in its language; there is such a frame in
##    each language. Rewrite the first line, or make the opening start elsewhere, and this
##    fails until the frames are captured again (the dialogue evidence relay in the Playthrough capture workflow) or
##    relabelled as history.
## 5. **Which band they show.** A current frame whose `ui_fingerprint` differs from the
##    panel's files today is reported as a note, not a failure: the words are still right.

const Harness = preload("res://tests/test_harness.gd")
const EvidenceContract = preload("res://tests/evidence_contract.gd")
const MAIN := "res://scenes/main/main.tscn"
const MANIFEST := "res://docs/screenshots/MANIFEST.json"
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const LOCALES: Array[String] = ["en", "zh-CN"]

var _failures: Array[String] = []
var _notes: Array[String] = []
var _main: Node = null
var _ui: GameUI = null
var _dialogue: DialogueController = null
var _panel: DialoguePanel = null
var _loc: Node = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 200.0, "opening_line_evidence_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	_loc = Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")
	if _loc == null:
		Harness.finish(self, ["The Loc autoload could not be created."], "")
		return
	_loc.call("set_locale", "en")

	_check_authored_reader()
	await _boot()
	if _panel != null:
		var shown := _check_first_line()
		if not shown.is_empty():
			_check_comparator_objects(shown)
			await _check_languages(shown)
			_check_manifest(shown)

	Engine.time_scale = 1.0
	_loc.call("set_locale", "en")
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		await _frames(3)
	Harness.clear_session_state(self)
	if not _notes.is_empty():
		print("::notice title=opening line evidence::%s" % " | ".join(_notes))
	Harness.finish(
		self, _failures,
		"The first line on screen is the authored opening in both languages, and the committed frames show it."
	)


# --- 1. The reader and the comparator can say no ---------------------------------------


func _check_authored_reader() -> void:
	var missing_conversation := EvidenceContract.authored_node("en", "prologue.json", "no_such_conversation")
	_expect(not bool(missing_conversation["ok"]), "authored_node accepted a conversation that does not exist.")
	var missing_node := EvidenceContract.authored_node(
		"en", "prologue.json", EvidenceContract.OPENING_CONVERSATION, "no_such_node"
	)
	_expect(not bool(missing_node["ok"]), "authored_node accepted a node that does not exist.")
	var missing_file := EvidenceContract.authored_node("en", "no_such_file.json", "q_wake")
	_expect(not bool(missing_file["ok"]), "authored_node accepted a file that does not exist.")
	for locale in LOCALES:
		var start := EvidenceContract.authored_node(
			locale, EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION
		)
		_expect(bool(start["ok"]), "%s: the opening has no readable start node (%s)." % [locale, start["error"]])
		_expect(
			not String(start.get("text", "")).is_empty(),
			"%s: the opening's start node has no text." % locale
		)


func _check_comparator_objects(shown: Dictionary) -> void:
	# A node of the same conversation that is not on screen.
	var other_node := _another_node_of_opening(String(shown["node"]))
	if other_node.is_empty():
		_failures.append("The opening has only one node with text; the comparator cannot be tested against another.")
	else:
		var problem := EvidenceContract.compare_panel(
			_panel, _dialogue, "en", EvidenceContract.OPENING_SOURCE,
			EvidenceContract.OPENING_CONVERSATION, other_node
		)
		_expect(
			not problem.is_empty(),
			"compare_panel found nothing wrong with node '%s', which is not on screen." % other_node
		)
	# The right node in the wrong language.
	var wrong_language := EvidenceContract.compare_panel(
		_panel, _dialogue, "zh-CN", EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION
	)
	_expect(not wrong_language.is_empty(), "compare_panel accepted Chinese while the game draws English.")


# --- 2. The first line -------------------------------------------------------------------


func _boot() -> void:
	var packed: PackedScene = load(MAIN)
	if packed == null:
		_failures.append("main.tscn could not be loaded.")
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _frames(6)
	_ui = _main.get_node_or_null("GameUI") as GameUI
	_dialogue = _main.get_node_or_null("DialogueController") as DialogueController
	if _ui == null or _dialogue == null or _ui.dialogue_panel == null:
		_failures.append("Main did not expose GameUI, its dialogue panel and DialogueController.")
		return
	_panel = _ui.dialogue_panel
	Engine.time_scale = 4.0
	# Real time, not frames: a headless run draws frames as fast as it can, so a frame
	# count would be a different budget on every machine.
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 90000:
		if _dialogue.is_busy() and not String(_dialogue.get_current_line().get("text", "")).is_empty():
			break
		await process_frame
	if not _dialogue.is_busy():
		_failures.append("The opening conversation never showed a line.")
		_panel = null
		return
	await _wait_for_reveal()


## The node on screen, checked against the authored start of the opening in English.
## Returns `{conversation, node, text}`, or an empty dictionary after recording a failure.
func _check_first_line() -> Dictionary:
	var line := _dialogue.get_current_line()
	var conversation := String(line.get("conversation_id", ""))
	var node := String(line.get("node_id", ""))
	var authored := EvidenceContract.authored_node(
		"en", EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION
	)
	if conversation != EvidenceContract.OPENING_CONVERSATION:
		_failures.append(
			"The first conversation on screen is '%s', not the opening '%s'."
			% [conversation, EvidenceContract.OPENING_CONVERSATION]
		)
		return {}
	if node != String(authored.get("node", "")):
		_failures.append(
			"The first line on screen is node '%s'; the opening starts at '%s'." % [node, authored.get("node", "")]
		)
		return {}
	var problem := EvidenceContract.compare_panel(
		_panel, _dialogue, "en", EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION
	)
	if not problem.is_empty():
		_failures.append("English: %s." % problem)
		return {}
	_notes.append("first line: %s/%s \"%s\"" % [conversation, node, _panel.get_body_text()])
	return {"conversation": conversation, "node": node, "text": _panel.get_body_text()}


# --- 3. Both languages -------------------------------------------------------------------


func _check_languages(shown: Dictionary) -> void:
	_loc.call("set_locale", "zh-CN")
	await _frames(4)
	await _wait_for_reveal()
	var chinese := EvidenceContract.compare_panel(
		_panel, _dialogue, "zh-CN", EvidenceContract.OPENING_SOURCE,
		EvidenceContract.OPENING_CONVERSATION, String(shown["node"])
	)
	_expect(chinese.is_empty(), "Chinese: %s." % chinese)
	if chinese.is_empty():
		_notes.append("zh-CN: \"%s\"" % _panel.get_body_text())
	_loc.call("set_locale", "en")
	await _frames(4)
	await _wait_for_reveal()
	var english := EvidenceContract.compare_panel(
		_panel, _dialogue, "en", EvidenceContract.OPENING_SOURCE,
		EvidenceContract.OPENING_CONVERSATION, String(shown["node"])
	)
	_expect(english.is_empty(), "Back to English: %s." % english)


# --- 4 and 5. The committed frames --------------------------------------------------------


func _check_manifest(shown: Dictionary) -> void:
	if not FileAccess.file_exists(MANIFEST):
		_failures.append("%s does not exist." % MANIFEST)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or not (parsed as Dictionary).get("frames") is Array:
		_failures.append("%s has no list of frames." % MANIFEST)
		return
	var fingerprint := EvidenceContract.ui_fingerprint()
	var covered: Dictionary = {}
	for entry: Variant in (parsed as Dictionary)["frames"]:
		if not entry is Dictionary:
			continue
		var frame: Dictionary = entry
		var shows: Variant = frame.get("shows", null)
		if String(frame.get("status", "")) != "current" or not shows is Dictionary:
			continue
		var binding: Dictionary = shows
		if String(binding.get("conversation", "")) != EvidenceContract.OPENING_CONVERSATION:
			continue
		var file := String(frame.get("file", "?"))
		var locale := String(binding.get("locale", ""))
		if String(binding.get("node", "")) != String(shown["node"]):
			_failures.append(
				"%s claims to show node '%s'; the game opens on '%s'."
				% [file, binding.get("node", ""), shown["node"]]
			)
			continue
		var authored := EvidenceContract.authored_node(
			locale, EvidenceContract.OPENING_SOURCE, EvidenceContract.OPENING_CONVERSATION,
			String(shown["node"])
		)
		if not bool(authored["ok"]):
			_failures.append("%s: %s." % [file, authored["error"]])
			continue
		if String(binding.get("text", "")) != String(authored["text"]):
			_failures.append(
				"%s is stale: it shows \"%s\" but the game now says \"%s\" in %s. Capture it again "
				% [file, binding.get("text", ""), authored["text"], locale]
				+ "with the dialogue evidence relay (Playthrough capture, relay_dialogue_evidence), or mark it historical."
			)
			continue
		covered[locale] = true
		if String(frame.get("ui_fingerprint", "")) != fingerprint:
			_notes.append(
				"%s was taken with reading band %s; the band is %s now"
				% [file, frame.get("ui_fingerprint", ""), fingerprint]
			)
	for locale in LOCALES:
		_expect(
			covered.has(locale),
			"No current frame in %s shows the opening line in %s." % [MANIFEST, locale]
		)


# --- helpers ---------------------------------------------------------------------------


func _another_node_of_opening(except_node: String) -> String:
	var path := "res://data/dialogue/en/%s" % EvidenceContract.OPENING_SOURCE
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return ""
	var graph: Variant = ((parsed as Dictionary).get("conversations", {}) as Dictionary).get(
		EvidenceContract.OPENING_CONVERSATION, {}
	)
	if not graph is Dictionary:
		return ""
	for entry: Variant in (graph as Dictionary).get("nodes", []):
		if entry is Dictionary:
			var id := String((entry as Dictionary).get("id", ""))
			if id != except_node and not String((entry as Dictionary).get("text", "")).is_empty():
				return id
	return ""


func _wait_for_reveal() -> void:
	var started := Time.get_ticks_msec()
	while _panel != null and _panel.is_revealing() and Time.get_ticks_msec() - started < 15000:
		await process_frame


func _frames(count: int) -> void:
	for index in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
