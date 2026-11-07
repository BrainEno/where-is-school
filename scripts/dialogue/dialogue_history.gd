class_name DialogueHistory
extends RefCounted
## What the player has read, in the order it happened, identified by content ids.
##
## Issue #18 was a backlog that grew a duplicate row every time the language
## changed: the runtime re-emits the current line when its graph is rebuilt, and the
## controller appended whatever came back. The fix is not "remember not to append" —
## it is to give every entry a **stable identity** so the surface can tell "this is
## the same event, said again in another language" apart from "the player read
## something new".
##
## Identity never contains text. Text is the one thing a language switch is allowed
## to change, so comparing it can neither find the entry that needs re-rendering nor
## keep two events with equal text apart. The ids come from the content:
##
## - conversation line: `conv:<conversation_id>/<node_id>`
## - inspection line:   `inspection:<inspection_id>/<variant>`, where the variant is
##   `first`, `repeat` or `recall` — so a first read, a later repeat read and the
##   recollection stay three different things, in any language, in that order.
##
## Two events that happen to share an identity (walking back to a node that was
## already read) are still two entries: only `update_last()` ever replaces anything,
## and it does so only when the identity of the last entry matches. Nothing is ever
## merged by text.
##
## The history stores descriptors, not rendered rows: enough to rebuild the display
## in whatever language is current (`identity`, which content it came from, the
## source category) plus the text last rendered, used only if the content can no
## longer be resolved.

var _entries: Array[Dictionary] = []


## Appends the descriptor if it is a genuinely new event, and returns the stored copy.
## A descriptor whose identity matches the newest entry is treated as a republish of
## that entry and replaces it instead: that is the safe path for an emitter that
## repeats itself, and it is never decided by text.
func record(descriptor: Dictionary) -> Dictionary:
	var entry := _normalise(descriptor)
	if not _entries.is_empty() and identify(_entries[_entries.size() - 1]) == identify(entry):
		entry["seq"] = int(_entries[_entries.size() - 1].get("seq", 0))
		_entries[_entries.size() - 1] = entry
		return entry
	entry["seq"] = _entries.size()
	_entries.append(entry)
	return entry


## Replaces the newest entry when it is the same event, and reports whether it did.
## Returns false when the identity belongs to an older entry or to a different
## event, so the caller appends instead of overwriting the wrong row.
func update_last(descriptor: Dictionary) -> bool:
	if _entries.is_empty():
		return false
	var entry := _normalise(descriptor)
	if identify(_entries[_entries.size() - 1]) != identify(entry):
		return false
	entry["seq"] = int(_entries[_entries.size() - 1].get("seq", 0))
	_entries[_entries.size() - 1] = entry
	return true


func entries() -> Array[Dictionary]:
	return _entries.duplicate(true)


func size() -> int:
	return _entries.size()


func identities() -> PackedStringArray:
	var ids := PackedStringArray()
	for entry in _entries:
		ids.append(identify(entry))
	return ids


func clear() -> void:
	_entries.clear()


## The stable identity of a descriptor. Public and static so tests and the backlog can
## reason about the same value the history stores.
static func identify(descriptor: Dictionary) -> String:
	var explicit := String(descriptor.get("identity", ""))
	if not explicit.is_empty():
		return explicit
	var conversation_id := String(descriptor.get("conversation_id", ""))
	var node_id := String(descriptor.get("node_id", ""))
	if not conversation_id.is_empty() and not node_id.is_empty():
		return "conv:%s/%s" % [conversation_id, node_id]
	var inspection_id := String(descriptor.get("inspection_id", ""))
	var variant := String(descriptor.get("variant", ""))
	if not inspection_id.is_empty():
		if variant.is_empty():
			variant = "first"
		return "inspection:%s/%s" % [inspection_id, variant]
	# Nothing identified it: fall back to the speaker and the order of arrival rather
	# than to the text, so the entry is still unique and still re-renderable.
	return "unidentified:%s" % String(descriptor.get("speaker_id", ""))


func _normalise(descriptor: Dictionary) -> Dictionary:
	var entry := descriptor.duplicate(true)
	entry["identity"] = identify(entry)
	entry.erase("effects")
	entry.erase("record")
	entry.erase("set_flag")
	return entry
