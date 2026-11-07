extends SceneTree
## Temporary probe: proves that a real (non-headless) window renders this project
## under Xvfb in CI, and that a frame can be captured from the live viewport.

const SCENE := "res://scenes/main/main.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	if packed == null:
		print("PROBE FAIL: scene did not load")
		quit(1)
		return
	var main: Node = packed.instantiate()
	var sequence := main.get_node_or_null("OpeningSequence")
	if sequence != null:
		sequence.set("autostart", false)
	root.add_child(main)
	for i in 40:
		await process_frame
	RenderingServer.force_draw(true)
	await process_frame
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("PROBE FAIL: viewport texture has no image")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/screenshots"))
	var path := "res://docs/screenshots/probe_headless_check.png"
	var err := image.save_png(path)
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	print("PROBE size=%dx%d err=%d center=%s" % [image.get_width(), image.get_height(), err, center])
	print("PROBE OK: wrote %s" % path)
	quit(0)
