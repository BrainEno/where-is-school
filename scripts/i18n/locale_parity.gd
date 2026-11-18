class_name LocaleParity
extends RefCounted
## Reusable key-set and entry parity comparison across languages.
##
## Compares localized key collections across locales to ensure bilingual consistency:
## - Keys present in reference locale but missing in translated locale
## - Keys present in translated locale but missing in reference locale
## - Verifying table entry parity between language datasets

## Finds missing and extra keys between reference and target arrays.
## Returns a Dictionary with "missing" (in reference but not in target) and
## "extra" (in target but not in reference).
static func find_key_differences(reference_keys: Array, target_keys: Array) -> Dictionary:
	var missing: Array = []
	var extra: Array = []
	for key: Variant in reference_keys:
		if not target_keys.has(key):
			missing.append(key)
	for key: Variant in target_keys:
		if not reference_keys.has(key):
			extra.append(key)
	return {
		"missing": missing,
		"extra": extra,
	}


## Checks entry ID parity between reference and target locales, appending problems.
static func check_id_parity(
	reference_locale: String,
	reference_ids: Array,
	_target_locale: String,
	target_ids: Array,
	noun: String = "entry",
	target_path: String = ""
) -> Array[String]:
	var diff := find_key_differences(reference_ids, target_ids)
	var problems: Array[String] = []
	var prefix := ("%s: " % target_path) if not target_path.is_empty() else ""
	for item: Variant in diff.missing:
		problems.append(
			"%s%s '%s' has no text (present in %s)."
			% [prefix, noun, item, reference_locale]
		)
	for item: Variant in diff.extra:
		problems.append(
			"%s%s '%s' does not exist in %s."
			% [prefix, noun, item, reference_locale]
		)
	return problems


## Checks catalog dictionary parity between reference and target tables (as in journal_catalog).
static func check_table_parity(
	reference_locale: String,
	reference_table: Dictionary,
	_target_locale: String,
	target_table: Dictionary
) -> Array[String]:
	var problems: Array[String] = []
	var diff := find_key_differences(reference_table.keys(), target_table.keys())
	for key: Variant in diff.missing:
		problems.append(
			"%s records '%s' but %s never does." % [reference_locale, key, target_locale]
		)
	for key: Variant in diff.extra:
		problems.append(
			"%s records '%s' but %s never does." % [target_locale, key, reference_locale]
		)
	return problems
