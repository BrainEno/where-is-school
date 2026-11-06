extends SceneTree
## Unit tests for the narrative knowledge log.
##
## These are the properties the whole "imagination is not evidence" rule rests on:
## entries keep their source, ids are unique, repeat visits do not duplicate, and
## a snapshot round-trip preserves category.

const Harness = preload("res://tests/test_harness.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	var narrative: Node = autoloads["narrative_state"]
	if narrative == null:
		Harness.finish(self, ["NarrativeState could not be created."], "")
		return
	narrative.clear()

	if not narrative.record(&"seen_board", NarrativeEntry.Source.OBSERVED, &"protagonist", "Board read."):
		_failures.append("A first record call should succeed.")
	if narrative.record(&"seen_board", NarrativeEntry.Source.IMAGINED, &"protagonist", "Different text."):
		_failures.append("Recording the same entry id twice must be rejected.")
	if not narrative.has_entry(&"seen_board"):
		_failures.append("Recorded entry is missing.")
	if narrative.get_entry(&"seen_board").source != NarrativeEntry.Source.OBSERVED:
		_failures.append("A duplicate record must not change the original source.")
	if narrative.count_for_source(NarrativeEntry.Source.OBSERVED) != 1:
		_failures.append("Observed entry count is wrong.")
	if narrative.count_for_source(NarrativeEntry.Source.IMAGINED) != 0:
		_failures.append("Imagined entries appeared from a rejected record.")

	if not narrative.record(&"imagined_b", NarrativeEntry.Source.IMAGINED, &"b", "B says stand."):
		_failures.append("Recording an imagined entry should succeed.")
	if not narrative.record(&"claim_b", NarrativeEntry.Source.REPORTED, &"q", "Q says B is strict."):
		_failures.append("Recording a reported entry should succeed.")
	if not narrative.record(&"recall_desk", NarrativeEntry.Source.RECALLED, &"protagonist", "Groove."):
		_failures.append("Recording a recalled entry should succeed.")

	if narrative.count_for_source(NarrativeEntry.Source.OBSERVED) != 1:
		_failures.append("Sources are collapsing into one another.")
	if narrative.get_entries().size() != 4:
		_failures.append("Expected 4 entries, found %d." % narrative.get_entries().size())

	# Empty input must be refused, not silently stored.
	if narrative.record(&"", NarrativeEntry.Source.OBSERVED, &"protagonist", "No id."):
		_failures.append("An empty entry id must be rejected.")

	var snapshot: Dictionary = narrative.to_snapshot()
	narrative.clear()
	if narrative.get_entries().size() != 0:
		_failures.append("clear() did not empty the log.")
	narrative.restore_snapshot(snapshot)
	if narrative.count_for_source(NarrativeEntry.Source.IMAGINED) != 1:
		_failures.append("Snapshot round-trip lost the imagined entry.")
	if narrative.count_for_source(NarrativeEntry.Source.RECALLED) != 1:
		_failures.append("Snapshot round-trip lost the recalled entry.")

	Harness.finish(self, _failures, "narrative entries keep their source and survive snapshots.")
