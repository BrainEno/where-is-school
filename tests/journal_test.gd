extends SceneTree
## The notebook: what the protagonist knows, read back from `NarrativeState`.
##
##     godot --headless --path . --script res://tests/journal_test.gd
##
## A. **The catalog against the shipped content.** Every `record` and inspection `recall`
##    in `data/dialogue` and `data/inspections` - found here by reading the JSON directly,
##    not through the code under test - is in the catalog, in both languages, with one
##    source per id, words in each language and a place heading that exists. An id the
##    content does not know falls back to the words the log stored.
## B. **The page, without controls.** Sections in the order their first entry was learned,
##    rows in log order, counts per kind, the filter, "new", and who an entry came from.
## C. **The panel inside the real pause menu.** The notebook key opens it during play and
##    pauses the world; Esc goes straight back to the game. From the menu entry, Esc goes
##    back to the menu. The entry counts what is new; reading clears it; a restored log is
##    not news; a language switch re-words every row and changes no identity; the kinds
##    can be picked from the keyboard; it never writes to the log.
## D. **The HUD's "noted" line.** A new entry shows its kind and the notebook key; a
##    restore shows nothing.
## E. **The route line.** The places reached, from the flags the story already keeps, in
##    the story's order, never a place not reached, with where the player stands now.

const Harness = preload("res://tests/test_harness.gd")
const SETTINGS_SCRIPT := "res://scripts/autoload/settings_manager.gd"
const LOC_SCRIPT := "res://scripts/i18n/loc.gd"
const PAUSE_MENU_SCENE := "res://scenes/ui/pause_menu.tscn"
const GAME_UI_SCENE := "res://scenes/ui/game_ui.tscn"
const WINDOW_SIZE := Vector2i(1600, 900)

var _failures: Array[String] = []
var _narrative: Node = null
var _loc: Node = null
var _catalog: JournalCatalog = null


## Just enough of `GameState` for `JournalRoute`.
class Flags extends RefCounted:
	var data: Dictionary = {}

	func get_flag(flag: StringName, default_value: Variant = null) -> Variant:
		return data.get(flag, default_value)


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "journal_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	Harness.clear_session_state(self)
	_narrative = autoloads["narrative_state"]
	_loc = Harness.ensure_autoload(self, "Loc", LOC_SCRIPT)
	var settings := Harness.ensure_autoload(self, "Settings", SETTINGS_SCRIPT)
	if settings != null:
		settings.call("reset_to_defaults")
	L10n.load_tables()
	_set_locale("zh-CN")
	# A headless run without `--resolution` gets a 64 px window: the row of kinds would
	# wrap into a column and the HUD line could not fit. Lay out at a real size.
	root.min_size = Vector2i.ZERO
	root.size = WINDOW_SIZE
	await _frames(2)
	if _narrative == null:
		Harness.finish(self, ["NarrativeState could not be created."], "")
		return

	_check_catalog()
	_check_page()
	_check_route()
	if _catalog != null:
		await _check_panel()
		await _check_hud()

	_narrative.clear()
	_set_locale("en")
	await _frames(1)
	Harness.finish(
		self,
		_failures,
		"the notebook indexes every recorded entry in both languages, files and filters "
		+ "the log in reading order, opens from the key and the menu, re-words itself on "
		+ "a language switch, tracks what is new without saving it, and the HUD notes "
		+ "new entries."
	)


# --- A. The catalog ---------------------------------------------------------------------


