extends SceneTree
## The interaction outline respects the depth of the scene, measured on rendered pixels.
##
## This test needs a real renderer: it reads the frames back and looks at them. CI runs it in
## a window under Xvfb with `--rendering-driver opengl3`, i.e. Godot's Compatibility renderer,
## and sets `OUTLINE_REQUIRE_RENDERER=gl_compatibility` so a run on any other renderer fails
## instead of passing on the wrong evidence. Under `--headless` it fails: a headless run
## draws nothing, and a pass there would prove nothing.
##
## The scene is built here, not loaded: three unit boxes in front of a fixed camera, all
## unshaded, so a pixel's colour is its material's colour and nothing else.
##
##   open     - nothing in front of it;
##   hidden   - a wall in front of it covers its whole silhouette;
##   partial  - a post in front of it covers the left part of its silhouette.
##
## The outline is found two ways. Its *line* is a warm, light colour that nothing in the
## scene comes near (`_is_line`), so line pixels can be classified in any frame without a
## reference. "Nothing was drawn" is stronger: the frame with the outline is compared with the
## same frame without it, so the wash and the dark rim count too.
##
## Checks, each against the box's projected silhouette (the convex hull of its eight
## projected corners):
##
## 1. open: line pixels all around the silhouette, none farther from it than the pen;
## 2. hidden: not a single pixel differs from the frame without the outline, and the mask is
##    empty there; with the wall hidden, the same box is outlined all round (the control);
##    and with the mask camera cut back to the outline layer alone - the mask as it was before
##    it was depth-tested - the outline shows through the wall (the negative control);
## 3. partial: the line runs along the visible part of the silhouette and along the post's
##    edge where the post cuts the box, and is absent from the part of the silhouette the post
##    covers;
## 4. switching from one target to another moves the whole outline in the first rendered
##    frame - nothing is left on the first box - and gives the first box's meshes back their
##    layers and their own overlay material, unchanged;
## 5. releasing a target while its outline is fading removes it in the next frame, stops the
##    mask pass, and a late release from an owner that was already replaced does not touch
##    the outline that replaced it;
## 6. the camera moves every frame while the outline is shown, and every one of those frames
##    has the outline on the box where the box is drawn in that frame.
##
## Frames are saved as evidence: `$OUTLINE_EVIDENCE_DIR` if set, otherwise
## `user://outline_occlusion/`.

const Harness = preload("res://tests/test_harness.gd")

const TIMEOUT_SECONDS := 180.0
## A line pixel can be up to (line + rim) px outside the silhouette; plus rounding.
const PEN_TOLERANCE_PX := 6.0
## Where to look for the line: just outside the silhouette, along its outward normal.
const LINE_OFFSET_PX := 1.5
## Hull samples are only counted as "covered" / "visible" with this margin from the
## occluder's edge, so the line traced along that edge is never what is being measured.
const OCCLUDER_MARGIN_PX := 10.0
const SAMPLE_STEP_PX := 4.0
## Two renders of the same scene are the same picture; one 8-bit step of slack.
const SAME_PIXEL := 1.0 / 255.0 + 0.0001
## Fractions of samples that must find the line.
const FULL_COVERAGE := 0.95
const VISIBLE_COVERAGE := 0.9

const BACKGROUND := Color(0.11, 0.13, 0.19)
const BOX_COLOURS := [Color(0.2, 0.35, 0.8), Color(0.18, 0.55, 0.3), Color(0.55, 0.3, 0.75)]
const OCCLUDER_COLOUR := Color(0.45, 0.1, 0.1)
const CAMERA_POSITION := Vector3(0.0, 2.2, 7.0)
const CAMERA_TARGET := Vector3(0.0, 0.6, 0.0)

var _failures: Array[String] = []
var _checks: int = 0
var _notes: Array[String] = []
var _world: Node3D = null
var _camera: Camera3D = null
var _overlay: OutlineOverlay = null
var _open: MeshInstance3D = null
var _hidden: MeshInstance3D = null
var _partial: MeshInstance3D = null
var _wall: MeshInstance3D = null
var _post: MeshInstance3D = null
var _authored_overlay: StandardMaterial3D = null
var _evidence_dir: String = ""


class Owner:
	extends RefCounted
	var label: String = ""

	func _init(text: String) -> void:
		label = text


