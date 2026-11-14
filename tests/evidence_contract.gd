extends RefCounted
## Ties a captured dialogue frame to the sentence it is supposed to show (#186).
##
## The repository once kept a frame of the opening that read "Oh - you're up..." for days
## after the authored line had become "Enjoy your nap, did you?": nothing compared what a
## capture photographed with what the content says, so a frame could be wrong without
## anything failing. This helper is that comparison, shared by the capture scripts and the
## headless check:
##
## - `authored_node()` reads the sentence straight from `data/dialogue/<locale>/<file>`,
##   not through `DialogueLibrary`, so a fault in the runtime cannot make the expected
##   value agree with itself.
## - `compare_panel()` asks the controller which node is on screen and the panel what it
##   is drawing, and says what disagrees (empty string when nothing does).
## - `evidence_record()` / `evidence_line()` print one `EVIDENCE {json}` line per frame, the
##   record `tools/screenshot_evidence.py` keeps in `docs/screenshots/MANIFEST.json`.
## - `ui_fingerprint()` hashes the panel's scene and script the same way the Python checker
##   does, so a frame records which reading band it photographed.
## - `write_jpeg_copy()` writes a full-size JPEG beside a PNG when the relay workflow asks
##   for one (`WIS_EVIDENCE_JPEG_QUALITY`), and does nothing otherwise.

const DIALOGUE_ROOT := "res://data/dialogue"
## The opening conversation: what the first frame of a playthrough shows.
const OPENING_CONVERSATION := "q_wake"
const OPENING_SOURCE := "prologue.json"
## The files that decide what the reading band looks like. The order is part of the
## fingerprint; `tools/screenshot_evidence.py` keeps the same list in the same order.
const UI_FINGERPRINT_FILES: Array[String] = [
	"scenes/ui/dialogue_panel.tscn",
	"scripts/ui/dialogue_panel.gd",
]
const JPEG_QUALITY_ENV := "WIS_EVIDENCE_JPEG_QUALITY"


## The authored node of `conversation` in `data/dialogue/<locale>/<source_file>`: the node
## named `node_id`, or the conversation's `start` when `node_id` is empty. Returns
## `{ok, error, node, text, speaker}`.
static func authored_node(
	locale: String, source_file: String, conversation: String, node_id: String = ""
) -> Dictionary:
	var result := {"ok": false, "error": "", "node": "", "text": "", "speaker": ""}
	var path := "%s/%s/%s" % [DIALOGUE_ROOT, locale, source_file]
	if not FileAccess.file_exists(path):
		result["error"] = "%s does not exist" % path
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		result["error"] = "%s is not a JSON object" % path
		return result
	var conversations: Variant = (parsed as Dictionary).get("conversations", {})
	if not conversations is Dictionary or not (conversations as Dictionary).has(conversation):
		result["error"] = "%s has no conversation '%s'" % [path, conversation]
		return result
	var graph: Dictionary = (conversations as Dictionary)[conversation]
	var wanted := node_id if not node_id.is_empty() else String(graph.get("start", ""))
	if wanted.is_empty():
		result["error"] = "'%s' in %s names no start node" % [conversation, path]
		return result
	var nodes: Variant = graph.get("nodes", [])
	if nodes is Array:
		for entry: Variant in nodes:
			if entry is Dictionary and String((entry as Dictionary).get("id", "")) == wanted:
				result["ok"] = true
				result["node"] = wanted
				result["text"] = String((entry as Dictionary).get("text", ""))
				result["speaker"] = String((entry as Dictionary).get("speaker", ""))
				return result
	result["error"] = "'%s' in %s has no node '%s'" % [conversation, path, wanted]
	return result