func _check_catalog() -> void:
	Harness.stage = "A. catalog"
	var abilities := InnerAbilities.load_all()
	var dialogue := DialogueLibrary.load_all(abilities)
	var inspections := InspectionLibrary.load_all()
	_expect(dialogue.is_valid(), "A: the dialogue content does not load: %s" % dialogue.describe_errors())
	_expect(inspections.is_valid(), "A: the inspections do not load: %s" % inspections.describe_errors())
	_catalog = JournalCatalog.build(dialogue, inspections)
	for problem: String in _catalog.problems():
		_failures.append("A: %s" % problem)

	for locale: String in L10n.LOCALES:
		var expected := _scan_content(locale)
		_expect(expected.size() >= 40,
			"A: only %d recorded entries were found in the %s content." % [expected.size(), locale])
		_expect(_catalog.size(locale) == expected.size(),
			"A: the catalog has %d entries in %s; the content records %d."
			% [_catalog.size(locale), locale, expected.size()])
		for entry_id: Variant in expected.keys():
			var found := _catalog.lookup(StringName(entry_id), locale)
			if found.is_empty():
				_failures.append("A: %s records '%s' but the catalog does not know it." % [locale, entry_id])
				continue
			var source := int(expected[entry_id])
			_expect(int(found["source"]) == source,
				"A: '%s' is %s in the %s content but %s in the catalog." % [
					entry_id, NarrativeEntry.source_to_id(source), locale,
					NarrativeEntry.source_to_id(int(found["source"])),
				])
			_expect(not String(found["text"]).strip_edges().is_empty(),
				"A: '%s' has no words in %s." % [entry_id, locale])
			var place_key := _catalog.place_key_for(StringName(entry_id))
			_expect(L10n.has_key(place_key, locale),
				"A: '%s' is filed under '%s', which %s does not have." % [entry_id, place_key, locale])

	# The same entry, two languages, two different wordings.
	var zh := _catalog.lookup(&"saw_set_square", "zh-CN")
	var en := _catalog.lookup(&"saw_set_square", "en")
	_expect(not zh.is_empty() and not en.is_empty(), "A: saw_set_square is missing.")
	if not zh.is_empty() and not en.is_empty():
		_expect(String(zh["text"]) != String(en["text"]),
			"A: saw_set_square reads the same in both languages.")
		_expect(_catalog.place_key_for(&"saw_set_square") == "place.classroom",
			"A: the set square is not filed under the classroom.")
		_expect(String(zh["origin"]) == JournalCatalog.ORIGIN_INSPECTION,
			"A: the set square's entry does not come from its inspection.")
	# A recall is always a recollection, whatever the inspection itself is.
	var recall := _catalog.lookup(&"recall_set_square_placed", "zh-CN")
	_expect(not recall.is_empty() and int(recall["source"]) == NarrativeEntry.Source.RECALLED,
		"A: the set square's recall is not indexed as recalled.")
	# The prologue is the classroom; Q's account is reported, and his.
	var dialogue_reported := 0
	for entry_id: StringName in _catalog.get_entry_ids("zh-CN"):
		var found := _catalog.lookup(entry_id, "zh-CN")
		if String(found["origin"]) == JournalCatalog.ORIGIN_DIALOGUE \
				and int(found["source"]) == NarrativeEntry.Source.REPORTED:
			dialogue_reported += 1
			_expect(StringName(found["speaker_id"]) != &"protagonist",
				"A: reported entry '%s' is attributed to the protagonist." % entry_id)
	_expect(dialogue_reported >= 1, "A: no reported entry came from a conversation.")
	_expect(JournalCatalog.place_key_for_chapter("prologue") == "place.classroom",
		"A: the prologue is not filed under the classroom.")
	_expect(JournalCatalog.place_key_for_chapter("inner_voice") == JournalCatalog.ELSEWHERE_KEY,
		"A: inner-voice entries are not filed under 'elsewhere'.")
	_expect(JournalCatalog.place_key_for_chapter("no_such_place") == JournalCatalog.ELSEWHERE_KEY,
		"A: an unknown chapter did not fall back to 'elsewhere'.")

	# Words for what the content no longer knows: the stored ones.
	var orphan := NarrativeEntry.new(&"removed_line", NarrativeEntry.Source.OBSERVED, &"protagonist", "Kept words.")
	_expect(_catalog.text_for(orphan, "en") == "Kept words.",
		"A: an entry the content does not know lost its stored words.")
	_expect(_catalog.place_key_for(&"removed_line") == JournalCatalog.ELSEWHERE_KEY,
		"A: an entry the content does not know is not filed under 'elsewhere'.")
	_expect(not _catalog.has_entry(&"removed_line"), "A: the catalog invented an entry.")

	# Order follows the content: a classroom thing comes before a playground one.
	_expect(_catalog.order_of(&"saw_set_square") < _catalog.order_of(&"removed_line"),
		"A: an unknown entry does not sort last.")


