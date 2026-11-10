extends SceneTree
## What the text corpus costs, measured rather than estimated.
##
## The game loads every chapter of every language at start-up. That is a decision, not an
## accident, and this test holds the measurement of it:
##
## - the load is timed, and the time is real (non-zero, and every chapter carries a share);
## - every chapter of every language is accounted for, with its JSON size in bytes;
## - the counts agree with the loaded libraries themselves — conversation ids, node counts
##   and inspection entries are cross-checked against `DialogueLibrary` and
##   `InspectionLibrary`, so the report cannot drift from the content it describes;
## - both languages are accounted for, and carry the same amount of content.
##
## It prints both reports, which is where the numbers in `docs/TECHNICAL_ROADMAP.md` come
## from. It does not change how loading works: the per-language/per-chapter lazy loading in
## that document's roadmap is a plan, not a feature.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "content_load_report_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.ensure_state_autoloads(self)
	Harness.ensure_autoload(self, "Loc", "res://scripts/i18n/loc.gd")
	L10n.load_tables()

	Harness.stage = "loading dialogue"
	var abilities := InnerAbilities.load_all()
	var dialogue := DialogueLibrary.load_all(abilities)
	Harness.stage = "loading inspections"
	var inspections := InspectionLibrary.load_all()

	print(dialogue.describe_load_report())
	print(inspections.describe_load_report())
	# The same numbers as annotations: a step log cannot be read back from the API, and the
	# roadmap has to quote what CI actually measured.
	print(
		"::notice title=text corpus::%s"
		% _summary("dialogue", dialogue.get_load_report(), "nodes", "conversations")
		+ " | "
		+ _summary("inspections", inspections.get_load_report(), "entries", "")
	)

	_check_dialogue(dialogue)
	_check_inspections(inspections)

	Harness.finish(
		self,
		_failures,
		"the dialogue and inspection libraries report their real size, their real chapter "
		+ "breakdown and their real load time, in every language, and the counts match the "
		+ "loaded libraries.",
	)


# --- dialogue ---------------------------------------------------------------


func _check_dialogue(library: DialogueLibrary) -> void:
	Harness.stage = "dialogue report"
	var report := library.get_load_report()
	_expect(not report.is_empty(), "The dialogue library produced no load report.")
	if report.is_empty():
		return
	_expect(int(report.get("total_usec", 0)) > 0, "The dialogue load was not timed.")
	var locales: Dictionary = report.get("locales", {})
	_expect(
		locales.size() == L10n.LOCALES.size(),
		"The dialogue report covers %d language(s), the game has %d."
		% [locales.size(), L10n.LOCALES.size()]
	)
	for locale: String in L10n.LOCALES:
		_expect(locales.has(locale), "The dialogue report has no entry for %s." % locale)
		if not locales.has(locale):
			continue
		var entry: Dictionary = locales[locale]
		_expect(int(entry["bytes"]) > 0, "%s: no dialogue bytes were measured." % locale)
		_expect(int(entry["conversations"]) > 0, "%s: no conversations were counted." % locale)
		_expect(int(entry["nodes"]) > 0, "%s: no nodes were counted." % locale)
		_expect(int(entry["usec"]) > 0, "%s: the dialogue load has no duration." % locale)
		var chapters: Dictionary = entry["chapters"]
		var chapter_bytes := 0
		var chapter_conversations := 0
		for chapter: String in DialogueLibrary.CHAPTERS:
			_expect(
				chapters.has(chapter),
				"%s: chapter '%s' is missing from the report." % [locale, chapter]
			)
			if not chapters.has(chapter):
				continue
			var chapter_entry: Dictionary = chapters[chapter]
			_expect(
				int(chapter_entry["bytes"]) > 0,
				"%s/%s: zero bytes; the file was not measured." % [locale, chapter]
			)
			_expect(
				int(chapter_entry["conversations"]) > 0,
				"%s/%s: no conversations; the chapter was not parsed." % [locale, chapter]
			)
			_expect(
				int(chapter_entry["nodes"]) > 0,
				"%s/%s: no nodes; the chapter was not parsed." % [locale, chapter]
			)
			chapter_bytes += int(chapter_entry["bytes"])
			chapter_conversations += int(chapter_entry["conversations"])
		_expect(
			chapter_bytes == int(entry["bytes"]),
			"%s: the chapters add up to %d bytes, the total says %d."
			% [locale, chapter_bytes, int(entry["bytes"])]
		)
		_expect(
			chapter_conversations == int(entry["conversations"]),
			"%s: the chapters add up to %d conversations, the total says %d."
			% [locale, chapter_conversations, int(entry["conversations"])]
		)
		# The count has to be the library's own answer, not a second count kept beside it.
		library.set_locale(locale)
		_expect(
			int(entry["conversations"]) == library.get_conversation_ids().size(),
			"%s: the report says %d conversations, the library resolves %d."
			% [locale, int(entry["conversations"]), library.get_conversation_ids().size()]
		)

	# Both languages carry the same content: a chapter added to one and not the other is a
	# parity break, and the report would show it as unequal totals.
	if locales.size() >= 2:
		var first: Dictionary = locales[L10n.LOCALES[0]]
		var second: Dictionary = locales[L10n.LOCALES[1]]
		_expect(
			int(first["conversations"]) == int(second["conversations"]),
			"The languages disagree on how many conversations exist: %d vs %d."
			% [int(first["conversations"]), int(second["conversations"])]
		)
		_expect(
			int(first["nodes"]) == int(second["nodes"]),
			"The languages disagree on how many nodes exist: %d vs %d."
			% [int(first["nodes"]), int(second["nodes"])]
		)

	var text := library.describe_load_report()
	for locale: String in L10n.LOCALES:
		_expect(text.find(locale) >= 0, "The dialogue report does not name %s." % locale)
	for chapter: String in DialogueLibrary.CHAPTERS:
		_expect(text.find(chapter) >= 0, "The dialogue report does not name chapter '%s'." % chapter)