func _initialize() -> void:
	Harness.arm_watchdog(self, TIMEOUT_SECONDS, "interaction_outline_occlusion_test.gd")
	call_deferred("_run")


func _run() -> void:
	Harness.stage = "renderer"
	if not _renderer_is_usable():
		Harness.finish(self, _failures, "")
		return
	_prepare_evidence_dir()
	_build_scene()
	await _frames(4)
	if not _frame_matches_viewport():
		Harness.finish(self, _failures, "")
		return
	_check_preconditions()
	if not _failures.is_empty():
		Harness.finish(self, _failures, "")
		return

	await _check_open()
	await _check_hidden()
	await _check_partial()
	await _check_switch()
	await _check_release_while_fading()
	await _check_camera_motion()

	for note in _notes:
		print("NOTE: %s" % note)
	Harness.finish(
		self,
		_failures,
		"%d checks on rendered frames (%s): an open box is outlined all round, a box behind "
		% [_checks, _renderer_name()]
		+ "a wall draws nothing, a box half behind a post is outlined only where it shows, "
		+ "switching and releasing leave nothing behind, and the outline stays on the box in "
		+ "every frame of a moving camera."
	)


# --- set-up -----------------------------------------------------------------


func _renderer_name() -> String:
	if RenderingServer.has_method("get_current_rendering_method"):
		return String(RenderingServer.call("get_current_rendering_method"))
	return String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))


func _renderer_is_usable() -> bool:
	var display := DisplayServer.get_name()
	var method := _renderer_name()
	var driver := ""
	if RenderingServer.has_method("get_current_rendering_driver_name"):
		driver = String(RenderingServer.call("get_current_rendering_driver_name"))
	print("renderer: %s (driver %s, display %s, adapter %s)" % [
		method, driver, display, RenderingServer.get_video_adapter_name()
	])
	if display == "headless":
		_failures.append(
			"This test reads rendered pixels and cannot run headless; run it in a window "
			+ "(CI: xvfb-run ... --rendering-driver opengl3)."
		)
		return false
	var required := OS.get_environment("OUTLINE_REQUIRE_RENDERER")
	if not required.is_empty() and method != required:
		_failures.append("The renderer is '%s', not the required '%s'." % [method, required])
		return false
	return true


func _prepare_evidence_dir() -> void:
	_evidence_dir = OS.get_environment("OUTLINE_EVIDENCE_DIR")
	if _evidence_dir.is_empty():
		_evidence_dir = ProjectSettings.globalize_path("user://outline_occlusion")
	DirAccess.make_dir_recursive_absolute(_evidence_dir)


func _build_scene() -> void:
	_world = Node3D.new()
	_world.name = "OcclusionWorld"
	root.add_child(_world)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world.add_child(world_environment)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 50.0
	_camera.near = 0.05
	_camera.far = 100.0
	_world.add_child(_camera)
	_camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
	_camera.current = true

	_open = _box("Open", Vector3(-2.4, 0.5, 0.0), Vector3.ONE, BOX_COLOURS[0])
	_hidden = _box("Hidden", Vector3(0.0, 0.5, 0.0), Vector3.ONE, BOX_COLOURS[1])
	_partial = _box("Partial", Vector3(2.4, 0.5, 0.0), Vector3.ONE, BOX_COLOURS[2])
	_wall = _box("Wall", Vector3(0.0, 1.0, 1.6), Vector3(2.4, 2.8, 0.1), OCCLUDER_COLOUR)
	# Between the camera and the partial box, over its left part: on screen it covers about
	# the left 40% of the box and leaves the right part in plain view (`_check_preconditions`
	# measures that rather than trusting this comment).
	_post = _box("Post", Vector3(1.5, 1.0, 1.2), Vector3(0.55, 3.2, 0.1), OCCLUDER_COLOUR)

	# The open box carries an authored overlay, as the classroom desks do: the outline must
	# leave it exactly as it is, highlighted or not.
	_authored_overlay = StandardMaterial3D.new()
	_authored_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_authored_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_authored_overlay.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_open.material_overlay = _authored_overlay

	_overlay = OutlineOverlay.new()
	_overlay.name = "OutlineOverlay"
	root.add_child(_overlay)


