extends SceneTree
## Called by review_author_draft.py in a staging project. Never writes to res://.

const Patch := preload("res://scripts/story_editor/dialogue_patch.gd")
const Journal := preload("res://scripts/story_editor/draft_journal.gd")


func _initialize() -> void:
	call_deferred("_review")


func _review() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or not args[0].is_absolute_path() or not args[1].is_absolute_path():
		_fail("Expected two absolute paths: input draft and review result.")
		return
	var draft := Patch.read_json(args[0])
	if not Patch.valid_envelope(draft):
		_fail("无效或不支持的剧情草稿（需为本游戏作者版导出的 JSON）。")
		return
	var chapters := {}
	var placeholders: Array[Dictionary] = []
	for id: Variant in draft["chapters"]:
		if not id is String or id not in DialogueLibrary.CHAPTERS or not draft["chapters"][id] is Dictionary:
			_fail("草稿引用了不支持的章节。")
			return
		var base := Patch.read_json(DialogueLibrary.chapter_path(Patch.LOCALE, id))
		if base.is_empty():
			_fail("无法读取当前章节：" + id)
			return
		var result := Patch.apply_chapter(base, id, draft["chapters"][id])
		if result.has("error"):
			_fail(result["error"])
			return
		var graph: DialogueGraph = result["graph"]
		if not graph.is_valid():
			_fail("当前章节本身未通过校验：" + id)
			return
		var followups: Patch.Followups = result.get("followups")
		if followups != null:
			for pending: Dictionary in followups.placeholders.values():
				placeholders.append(pending.merged({"chapter": id}))
		if result["data"] != base:
			chapters[id] = result["data"]
	# Never emit a game-data candidate containing a draft-only placeholder.
	var output := {"chapters": chapters if placeholders.is_empty() else {}, "pending_followups": placeholders}
	var error := Journal.write_checked(args[1], JSON.stringify(output, "\t", false, true))
	if error != OK:
		_fail("无法保存预检结果。")
		return
	quit()


func _fail(message: String) -> void:
	printerr("作者草稿预检：", message)
	quit(1)