## entry_id -> source, straight from the JSON files of one language.
func _scan_content(locale: String) -> Dictionary:
	var found: Dictionary = {}
	for chapter: String in DialogueLibrary.CHAPTERS:
		_walk(_read_json(DialogueLibrary.chapter_path(locale, chapter)), found, false)
	for chapter: String in InspectionLibrary.CHAPTERS:
		var data: Variant = _read_json(InspectionLibrary.chapter_path(locale, chapter))
		if not (data is Dictionary):
			continue
		var inspections: Variant = (data as Dictionary).get("inspections", data)
		if not (inspections is Dictionary):
			continue
		for key: Variant in (inspections as Dictionary).keys():
			var item: Variant = (inspections as Dictionary)[key]
			if not (item is Dictionary):
				continue
			var record: Variant = (item as Dictionary).get("record", null)
			if record is Dictionary:
				found[String((record as Dictionary)["entry_id"])] = NarrativeEntry.source_from_id(
					String((record as Dictionary).get("source", "observed"))
				)
			var recall: Variant = (item as Dictionary).get("recall", null)
			if recall is Dictionary:
				found[String((recall as Dictionary)["entry_id"])] = NarrativeEntry.Source.RECALLED
	return found


func _walk(node: Variant, found: Dictionary, _inside: bool) -> void:
	if node is Dictionary:
		var data: Dictionary = node
		if String(data.get("type", "")) == "record" and data.has("entry_id"):
			found[String(data["entry_id"])] = NarrativeEntry.source_from_id(String(data.get("source", "")))
		for value: Variant in data.values():
			_walk(value, found, true)
	elif node is Array:
		for value: Variant in node:
			_walk(value, found, true)


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


# --- B. The page ------------------------------------------------------------------------