func _box(label: String, at: Vector3, size: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	mesh.material_override = material
	mesh.position = at
	_world.add_child(mesh)
	return mesh


func _frame_matches_viewport() -> bool:
	Harness.stage = "frame size"
	var image := root.get_texture().get_image()
	var visible := Vector2i(root.get_visible_rect().size)
	_expect(image != null and image.get_size() == visible,
		"The frame read back is %s, not the viewport's %s; screen positions would not line up."
		% [str(image.get_size() if image != null else Vector2i.ZERO), str(visible)])
	print("frame: %s" % str(visible))
	return _failures.is_empty()


## The geometry is what the checks below assume it is: measured, not hoped.
func _check_preconditions() -> void:
	Harness.stage = "preconditions"
	var size := root.get_visible_rect().size
	for mesh in [_open, _hidden, _partial, _wall, _post]:
		for point in _hull(mesh):
			_expect(
				point.x > 8.0 and point.y > 8.0 and point.x < size.x - 8.0 and point.y < size.y - 8.0,
				"%s is not fully on screen (corner at %s)." % [mesh.name, str(point)]
			)
	var wall := _hull(_wall)
	for point in _hull(_hidden):
		_expect(
			_inside_by(point, wall) >= OCCLUDER_MARGIN_PX,
			"The wall does not cover the hidden box with %.0f px to spare (corner %s)."
			% [OCCLUDER_MARGIN_PX, str(point)]
		)
	var covered := _hull_samples(_hull(_partial), _hull(_post), true)
	var shown := _hull_samples(_hull(_partial), _hull(_post), false)
	_expect(covered.size() >= 12,
		"The post covers too little of the partial box's outline (%d samples)." % covered.size())
	_expect(shown.size() >= 40,
		"Too little of the partial box's outline is in view (%d samples)." % shown.size())


# --- the cases --------------------------------------------------------------


func _check_open() -> void:
	Harness.stage = "open"
	var baseline := await _grab()
	var owner := Owner.new("open")
	_show(owner, _open, 1.0)
	var frame := await _grab_after(3)
	_save(frame, "case1_open.png")
	var hull := _hull(_open)
	var found := _line_coverage(frame, _outward_samples(hull))
	_expect(found >= FULL_COVERAGE,
		"Unobstructed: the line was found on %.0f%% of the silhouette, not all round." % (found * 100.0))
	var stray := _stray_line_pixels(frame, hull)
	_expect(stray == 0, "Unobstructed: %d line pixels are farther than the pen from the box." % stray)
	var mask := _mask_image()
	_expect(_mask_at(mask, _centroid(hull)) > 0.5, "Unobstructed: the mask is empty on the box.")
	_expect(_differs(baseline, frame, _bounds(hull, 12.0)), "Unobstructed: nothing was drawn at all.")
	_notes.append("open: line on %.0f%% of the silhouette, %d stray pixels" % [found * 100.0, stray])
	_overlay.release(owner)
	await _frames(2)


func _check_hidden() -> void:
	Harness.stage = "hidden"
	var area := _bounds(_hull(_wall), 12.0)
	var baseline := await _grab()
	var owner := Owner.new("hidden")
	_show(owner, _hidden, 1.0)
	var frame := await _grab_after(3)
	_save(frame, "case2_hidden.png")
	var change := _max_change(baseline, frame, area)
	_expect(change <= SAME_PIXEL,
		"Fully hidden: the frame changed behind the wall (largest change %.3f, %d px differ): the "
		% [change, _count_changed(baseline, frame, area)]
		+ "outline shows through.")
	var mask := _mask_image()
	_expect(_mask_at(mask, _centroid(_hull(_hidden))) < 0.01,
		"Fully hidden: the mask marks the box although the wall covers it.")
	_expect(_overlay.is_active(), "Fully hidden: the overlay stopped being active (it should still own the box).")

	# The negative control: the same outline with the mask drawing only the outline layer -
	# what the mask did before it was depth-tested. The outline must now show through the
	# wall, which proves both that this check would see it and that the scene's depth in the
	# mask is what hides it. The overlay stops syncing for the duration (the camera is
	# still), so it cannot put the full culling back.
	var mask_camera := _overlay.get_mask_camera()
	var synced_mask := mask_camera.cull_mask
	_overlay.process_mode = Node.PROCESS_MODE_DISABLED
	mask_camera.cull_mask = OutlineOverlay.MASK_LAYER
	var through := await _grab_after(3)
	_save(through, "case2_hidden_negative_control_no_depth.png")
	var through_found := _line_coverage(through, _outward_samples(_hull(_hidden)))
	_expect(through_found >= FULL_COVERAGE,
		"Negative control: without the scene in the mask the outline should show through the "
		+ "wall, but the line is on only %.0f%% of the silhouette." % (through_found * 100.0))
	mask_camera.cull_mask = synced_mask
	_overlay.process_mode = Node.PROCESS_MODE_INHERIT
	await _frames(2)

	# The control: the same box, the same outline, the wall out of the way.
	_wall.visible = false
	var control := await _grab_after(3)
	_save(control, "case2_hidden_control_no_wall.png")
	var found := _line_coverage(control, _outward_samples(_hull(_hidden)))
	_expect(found >= FULL_COVERAGE,
		"Control: with the wall hidden the box is outlined on only %.0f%% of its silhouette."
		% (found * 100.0))
	_notes.append(
		"hidden: max change %.4f behind the wall; without depth in the mask %.0f%%; control %.0f%%"
		% [change, through_found * 100.0, found * 100.0]
	)
	_wall.visible = true
	_overlay.release(owner)
	await _frames(2)


func _check_partial() -> void:
	Harness.stage = "partial"
	var owner := Owner.new("partial")
	_show(owner, _partial, 1.0)
	var frame := await _grab_after(3)
	_save(frame, "case3_partial.png")
	var hull := _hull(_partial)
	var post := _hull(_post)

	var shown := _offset_samples(_hull_samples(hull, post, false), hull, LINE_OFFSET_PX)
	var shown_found := _line_coverage(frame, shown)
	_expect(shown_found >= VISIBLE_COVERAGE,
		"Partly hidden: the line covers %.0f%% of the visible silhouette." % (shown_found * 100.0))

	var covered := _offset_samples(_hull_samples(hull, post, true), hull, LINE_OFFSET_PX)
	var covered_found := _line_coverage(frame, covered)
	_expect(covered_found == 0.0,
		"Partly hidden: the line is drawn on %.0f%% of the silhouette the post covers."
		% (covered_found * 100.0))

	# The visible part is closed off along the post's edge: the line runs on the post,
	# just outside what is still visible of the box.
	var edge := _edge_samples_inside(post, hull)
	var edge_found := _line_coverage(frame, edge)
	_expect(edge.size() >= 8 and edge_found >= 0.8,
		"Partly hidden: the line does not follow the post's edge across the box (%.0f%% of %d)."
		% [edge_found * 100.0, edge.size()])

	var stray := _stray_line_pixels(frame, hull)
	_expect(stray == 0, "Partly hidden: %d line pixels are away from the box." % stray)
	var mask := _mask_image()
	_expect(_mask_at(mask, _inside_point(hull, post, false)) > 0.5,
		"Partly hidden: the mask is empty on the visible part.")
	_expect(_mask_at(mask, _inside_point(hull, post, true)) < 0.01,
		"Partly hidden: the mask marks the part behind the post.")
	_notes.append("partial: visible %.0f%%, covered %.0f%%, along the post %.0f%%"
		% [shown_found * 100.0, covered_found * 100.0, edge_found * 100.0])
	_overlay.release(owner)
	await _frames(2)


func _check_switch() -> void:
	Harness.stage = "switch"
	var first := Owner.new("first")
	var second := Owner.new("second")
	var open_layers := _open.layers
	_show(first, _open, 1.0)
	await _grab_after(3)
	_expect(_open.material_overlay == _authored_overlay and _authored_overlay.next_pass == null,
		"Highlighting the box changed its authored overlay material.")
	var twins := _overlay.get_key_twins()
	_expect(twins.size() == 1 and twins[0].get_parent() == _open,
		"The highlighted box has no key twin in the mask (%d twins)." % twins.size())
	_expect(_open.get_child_count() == 0,
		"The key twin is visible to scene walks (get_children): it must be an internal child.")

	# The controller hands over in one frame: new owner, new meshes.
	_show(second, _partial, 1.0)
	_expect(_open.layers == open_layers, "Switching did not give the first box its layers back.")
	_expect(_open.material_overlay == _authored_overlay,
		"Switching changed the first box's own overlay.")
	_expect(_open.get_child_count(true) == 0,
		"Switching left the first box's key twin in the tree.")
	var frame := await _grab_after(0)
	_save(frame, "case4_switch_first_frame.png")
	var old_found := _line_coverage(frame, _outward_samples(_hull(_open)))
	_expect(old_found == 0.0,
		"Switching: %.0f%% of the first box's outline is still drawn in the first frame."
		% (old_found * 100.0))
	var new_found := _line_coverage(
		frame, _offset_samples(_hull_samples(_hull(_partial), _hull(_post), false),
			_hull(_partial), LINE_OFFSET_PX)
	)
	_expect(new_found >= VISIBLE_COVERAGE,
		"Switching: the second box is outlined on only %.0f%% in the first frame." % (new_found * 100.0))
	_overlay.release(second)
	await _frames(2)


func _check_release_while_fading() -> void:
	Harness.stage = "release while fading"
	var baseline := await _grab()
	var owner := Owner.new("fading")
	_show(owner, _open, 1.0)
	await _grab_after(2)
	_overlay.set_opacity(owner, 0.45)
	var half := await _grab_after(1)
	var area := _bounds(_hull(_open), 12.0)
	_expect(_differs(baseline, half, area), "Fading: the half-faded outline is not drawn at all.")
	_overlay.release(owner)
	_expect(not _overlay.is_active(), "Released while fading: the overlay is still active.")
	_expect(_open.material_overlay == _authored_overlay and _authored_overlay.next_pass == null,
		"Released while fading: the box's overlay is not the authored one.")
	_expect(_open.get_child_count(true) == 0, "Released while fading: the key twin is still in the tree.")
	_expect(_open.layers & OutlineOverlay.MASK_LAYER == 0,
		"Released while fading: the box kept the mask layer.")
	var viewport := _overlay.get_mask_viewport()
	_expect(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"Released while fading: the mask pass keeps running.")
	var after := await _grab_after(0)
	var change := _max_change(baseline, after, area)
	_expect(change <= SAME_PIXEL,
		"Released while fading: the next frame still differs (%.3f) - a stale outline." % change)

	# A late fade from a replaced owner: the replacement keeps its outline.
	var stale := Owner.new("stale")
	var current := Owner.new("current")
	_show(stale, _open, 1.0)
	await _grab_after(1)
	_overlay.set_opacity(stale, 0.5)
	_show(current, _partial, 1.0)
	_overlay.set_opacity(stale, 0.1)
	_overlay.release(stale)
	_expect(_overlay.is_owned_by(current), "A stale owner's release took the overlay away.")
	_expect(is_equal_approx(_overlay.get_opacity(), 1.0),
		"A stale owner's fade changed the current outline's opacity (%.2f)." % _overlay.get_opacity())
	var frame := await _grab_after(1)
	var found := _line_coverage(
		frame, _offset_samples(_hull_samples(_hull(_partial), _hull(_post), false),
			_hull(_partial), LINE_OFFSET_PX)
	)
	_expect(found >= VISIBLE_COVERAGE,
		"After a stale release the current outline covers only %.0f%%." % (found * 100.0))
	_expect(_line_coverage(frame, _outward_samples(_hull(_open))) == 0.0,
		"After a stale release the replaced box is outlined again.")
	_overlay.release(current)
	await _frames(2)


func _check_camera_motion() -> void:
	Harness.stage = "camera motion"
	var owner := Owner.new("moving")
	_show(owner, _open, 1.0)
	await _grab_after(2)
	var worst := 1.0
	var worst_stray := 0
	for step in 10:
		# Move and turn the camera, then look at the very next frame: the mask camera must
		# have followed before it was drawn.
		var offset := Vector3(-0.12 * float(step + 1), 0.05 * float(step % 3), 0.0)
		var aim := CAMERA_TARGET + Vector3(-0.1 * float(step + 1), 0.0, 0.0)
		_camera.look_at_from_position(CAMERA_POSITION + offset, aim, Vector3.UP)
		var frame := await _grab_after(0)
		if step == 9:
			_save(frame, "case6_camera_moved.png")
		var hull := _hull(_open)
		var found := _line_coverage(frame, _outward_samples(hull))
		var stray := _stray_line_pixels(frame, hull)
		worst = minf(worst, found)
		worst_stray = maxi(worst_stray, stray)
		_expect(found >= FULL_COVERAGE,
			"Camera step %d: the line is on only %.0f%% of where the box is drawn (drift)."
			% [step, found * 100.0])
		_expect(stray == 0, "Camera step %d: %d line pixels are off the box (drift)." % [step, stray])
	_notes.append("camera motion: worst coverage %.0f%%, worst stray %d" % [worst * 100.0, worst_stray])
	_camera.look_at_from_position(CAMERA_POSITION, CAMERA_TARGET, Vector3.UP)
	_overlay.release(owner)
	await _frames(2)


# --- outline control ----------------------------------------------------------


func _show(owner: Owner, mesh: MeshInstance3D, opacity: float) -> void:
	var meshes: Array[GeometryInstance3D] = [mesh]
	_overlay.show_meshes(owner, meshes)
	_overlay.set_opacity(owner, opacity)


# --- frames -------------------------------------------------------------------


func _frames(count: int) -> void:
	for index in count:
		await process_frame
	await RenderingServer.frame_post_draw


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## The frame drawn after `settle` further frames. `settle` 0 is the first frame drawn after
## whatever the caller just changed.
func _grab_after(settle: int) -> Image:
	for index in settle:
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _mask_image() -> Image:
	var viewport := _overlay.get_mask_viewport()
	return viewport.get_texture().get_image() if viewport != null else null


func _mask_at(mask: Image, point: Vector2) -> float:
	if mask == null:
		return -1.0
	var frame := root.get_visible_rect().size
	var x := clampi(int(point.x * float(mask.get_width()) / frame.x), 0, mask.get_width() - 1)
	var y := clampi(int(point.y * float(mask.get_height()) / frame.y), 0, mask.get_height() - 1)
	return mask.get_pixel(x, y).r


func _save(image: Image, file_name: String) -> void:
	if image == null:
		return
	var path := _evidence_dir.path_join(file_name)
	var error := image.save_png(path)
	if error == OK:
		print("EVIDENCE: %s" % path)
	else:
		print("EVIDENCE: could not write %s (error %d)" % [path, error])


# --- pixel classification -------------------------------------------------------


## The outline's line colour over anything in this scene: warm and light. The breath takes at
## most 18% off its alpha, which still leaves it far from every material here.
func _is_line(colour: Color) -> bool:
	return colour.r > 0.7 and colour.g > 0.55 and colour.b < 0.8 and colour.r - colour.b > 0.15


func _line_near(image: Image, point: Vector2) -> bool:
	var cx := int(roundf(point.x))
	var cy := int(roundf(point.y))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			if _is_line(image.get_pixel(x, y)):
				return true
	return false


func _line_coverage(image: Image, samples: PackedVector2Array) -> float:
	if samples.is_empty():
		return 0.0
	var hits := 0
	for point in samples:
		if _line_near(image, point):
			hits += 1
	return float(hits) / float(samples.size())


## Line pixels farther than the pen from the silhouette (inside counts as on it).
func _stray_line_pixels(image: Image, hull: PackedVector2Array) -> int:
	var area := _bounds(hull, 40.0)
	var stray := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if not _is_line(image.get_pixel(x, y)):
				continue
			if _distance_outside(Vector2(x + 0.5, y + 0.5), hull) > PEN_TOLERANCE_PX:
				stray += 1
	return stray


## The largest change of any colour channel in `area`, 0..1.
func _max_change(a: Image, b: Image, area: Rect2i) -> float:
	var worst := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			worst = maxf(worst, maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))))
	return worst