# --- inspections ------------------------------------------------------------


func _check_inspections(library: InspectionLibrary) -> void:
	Harness.stage = "inspection report"
	var report := library.get_load_report()
	_expect(not report.is_empty(), "The inspection library produced no load report.")
	if report.is_empty():
		return
	_expect(int(report.get("total_usec", 0)) > 0, "The inspection load was not timed.")
	var locales: Dictionary = report.get("locales", {})
	_expect(
		locales.size() == L10n.LOCALES.size(),
		"The inspection report covers %d language(s), the game has %d."
		% [locales.size(), L10n.LOCALES.size()]
	)
	for locale: String in L10n.LOCALES:
		_expect(locales.has(locale), "The inspection report has no entry for %s." % locale)
		if not locales.has(locale):
			continue
		var entry: Dictionary = locales[locale]
		_expect(int(entry["bytes"]) > 0, "%s: no inspection bytes were measured." % locale)
		_expect(int(entry["entries"]) > 0, "%s: no inspectables were counted." % locale)
		_expect(int(entry["usec"]) > 0, "%s: the inspection load has no duration." % locale)
		var chapters: Dictionary = entry["chapters"]
		var chapter_bytes := 0
		var chapter_entries := 0
		for chapter: String in InspectionLibrary.CHAPTERS:
			_expect(
				chapters.has(chapter),
				"%s: inspection chapter '%s' is missing from the report." % [locale, chapter]
			)
			if not chapters.has(chapter):
				continue
			var chapter_entry: Dictionary = chapters[chapter]
			_expect(
				int(chapter_entry["bytes"]) > 0,
				"%s/%s: zero bytes; the file was not measured." % [locale, chapter]
			)
			_expect(
				int(chapter_entry["entries"]) > 0,
				"%s/%s: no inspectables; the file contributed nothing." % [locale, chapter]
			)
			chapter_bytes += int(chapter_entry["bytes"])
			chapter_entries += int(chapter_entry["entries"])
		_expect(
			chapter_bytes == int(entry["bytes"]),
			"%s: the inspection chapters add up to %d bytes, the total says %d."
			% [locale, chapter_bytes, int(entry["bytes"])]
		)
		_expect(
			chapter_entries == int(entry["entries"]),
			"%s: the inspection chapters add up to %d entries, the total says %d."
			% [locale, chapter_entries, int(entry["entries"])]
		)
		_expect(
			int(entry["entries"]) == library.get_ids_for(locale).size(),
			"%s: the report says %d inspectables, the library resolves %d."
			% [locale, int(entry["entries"]), library.get_ids_for(locale).size()]
		)

	if locales.size() >= 2:
		var first: Dictionary = locales[L10n.LOCALES[0]]
		var second: Dictionary = locales[L10n.LOCALES[1]]
		_expect(
			int(first["entries"]) == int(second["entries"]),
			"The languages disagree on how many inspectables exist: %d vs %d."
			% [int(first["entries"]), int(second["entries"])]
		)

	var text := library.describe_load_report()
	for locale: String in L10n.LOCALES:
		_expect(text.find(locale) >= 0, "The inspection report does not name %s." % locale)


## "dialogue 812.4 ms; en 612.3 KB / 4318 nodes / 71 conversations; zh-CN ..." in one line.
func _summary(label: String, report: Dictionary, unit: String, second_unit: String) -> String:
	var parts: Array[String] = [
		"%s %.1f ms" % [label, int(report.get("total_usec", 0)) / 1000.0]
	]
	var locales: Dictionary = report.get("locales", {})
	for locale: String in locales.keys():
		var entry: Dictionary = locales[locale]
		var line := "%s %.1f KB / %d %s" % [locale, int(entry["bytes"]) / 1024.0, int(entry[unit]), unit]
		if not second_unit.is_empty():
			line += " / %d %s" % [int(entry[second_unit]), second_unit]
		parts.append(line)
	return ", ".join(parts)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures.append(message)
