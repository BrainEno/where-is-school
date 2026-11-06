extends TestCaseHelper
## The narrative ledger is the spine of the whole slice: it is what stops an
## imagined confrontation from becoming a remembered fact. These tests pin the
## behaviour that gameplay code depends on.


func _run() -> void:
	var game_state: Node = make_tree().root.get_node_or_null("GameState")
	var ledger: Node = make_tree().root.get_node_or_null("NarrativeLedger")
	check_not_null(game_state, "GameState autoload is present")
	check_not_null(ledger, "NarrativeLedger autoload is present")
	if game_state == null or ledger == null:
		return

	game_state.clear()
	ledger.clear()

	# --- kinds are stored, not inferred -------------------------------------
	var observed_added: bool = ledger.record(
		&"test.observed", NarrativeRecord.Kind.OBSERVED, "Saw the door open"
	)
	var heard_added: bool = ledger.record(
		&"test.heard", NarrativeRecord.Kind.HEARD, "Q said the exam went badly"
	)
	var recalled_added: bool = ledger.record(
		&"test.recalled", NarrativeRecord.Kind.RECALLED, "A window, second row"
	)
	var imagined_added: bool = ledger.record(
		&"test.imagined", NarrativeRecord.Kind.IMAGINED, "Rehearsed a confrontation"
	)
	check_true(observed_added, "observed record was accepted")
	check_true(heard_added, "heard record was accepted")
	check_true(recalled_added, "recalled record was accepted")
	check_true(imagined_added, "imagined record was accepted")

	# --- only OBSERVED counts as a fact -------------------------------------
	check_true(ledger.has_observed(&"test.observed"), "observed record reads as observed")
	check_false(ledger.has_observed(&"test.heard"), "a statement is not an observation")
	check_false(ledger.has_observed(&"test.recalled"), "a recollection is not an observation")
	check_false(ledger.has_observed(&"test.imagined"), "an imagined event is not an observation")

	# --- de-duplication -----------------------------------------------------
	var duplicate: bool = ledger.record(
		&"test.observed", NarrativeRecord.Kind.OBSERVED, "Saw the door open again"
	)
	check_false(duplicate, "duplicate record ids are refused")
	check_eq(ledger.get_record(&"test.observed").title, "Saw the door open", "first write wins")

	# --- invalid data -------------------------------------------------------
	check_false(
		ledger.add(NarrativeRecord.create(&"", NarrativeRecord.Kind.OBSERVED, "no id")),
		"records with an empty id are refused"
	)

	# --- grouping -----------------------------------------------------------
	var counts: Dictionary = ledger.kind_counts()
	check_eq(int(counts.get(NarrativeRecord.Kind.OBSERVED, 0)), 1, "one observed record")
	check_eq(int(counts.get(NarrativeRecord.Kind.HEARD, 0)), 1, "one heard record")
	check_eq(int(counts.get(NarrativeRecord.Kind.RECALLED, 0)), 1, "one recalled record")
	check_eq(int(counts.get(NarrativeRecord.Kind.IMAGINED, 0)), 1, "one imagined record")

	var imagined_records: Array = ledger.records_of_kind(NarrativeRecord.Kind.IMAGINED)
	check_eq(imagined_records.size(), 1, "imagined records are filterable")
	check_contains_text(
		NarrativeRecord.kind_label(NarrativeRecord.Kind.IMAGINED),
		"did not happen",
		"the imagined label tells the player it did not happen"
	)

	# --- record shape -------------------------------------------------------
	var record: NarrativeRecord = ledger.get_record(&"test.heard")
	check_not_null(record, "record can be fetched by id")
	if record != null:
		var restored := NarrativeRecord.from_dict(record.to_dict())
		check_eq(restored.id, record.id, "round-trip preserves the id")
		check_eq(int(restored.kind), int(record.kind), "round-trip preserves the kind")
		check_eq(restored.title, record.title, "round-trip preserves the title")

	# --- clearing -----------------------------------------------------------
	ledger.clear()
	check_eq(ledger.ids().size(), 0, "clear empties the ledger")
	check_false(ledger.has(&"test.observed"), "clear removes records")