func _differs(a: Image, b: Image, area: Rect2i) -> bool:
	return _max_change(a, b, area) > 2.0 / 255.0


func _count_changed(a: Image, b: Image, area: Rect2i) -> int:
	var changed := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if maxf(absf(p.r - q.r), maxf(absf(p.g - q.g), absf(p.b - q.b))) > 1.5 / 255.0:
				changed += 1
	return changed


# --- screen geometry -------------------------------------------------------------


## The box's silhouette on screen: the convex hull of its eight projected corners.
func _hull(mesh: MeshInstance3D) -> PackedVector2Array:
	var box := mesh.get_aabb()
	var points := PackedVector2Array()
	for corner in 8:
		points.append(_camera.unproject_position(mesh.global_transform * box.get_endpoint(corner)))
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	return hull


func _centroid(hull: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for point in hull:
		sum += point
	return sum / float(maxi(hull.size(), 1))


func _bounds(hull: PackedVector2Array, grow: float) -> Rect2i:
	var rect := Rect2(hull[0], Vector2.ZERO)
	for point in hull:
		rect = rect.expand(point)
	rect = rect.grow(grow)
	var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	rect = rect.intersection(frame)
	return Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.size.floor()))


func _distance_to_edge(point: Vector2, hull: PackedVector2Array) -> float:
	var best := INF
	for index in hull.size():
		var a := hull[index]
		var b := hull[(index + 1) % hull.size()]
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return best