func _check_page() -> void:
	Harness.stage = "B. page"
	var entries: Array[NarrativeEntry] = [
		NarrativeEntry.new(&"saw_set_square", NarrativeEntry.Source.OBSERVED, &"protagonist", "stored a"),
		NarrativeEntry.new(&"removed_line", NarrativeEntry.Source.IMAGINED, &"protagonist", "stored b"),
		NarrativeEntry.new(&"heard_from_q", NarrativeEntry.Source.REPORTED, &"q", "stored c"),
		NarrativeEntry.new(&"recall_set_square_placed", NarrativeEntry.Source.RECALLED, &"protagonist", "stored d"),
	]
	var read := {&"saw_set_square": true}
	var page := JournalPage.compose(entries, _catalog, "en", JournalPage.ALL, read, null)
	_expect(int(page["total"]) == 4 and int(page["shown"]) == 4,
		"B: the page shows %s of %s entries." % [page["shown"], page["total"]])
	_expect(int(page["unread"]) == 3, "B: %d unread, expected 3." % int(page["unread"]))
	var counts: Dictionary = page["counts"]
	for source: int in JournalPage.SOURCES:
		_expect(int(counts[source]) == 1, "B: %d entries counted as %s." % [
			int(counts[source]), NarrativeEntry.source_to_id(source)])
	_expect(JournalPage.row_ids(page) == [&"saw_set_square", &"recall_set_square_placed",
			&"removed_line", &"heard_from_q"],
		"B: rows are not grouped by place in learning order: %s." % str(JournalPage.row_ids(page)))
	var sections: Array = page["sections"]
	_expect(sections.size() == 2, "B: %d sections, expected classroom and elsewhere." % sections.size())
	if sections.size() == 2:
		_expect(String((sections[0] as Dictionary)["place_key"]) == "place.classroom",
			"B: the first section is not the classroom.")
		_expect(String((sections[1] as Dictionary)["place_key"]) == JournalCatalog.ELSEWHERE_KEY,
			"B: unknown entries are not filed under 'elsewhere'.")
	var rows := _rows_by_id(page)
	if _catalog != null:
		_expect(String(rows[&"saw_set_square"]["text"]) == String(_catalog.lookup(&"saw_set_square", "en")["text"]),
			"B: a known entry is not worded from the catalog.")
	_expect(String(rows[&"removed_line"]["text"]) == "stored b", "B: an unknown entry lost its words.")
	_expect(not bool(rows[&"saw_set_square"]["is_new"]), "B: a read entry is marked new.")
	_expect(bool(rows[&"heard_from_q"]["is_new"]), "B: an unread entry is not marked new.")
	_expect(String(rows[&"saw_set_square"]["attribution"]).is_empty(),
		"B: the protagonist's own observation is attributed.")
	var said := String(rows[&"heard_from_q"]["attribution"])
	_expect(said == L10n.t("journal.said_by", {"name": L10n.t("name.q")}),
		"B: Q's account is attributed as '%s'." % said)

	var reported := JournalPage.compose(entries, _catalog, "en", NarrativeEntry.Source.REPORTED, read)
	_expect(JournalPage.row_ids(reported) == [&"heard_from_q"],
		"B: the reported filter shows %s." % str(JournalPage.row_ids(reported)))
	_expect(int(reported["total"]) == 4 and int((reported["counts"] as Dictionary)[JournalPage.ALL]) == 4,
		"B: filtering changed the counts.")

	_expect(JournalPage.step_filter(JournalPage.ALL, 1) == NarrativeEntry.Source.OBSERVED,
		"B: the kind after All is not Seen.")
	_expect(JournalPage.step_filter(JournalPage.ALL, -1) == NarrativeEntry.Source.IMAGINED,
		"B: the kinds do not wrap backwards.")
	_expect(JournalPage.step_filter(NarrativeEntry.Source.IMAGINED, 1) == JournalPage.ALL,
		"B: the kinds do not wrap forwards.")
	for filter: int in [JournalPage.ALL, NarrativeEntry.Source.OBSERVED, NarrativeEntry.Source.REPORTED,
			NarrativeEntry.Source.RECALLED, NarrativeEntry.Source.IMAGINED]:
		for locale: String in L10n.LOCALES:
			_expect(L10n.has_key(JournalPage.caveat_key(filter), locale),
				"B: %s has no caveat for %s." % [locale, JournalPage.caveat_key(filter)])
			_expect(L10n.has_key(JournalPage.filter_label_key(filter), locale),
				"B: %s has no label for %s." % [locale, JournalPage.filter_label_key(filter)])
	var none: Array[NarrativeEntry] = []
	var empty := JournalPage.compose(none, _catalog, "en")
	_expect(int(empty["total"]) == 0 and (empty["sections"] as Array).is_empty(),
		"B: an empty log did not make an empty page.")