## What disagrees between the frame about to be taken and the authored content: the
## locale, the conversation and node on screen, and the sentence the panel draws. An empty
## string means the frame shows exactly the authored node.
static func compare_panel(
	panel: DialoguePanel,
	dialogue: DialogueController,
	locale: String,
	source_file: String,
	conversation: String,
	node_id: String = ""
) -> String:
	if panel == null or dialogue == null:
		return "no dialogue panel or controller to compare"
	var authored := authored_node(locale, source_file, conversation, node_id)
	if not bool(authored["ok"]):
		return String(authored["error"])
	var problems := PackedStringArray()
	if L10n.current != locale:
		problems.append("the game is in '%s', not '%s'" % [L10n.current, locale])
	var line := dialogue.get_current_line()
	var shown_conversation := String(line.get("conversation_id", ""))
	var shown_node := String(line.get("node_id", ""))
	if shown_conversation != conversation:
		problems.append("conversation '%s' is on screen, not '%s'" % [shown_conversation, conversation])
	if shown_node != String(authored["node"]):
		problems.append("node '%s' is on screen, not '%s'" % [shown_node, authored["node"]])
	var drawn := panel.get_body_text()
	if drawn != String(authored["text"]):
		problems.append(
			"the panel draws \"%s\" but %s/%s/%s says \"%s\""
			% [drawn, locale, source_file, authored["node"], authored["text"]]
		)
	if panel.is_revealing():
		problems.append("the sentence is still being revealed")
	return "; ".join(problems)


## One frame's record, in the shape `docs/screenshots/MANIFEST.json` keeps under `shows`
## (plus the frame's file name, size and the reading band's fingerprint).
static func evidence_record(
	frame: String,
	size: Vector2i,
	locale: String,
	source_file: String,
	conversation: String,
	node_id: String = ""
) -> Dictionary:
	var authored := authored_node(locale, source_file, conversation, node_id)
	var engine := Engine.get_version_info()
	return {
		"frame": frame,
		"size": [size.x, size.y],
		"godot": "%d.%d.%d" % [int(engine.get("major", 0)), int(engine.get("minor", 0)), int(engine.get("patch", 0))],
		"ui_fingerprint": ui_fingerprint(),
		"shows": {
			"kind": "dialogue",
			"locale": locale,
			"source": "data/dialogue/%s/%s" % [locale, source_file],
			"conversation": conversation,
			"node": String(authored.get("node", node_id)),
			"text": String(authored.get("text", "")),
		},
	}


## `EVIDENCE {json}` on one line: what the relay workflow collects into `frames.json`.
static func evidence_line(record: Dictionary) -> String:
	return "EVIDENCE %s" % JSON.stringify(record, "", true)


## A short hash of the files that draw the reading band. Each file contributes
## `<path>\n<sha256 of its bytes>\n`; the whole string is hashed again. A missing file
## contributes `<path>\nmissing\n`, so the hash still changes when one disappears.
static func ui_fingerprint() -> String:
	var joined := ""
	for relative: String in UI_FINGERPRINT_FILES:
		var path := "res://%s" % relative
		var digest := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
		joined += "%s\n%s\n" % [relative, digest]
	return joined.sha256_text().substr(0, 16)


## The JPEG quality the relay asked for (0..1), or a negative number when it asked for none.
static func requested_jpeg_quality() -> float:
	var raw := OS.get_environment(JPEG_QUALITY_ENV).strip_edges()
	if raw.is_empty() or not raw.is_valid_float():
		return -1.0
	return clampf(raw.to_float(), 0.05, 1.0)


## When the relay workflow asked for one, writes a full-size JPEG next to `png_path`
## (same name, `.jpg`) and returns its path; otherwise returns "" and writes nothing.
static func write_jpeg_copy(image: Image, png_path: String) -> String:
	var quality := requested_jpeg_quality()
	if quality < 0.0 or image == null or image.is_empty():
		return ""
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RGB8)
	var jpeg_path := png_path.get_basename() + ".jpg"
	if copy.save_jpg(jpeg_path, quality) != OK:
		return ""
	return jpeg_path
