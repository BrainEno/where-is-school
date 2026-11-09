extends RefCounted
## Editor-only: are the two language files still the same document?
##
## `DialogueParity` already compares what the *runtime* can see: node ids, order, branches,
## effects and checks. This comparison exists because a save has to answer the same
## question one level lower, on the JSON itself, before it writes anything: two files that
## a text edit has pulled apart must not be written at all, and the message has to name the
## address of the first difference rather than the file.
##
## Files are compared value by value, in order for arrays — order is what `once` keys and
## the "fall through to the next node" rule depend on — and by key for objects. Anything
## the tool is allowed to differ between languages is skipped by the caller's `ignore`
## callable, which receives the address of each value as a `PackedStringArray`.
##
## The reference is the first language in `L10n.LOCALES`, matching `DialogueParity`.

const MAX_REPORTED := 12


static func compare(
	reference: Variant,
	translated: Variant,
	reference_label: String,
	translated_label: String,
	ignore: Callable
) -> Array[String]:
	var problems: Array[String] = []
	_walk(
		reference,
		translated,
		PackedStringArray(),
		reference_label,
		translated_label,
		ignore,
		problems
	)
	return problems


static func pointer_of(address: PackedStringArray) -> String:
	return "/".join(address)


static func _is_ignored(ignore: Callable, address: PackedStringArray) -> bool:
	if not ignore.is_valid():
		return false
	return bool(ignore.call(address))


static func _walk(
	reference: Variant,
	translated: Variant,
	address: PackedStringArray,
	reference_label: String,
	translated_label: String,
	ignore: Callable,
	problems: Array[String]
) -> void:
	if problems.size() >= MAX_REPORTED:
		return
	if _is_ignored(ignore, address):
		return
	if reference is Dictionary and translated is Dictionary:
		var left: Dictionary = reference
		var right: Dictionary = translated
		for key: Variant in left.keys():
			var child := _append(address, String(key))
			if not right.has(key):
				if not _is_ignored(ignore, child):
					problems.append(
						"%s：%s 里有，%s 里没有。"
						% [pointer_of(child), reference_label, translated_label]
					)
				continue
			_walk(
				left[key],
				right[key],
				child,
				reference_label,
				translated_label,
				ignore,
				problems
			)
		for key: Variant in right.keys():
			if left.has(key):
				continue
			var child := _append(address, String(key))
			if not _is_ignored(ignore, child):
				problems.append(
					"%s：%s 里有，%s 里没有。"
					% [pointer_of(child), translated_label, reference_label]
				)
		return
	if reference is Array and translated is Array:
		var reference_items: Array = reference
		var translated_items: Array = translated
		if reference_items.size() != translated_items.size():
			problems.append(
				"%s：元素数量不同，%s 有 %d 个，%s 有 %d 个。"
				% [
					pointer_of(address),
					reference_label,
					reference_items.size(),
					translated_label,
					translated_items.size(),
				]
			)
			return
		for index in reference_items.size():
			_walk(
				reference_items[index],
				translated_items[index],
				_append(address, str(index)),
				reference_label,
				translated_label,
				ignore,
				problems
			)
		return
	if _same_value(reference, translated):
		return
	problems.append(
		"%s：两边不一致，%s 是 %s，%s 是 %s。"
		% [pointer_of(address), reference_label, _show(reference), translated_label, _show(translated)]
	)


static func _same_value(reference: Variant, translated: Variant) -> bool:
	if reference is String or translated is String:
		return reference is String and translated is String and String(reference) == String(translated)
	if reference is bool or translated is bool:
		return reference is bool and translated is bool and bool(reference) == bool(translated)
	if reference is int or reference is float:
		if not (translated is int or translated is float):
			return false
		return is_equal_approx(float(reference), float(translated))
	if reference == null or translated == null:
		return reference == null and translated == null
	return false


static func _append(address: PackedStringArray, part: String) -> PackedStringArray:
	var next := address.duplicate()
	next.append(part)
	return next


static func _show(value: Variant) -> String:
	if value is String:
		return "\"%s\"" % String(value)
	if value == null:
		return "null"
	return str(value)