func _rows_by_id(page: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for section: Variant in page["sections"]:
		for row: Variant in (section as Dictionary)["rows"]:
			out[StringName((row as Dictionary)["entry_id"])] = row
	return out


# --- C. The panel in the pause menu -----------------------------------------------------


func _check_panel() -> void:
	Harness.stage = "C. panel"
	_narrative.clear()
	var observed := _ids_of(NarrativeEntry.Source.OBSERVED)
	var reported := _ids_of(NarrativeEntry.Source.REPORTED)
	if observed.size() < 6 or reported.is_empty():
		_failures.append("C: the content has too few entries to exercise the notebook.")
		return
	# Two things known before the notebook exists: a Continue, not news.
	_record(observed[0])
	_record(observed[1])
	var packed: PackedScene = load(PAUSE_MENU_SCENE)
	var menu := packed.instantiate() as PauseMenu
	root.add_child(menu)
	await _frames(2)
	var journal := menu.get_journal_panel()
	if journal == null:
		_failures.append("C: the pause menu has no notebook.")
		menu.queue_free()
		return
	journal.set_catalog(_catalog)
	_expect(journal.get_unread_count() == 0, "C: entries known before the notebook existed are new.")
	_expect(menu.get_entry(&"journal").text == L10n.t("menu.journal"),
		"C: the menu entry reads '%s' with nothing new." % menu.get_entry(&"journal").text)

	# Three new things, one of them somebody's account.
	var fresh: Array[StringName] = [observed[2], observed[3], reported[0]]
	for entry_id: StringName in fresh:
		_record(entry_id)
	_expect(journal.get_unread_count() == 3, "C: %d new entries, expected 3." % journal.get_unread_count())
	menu.open()
	await _frames(2)
	_expect(menu.get_entry(&"journal").text == L10n.t("menu.journal_unread", {"count": 3}),
		"C: the menu entry reads '%s' with three new." % menu.get_entry(&"journal").text)
	menu.close()
	await _frames(1)

	# Where the run stands, as the story records it.
	var game_state := root.get_node_or_null(^"GameState")
	_expect(game_state != null, "C: there is no GameState to read the route from.")
	if game_state != null:
		game_state.call("set_flag", StoryFlags.CURRENT_LOCATION, "corridor")
		game_state.call("set_flag", StoryFlags.LEFT_CLASSROOM, true)
		game_state.call("set_flag", StoryFlags.OBJECTIVE_KEY, "objective.leave_classroom")

	# The notebook key during play: the menu is only its frame.
	paused = false
	await _key(KEY_N)
	await _frames(2)
	_expect(menu.is_open() and journal.is_open(), "C: the notebook key did not open the notebook.")
	_expect(paused, "C: the world kept running behind the notebook.")
	_expect(journal.get_title_text() == L10n.t("journal.title"), "C: the notebook has no title.")
	var expected_ids: Array[StringName] = [observed[0], observed[1]]
	expected_ids.append_array(fresh)
	_expect(_same_members(journal.get_row_ids(), expected_ids),
		"C: rows %s, expected %s." % [str(journal.get_row_ids()), str(expected_ids)])
	var new_mark := L10n.t("journal.new")
	var marked := 0
	for header: String in journal.get_row_headers():
		if header.ends_with(new_mark):
			marked += 1
	_expect(marked == 3, "C: %d rows are marked new, expected 3." % marked)
	var zh_texts := {}
	for entry_id: StringName in journal.get_row_ids():
		zh_texts[entry_id] = String(_catalog.lookup(entry_id, "zh-CN")["text"])
	_expect(_same_members(journal.get_row_texts(), zh_texts.values()),
		"C: the rows are not worded from the zh-CN content.")
	_expect(journal.get_section_titles().size() >= 1, "C: the rows have no place headings.")
	_expect(not journal.get_hint_text().is_empty(), "C: the notebook has no key hint.")
	var route := journal.get_route_text()
	_expect(route.contains(L10n.t("place.classroom")) and route.contains(L10n.t("place.corridor")),
		"C: the route line '%s' does not name the classroom and the corridor." % route)
	_expect(route.contains(L10n.t("journal.route_here", {"place": L10n.t("place.corridor")})),
		"C: the route line '%s' does not say the player is in the corridor." % route)
	_expect(journal.get_objective_text() == L10n.t("journal.objective",
			{"objective": L10n.objective_text("objective.leave_classroom")}),
		"C: the objective line reads '%s'." % journal.get_objective_text())
	_expect(journal.get_filter_button(JournalPage.ALL).has_focus(), "C: All does not have the focus.")
	var log_before: Array = _narrative.call("to_snapshot")["entries"]

	# A language switch re-words everything and changes no identity.
	var ids_before := journal.get_row_ids()
	_set_locale("en")
	await _frames(3)
	_expect(journal.get_row_ids() == ids_before, "C: the language switch changed the rows' identities.")
	for entry_id: StringName in ids_before:
		var expected := String(_catalog.lookup(entry_id, "en")["text"])
		_expect(journal.get_row_texts().has(expected), "C: '%s' was not re-worded in English." % entry_id)
	_expect(journal.get_title_text() == L10n.t("journal.title"), "C: the title stayed in Chinese.")
	_set_locale("zh-CN")
	await _frames(2)

	# The kinds from the keyboard: Right, Enter picks Seen.
	if not journal.get_filter_button(JournalPage.ALL).has_focus():
		_failures.append("C: after the language switch the focus is on %s, not All." % [
			root.gui_get_focus_owner()])
		journal.focus_filter(JournalPage.ALL)
	await _key(KEY_RIGHT)
	_expect(journal.get_filter_button(NarrativeEntry.Source.OBSERVED).has_focus(),
		"C: Right went to %s, not Seen." % [root.gui_get_focus_owner()])
	await _key(KEY_ENTER)
	await _frames(1)
	_expect(journal.get_filter() == NarrativeEntry.Source.OBSERVED,
		"C: Right, Enter picked filter %d, not Seen." % journal.get_filter())
	for entry_id: StringName in journal.get_row_ids():
		_expect(int(_catalog.lookup(entry_id, "zh-CN")["source"]) == NarrativeEntry.Source.OBSERVED,
			"C: '%s' is under Seen but is not an observation." % entry_id)
	_expect(journal.get_caveat_text() == L10n.t("journal.caveat.observed"),
		"C: the caveat does not follow the filter.")
	journal.set_filter(NarrativeEntry.Source.IMAGINED)
	await _frames(1)
	if int(journal.get_page()["shown"]) == 0:
		_expect(journal.get_empty_text() == L10n.t("journal.empty_filter"),
			"C: an empty kind does not say so.")
	# Down scrolls the page instead of leaving the row of kinds.
	journal.set_filter(JournalPage.ALL)
	await _frames(2)
	var focus_before := root.gui_get_focus_owner()
	await _key(KEY_DOWN)
	_expect(root.gui_get_focus_owner() == focus_before, "C: Down moved the focus off the kinds.")

	# Esc goes straight back to the game.
	await _key(KEY_ESCAPE)
	await _frames(2)
	_expect(not journal.is_open() and not menu.is_open(), "C: Esc did not go back to the game.")
	_expect(not paused, "C: the world stayed paused after the notebook closed.")
	_expect(journal.get_unread_count() == 0, "C: reading the notebook did not clear what was new.")
	var log_after: Array = _narrative.call("to_snapshot")["entries"]
	_expect(log_after == log_before, "C: the notebook changed the knowledge log.")

	# From the menu entry, Esc goes back to the menu, on the notebook's entry.
	menu.open()
	await _frames(1)
	_expect(menu.get_entry(&"journal").text == L10n.t("menu.journal"),
		"C: the entry still counts entries that were read.")
	menu.activate(&"journal")
	await _frames(2)
	_expect(journal.is_open(), "C: the menu entry did not open the notebook.")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_expect(not journal.is_open() and menu.is_open(), "C: Esc did not close only the notebook.")
	_expect(root.gui_get_focus_owner() == menu.get_entry(&"journal"),
		"C: closing the notebook did not return the focus to its entry.")
	# The notebook key from the menu list opens it too.
	await _key(KEY_N)
	await _frames(2)
	_expect(journal.is_open(), "C: the notebook key did not open the notebook from the menu.")
	await _key(KEY_N)
	await _frames(2)
	_expect(not journal.is_open() and menu.is_open(), "C: the notebook key did not close it again.")
	menu.close()
	await _frames(1)

	# A restored log is the run picked up again; a cleared one is a new run.
	_record(observed[4])
	_expect(journal.get_unread_count() == 1, "C: a new entry after reading is not new.")
	var snapshot: Dictionary = _narrative.call("to_snapshot")
	_narrative.clear()
	await _frames(1)
	_narrative.call("restore_snapshot", snapshot)
	await _frames(1)
	_expect(journal.get_unread_count() == 0, "C: restored entries are new.")
	_narrative.clear()
	await _frames(1)
	menu.open_journal(true)
	await _frames(2)
	_expect(journal.get_row_ids().is_empty(), "C: a cleared log left rows in the notebook.")
	_expect(journal.get_empty_text() == L10n.t("journal.empty"), "C: an empty notebook does not say so.")
	# Something learned while the notebook is open appears in it.
	_record(observed[5])
	await _frames(2)
	_expect(journal.get_row_ids() == [observed[5]], "C: an entry recorded while open did not appear.")
	journal.close()
	await _frames(2)
	_expect(not menu.is_open(), "C: closing the notebook opened from play left the menu open.")
	menu.queue_free()
	await _frames(1)


# --- E. The route ------------------------------------------------------------------------


func _check_route() -> void:
	Harness.stage = "E. route"
	var locations := LocationCatalog.load_all()
	_expect(locations.is_valid(), "E: locations.json does not load: %s" % locations.describe_errors())
	var flags := Flags.new()
	var rows := JournalRoute.compose(locations, flags)
	_expect(_route_ids(rows) == [&"classroom"],
		"E: a run that has gone nowhere reached %s." % str(_route_ids(rows)))
	flags.data[StoryFlags.CURRENT_LOCATION] = "corridor"
	flags.data[StoryFlags.LEFT_CLASSROOM] = true
	flags.data[StoryFlags.STREET_ARRIVED] = true
	rows = JournalRoute.compose(locations, flags, {"place.residential": 2})
	_expect(_route_ids(rows) == [&"classroom", &"corridor", &"street", &"residential"],
		"E: the route is %s, not classroom, corridor, street, residential." % str(_route_ids(rows)))
	for row: Dictionary in rows:
		_expect(bool(row["current"]) == (row["location_id"] == &"corridor"),
			"E: '%s' is marked current wrongly." % row["location_id"])
	_expect(int(rows[3]["entries"]) == 2, "E: the residential count is %s." % rows[3]["entries"])
	_expect(not _route_ids(rows).has(&"playground") and not _route_ids(rows).has(&"alley"),
		"E: the route names a place the run has not reached.")
	flags.data[StoryFlags.CURRENT_LOCATION] = "laboratory"
	rows = JournalRoute.compose(locations, flags)
	_expect(not _route_ids(rows).has(&"laboratory"), "E: a place without a name is on the route.")
	# A false flag is a place not reached.
	var unset := Flags.new()
	unset.data[StoryFlags.STREET_ARRIVED] = false
	_expect(not _route_ids(JournalRoute.compose(locations, unset)).has(&"street"),
		"E: a false arrival flag put the street on the route.")

	flags.data[StoryFlags.CURRENT_LOCATION] = "corridor"
	rows = JournalRoute.compose(locations, flags, {"place.classroom": 4})
	var line := JournalRoute.describe(rows)
	_expect(line.contains(L10n.t("journal.route_count", {"place": L10n.t("place.classroom"), "count": 4})),
		"E: the route line '%s' does not count the classroom's entries." % line)
	_expect(line.contains(L10n.t("journal.route_here", {"place": L10n.t("place.corridor")})),
		"E: the route line '%s' does not mark where the player is." % line)
	var no_rows: Array[Dictionary] = []
	_expect(JournalRoute.describe(no_rows).is_empty(), "E: an empty route still printed a line.")
	_expect(JournalRoute.objective_text(flags).is_empty(), "E: an objective appeared from nowhere.")
	flags.data[StoryFlags.OBJECTIVE_KEY] = "objective.leave_classroom"
	_expect(JournalRoute.objective_text(flags) == L10n.objective_text("objective.leave_classroom"),
		"E: the objective line is '%s'." % JournalRoute.objective_text(flags))
	_expect(JournalRoute.compose(null, flags).is_empty(), "E: no catalog still made a route.")


func _route_ids(rows: Array[Dictionary]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for row: Dictionary in rows:
		ids.append(StringName(row["location_id"]))
	return ids


# --- D. The HUD ---------------------------------------------------------------------------


func _check_hud() -> void:
	Harness.stage = "D. hud"
	_narrative.clear()
	var packed: PackedScene = load(GAME_UI_SCENE)
	var ui := packed.instantiate() as GameUI
	root.add_child(ui)
	await _frames(2)
	var hud := ui.hud
	_expect(hud.get_noted_text().is_empty(), "D: the HUD notes something before anything was learned.")
	var ids := _catalog.get_entry_ids("zh-CN")
	_record(ids[0])
	await _frames(1)
	var source := int(_catalog.lookup(ids[0], "zh-CN")["source"])
	var text := hud.get_noted_text()
	_expect(text.contains(L10n.t(NarrativeEntry.badge_key_for(source))),
		"D: the noted line '%s' does not name the kind." % text)
	_expect(text.contains(InputHint.action_key(hud, &"journal")),
		"D: the noted line '%s' does not name the notebook key." % text)
	_set_locale("en")
	await _frames(1)
	_expect(hud.get_noted_text() == L10n.t("hud.noted", {
			"badge": L10n.t(NarrativeEntry.badge_key_for(source)),
			"key": InputHint.action_key(hud, &"journal"),
		}),
		"D: the noted line did not follow the language switch: '%s'." % hud.get_noted_text())
	_set_locale("zh-CN")
	var snapshot: Dictionary = _narrative.call("to_snapshot")
	_narrative.call("restore_snapshot", snapshot)
	await _frames(1)
	_expect(hud.get_noted_text().is_empty(), "D: a restore was noted as something new.")
	_record(ids[1])
	await _frames(1)
	_expect(not hud.get_noted_text().is_empty(), "D: the second entry was not noted.")
	var label := hud.get_noted_label()
	var view := root.get_visible_rect().size
	if label != null:
		var box := label.get_global_rect()
		_expect(box.position.x >= 0.0 and box.end.x <= view.x + 0.5,
			"D: the noted line runs off the screen (%s in %s)." % [str(box), str(view)])
	_narrative.clear()
	await _frames(1)
	_expect(hud.get_noted_text().is_empty(), "D: clearing the log left the noted line up.")
	ui.queue_free()
	await _frames(1)


# --- Helpers ----------------------------------------------------------------------------


func _ids_of(source: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry_id: StringName in _catalog.get_entry_ids("zh-CN"):
		if int(_catalog.lookup(entry_id, "zh-CN")["source"]) == source:
			out.append(entry_id)
	return out


func _record(entry_id: StringName) -> void:
	var found := _catalog.lookup(entry_id, L10n.current)
	_narrative.call(
		"record", entry_id, int(found["source"]), StringName(found["speaker_id"]),
		String(found["text"])
	)


func _set_locale(locale: String) -> void:
	if _loc != null:
		_loc.call("set_locale", locale)
	else:
		L10n.set_locale(locale)


func _same_members(a: Variant, b: Variant) -> bool:
	var left: Array = Array(a)
	var right: Array = Array(b)
	if left.size() != right.size():
		return false
	for item: Variant in left:
		if not right.has(item):
			return false
	return true


func _key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event)
		await process_frame


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