func _distance_outside(point: Vector2, hull: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, hull):
		return 0.0
	return _distance_to_edge(point, hull)


## Positive: how far inside `hull` the point is. Negative: how far outside.
func _inside_by(point: Vector2, hull: PackedVector2Array) -> float:
	var distance := _distance_to_edge(point, hull)
	return distance if Geometry2D.is_point_in_polygon(point, hull) else -distance


## Points along the hull's boundary, every few pixels.
func _boundary(hull: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in hull.size():
		var a := hull[index]
		var b := hull[(index + 1) % hull.size()]
		var length := a.distance_to(b)
		var count := maxi(int(length / SAMPLE_STEP_PX), 1)
		for step in count:
			points.append(a.lerp(b, (float(step) + 0.5) / float(count)))
	return points


func _outward_samples(hull: PackedVector2Array) -> PackedVector2Array:
	return _offset_samples(_boundary(hull), hull, LINE_OFFSET_PX)


## Each boundary point moved `distance` px away from the hull (negative: into it).
func _offset_samples(points: PackedVector2Array, hull: PackedVector2Array, distance: float) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for point in points:
		var nearest := hull[0]
		var best := INF
		var normal := Vector2.ZERO
		for index in hull.size():
			var a := hull[index]
			var b := hull[(index + 1) % hull.size()]
			var on := Geometry2D.get_closest_point_to_segment(point, a, b)
			var d := point.distance_to(on)
			if d < best:
				best = d
				nearest = on
				normal = (b - a).orthogonal().normalized()
		if normal.dot(nearest - _centroid(hull)) < 0.0:
			normal = -normal
		moved.append(point + normal * distance)
	return moved


## Boundary points of `hull` that are behind `occluder` (covered) or clear of it (not),
## each with a margin from the occluder's edge.
func _hull_samples(hull: PackedVector2Array, occluder: PackedVector2Array, covered: bool) -> PackedVector2Array:
	var picked := PackedVector2Array()
	for point in _boundary(hull):
		var depth := _inside_by(point, occluder)
		if covered and depth >= OCCLUDER_MARGIN_PX:
			picked.append(point)
		elif not covered and depth <= -OCCLUDER_MARGIN_PX:
			picked.append(point)
	return picked


## Points just inside the occluder's edge, where that edge crosses the box well inside its
## silhouette: where the line closing off the visible part should be.
func _edge_samples_inside(occluder: PackedVector2Array, hull: PackedVector2Array) -> PackedVector2Array:
	var picked := PackedVector2Array()
	var moved := _offset_samples(_boundary(occluder), occluder, -LINE_OFFSET_PX)
	for point in moved:
		if _inside_by(point, hull) >= OCCLUDER_MARGIN_PX:
			picked.append(point)
	return picked


## A point well inside the box that is behind the occluder (`covered`) or in view.
func _inside_point(hull: PackedVector2Array, occluder: PackedVector2Array, covered: bool) -> Vector2:
	var area := _bounds(hull, 0.0)
	var best := _centroid(hull)
	var best_score := -INF
	for y in range(area.position.y, area.end.y, 4):
		for x in range(area.position.x, area.end.x, 4):
			var point := Vector2(x, y)
			var in_box := _inside_by(point, hull)
			var in_occluder := _inside_by(point, occluder)
			var score := minf(in_box, in_occluder if covered else -in_occluder)
			if score > best_score:
				best_score = score
				best = point
	return best


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append("[%s] %s" % [Harness.stage, message])
