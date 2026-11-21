extends SceneTree
## The imagined lesson (docs/IMAGINED_LESSON.md): teacher B as the protagonist pictures her
## during `expected_b`, drawn in the classroom itself.
##
## On the real classroom scene, with a camera where the game's rig puts it:
##
## 1. **Off by default.** The room is entered with the imagined lesson hidden, not
##    processing, its screen filter's layer hidden and its dream at 0.
## 2. **Built from the shipped model.** One lead figure and two after-images, each an
##    instance of `assets/models/teacher_b/teacher_b.glb` with one skeleton and a motion
##    player holding the shipped library; every mesh is drawn by the dream shader with the
##    dream ink as its next pass; the after-images are flat (`echo` 1) and cast no shadow.
##    The lead stands in the room, is larger than life and faces the protagonist's seat.
## 3. **Presentation only.** No collision, no interactable, no `NpcActor` anywhere in it:
##    B's real entrance stays `BPresence.present()`.
## 4. **On with the imagined exchange.** `ClassroomPresentation.set_b_impression_visible()`
##    fades it in (lesson, filter layer, motion, the swirl centred on screen near her head)
##    and back out to fully hidden and not processing.
## 5. **Renderer-safe filter.** The filter is a canvas item reading the screen texture in a
##    canvas layer under the game UI (layer 1), and both shaders exist where the scene says.
##
## With `-- --capture` (a rendered window; `.github/workflows/imagined-lesson-capture.yml`)
## it also photographs the room from the game camera before, during (twice, a second apart,
## so the wave is seen moving) and in a closer shot of her, into `builds/imagined-lesson/`,
## and checks that the dream changes the picture.

const Harness = preload("res://tests/test_harness.gd")
const CLASSROOM := "res://scenes/locations/classroom/classroom.tscn"
const FIGURE_SHADER := "res://assets/shaders/imagined/dream_figure.gdshader"
const INK_SHADER := "res://assets/shaders/imagined/dream_ink.gdshader"
const WAVE_SHADER := "res://assets/shaders/imagined/munch_wave.gdshader"
const MOTION := "res://assets/models/teacher_b/teacher_b_motion.tres"
## The game camera's offset from its target (scenes/main/main.tscn, CameraRig).
const CAMERA_OFFSET := Vector3(3.4, 6.4, 3.4)
const PROTAGONIST := "res://scenes/environment/characters/protagonist.tscn"
const OUT := "res://builds/imagined-lesson"
## Real seconds to wait for a fade. The fades are 1.6 s and 0.9 s of game time, but a
## software Vulkan renderer compiles the shaders on the first frames and draws a few
## frames per second, so the wait is generous.
const FADE_LIMIT := 40.0

var _check := Harness.Checker.new()
var _room: Node3D = null


func _initialize() -> void:
	Harness.arm_watchdog(self, 180.0, "imagined_lesson_test.gd")
	call_deferred("_run")


func _run() -> void:
	var autoloads := Harness.ensure_state_autoloads(self)
	if autoloads["game_state"] == null:
		Harness.finish(self, ["State autoloads are unavailable."], "")
		return
	Harness.clear_session_state(self)
	var packed := load(CLASSROOM) as PackedScene
	if packed == null:
		Harness.finish(self, ["The classroom could not be loaded."], "")
		return
	_room = packed.instantiate() as Node3D
	root.add_child(_room)
	var seat := (_room.get_node(^"SpawnPoints/PlayerStart") as Node3D).global_position
	var camera := Camera3D.new()
	camera.fov = 60.0
	root.add_child(camera)
	camera.global_position = seat + CAMERA_OFFSET
	camera.look_at(seat + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	camera.current = true
	var capture := "--capture" in OS.get_cmdline_user_args()
	if capture:
		# Standing, as she has just told him to.
		var lead := (load(PROTAGONIST) as PackedScene).instantiate() as Node3D
		_room.add_child(lead)
		lead.global_position = seat
	await process_frame
	await process_frame

	var lesson := _room.get_node_or_null(^"ImaginedLesson") as ImaginedLesson
	var presentation := _room.get_node_or_null(^"ClassroomPresentation")
	if lesson == null or presentation == null:
		Harness.finish(self, ["The classroom has no ImaginedLesson or ClassroomPresentation."], "")
		return

	Harness.stage = "off by default"
	_expect_off(lesson, "on entering the room")

	Harness.stage = "built from the shipped model"
	_check_figures(lesson, seat)

	Harness.stage = "presentation only"
	for node in lesson.find_children("*", "", true, false):
		_check.expect(not (node is CollisionObject3D), "%s is a collision object." % node.name)
		_check.expect(not (node is Interactable), "%s is an interactable." % node.name)
		_check.expect(not (node is NpcActor), "%s is an NPC actor." % node.name)

	Harness.stage = "renderer-safe filter"
	_check_filter(lesson)

	var before: Image = null
	if capture:
		Harness.stage = "capture before"
		if not _check.expect(
			DisplayServer.get_name() != "headless", "--capture needs a rendered window."
		):
			capture = false
		else:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
			before = await _photograph("before")

	Harness.stage = "fade in"
	presentation.call("set_b_impression_visible", true)
	_check.expect(
		lesson.is_active() and lesson.visible,
		"Showing the impression did not start the imagined lesson."
	)
	_check.expect(
		(lesson.get_node(^"Wave") as CanvasLayer).visible, "The screen filter's layer is not shown."
	)
	await Harness.wait_until(func() -> bool: return lesson.get_dream() >= 1.0, FADE_LIMIT)
	_check.expect(
		is_equal_approx(lesson.get_dream(), 1.0),
		"The dream did not reach 1 (%.2f)." % lesson.get_dream()
	)
	var wave := lesson.get_wave_material()
	_check.expect(
		is_equal_approx(_param(wave, &"strength"), 1.0), "The filter is not at full strength."
	)
	var vortex: Variant = wave.get_shader_parameter(&"vortex")
	_check.expect(
		(
			vortex is Vector2
			and vortex.x > 0.0
			and vortex.x < 1.0
			and vortex.y >= -0.25
			and vortex.y < 1.0
		),
		"The swirl is not centred on her (%s): she is out of the game camera's view." % str(vortex)
	)
	for figure in lesson.get_figures():
		var player := figure.get_node_or_null(^"Motion") as AnimationPlayer
		_check.expect(
			player != null and player.is_playing(),
			"%s's figure is not moving." % figure.get_parent().name
		)
	for material in _figure_materials(lesson):
		_check.expect(
			is_equal_approx(_param(material, &"dream"), 1.0), "A figure is not fully dreamed."
		)

	if capture:
		Harness.stage = "capture dream"
		var dream := await _photograph("dream")
		_check.expect(
			_changed(before, dream) > 0.35, "The dream frame is too close to the plain room."
		)
		await create_timer(1.1).timeout
		var later := await _photograph("dream_later")
		_check.expect(_changed(dream, later) > 0.02, "The wave does not move between frames.")
		var head := lesson.get_figures()[0].to_global(ImaginedLesson.HEAD)
		camera.global_position = head + Vector3(2.2, 0.4, 2.6)
		camera.look_at(head + Vector3(-0.5, -0.5, -0.4), Vector3.UP)
		await create_timer(0.4).timeout
		await _photograph("dream_close")
		camera.global_position = seat + CAMERA_OFFSET
		camera.look_at(seat + Vector3(0.0, 0.9, 0.0), Vector3.UP)

	Harness.stage = "fade out"
	presentation.call("set_b_impression_visible", false)
	_check.expect(not lesson.is_active(), "Hiding the impression did not end the imagined lesson.")
	await Harness.wait_until(func() -> bool: return not lesson.visible, FADE_LIMIT)
	_expect_off(lesson, "after the imagined exchange")

	Harness.finish(
		self,
		_check.failures,
		"the imagined lesson is built from teacher B's model and follows the exchange."
	)


func _photograph(id: String) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT).path_join(id + ".png")
	_check.expect(image.save_png(path) == OK, "Could not save %s." % path)
	# A small copy for the workflow to relay as annotations.
	var small := image.duplicate() as Image
	small.resize(
		800, roundi(800.0 * image.get_height() / image.get_width()), Image.INTERPOLATE_LANCZOS
	)
	_check.expect(
		small.save_jpg(path.get_basename() + ".jpg", 0.8) == OK, "Could not save %s's JPEG." % id
	)
	print("%s: %dx%d" % [id, image.get_width(), image.get_height()])
	return image


## The share of sampled pixels that differ noticeably between two frames.
func _changed(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 0.0
	var changed := 0
	var total := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			total += 1
			if absf(p.r - q.r) + absf(p.g - q.g) + absf(p.b - q.b) > 0.09:
				changed += 1
	return float(changed) / float(maxi(total, 1))


## A float shader parameter, or NAN when the material does not report it.
func _param(material: ShaderMaterial, parameter: StringName) -> float:
	var value: Variant = material.get_shader_parameter(parameter) if material != null else null
	return float(value) if value is float or value is int else NAN


func _expect_off(lesson: ImaginedLesson, when: String) -> void:
	_check.expect(not lesson.is_active(), "The imagined lesson is active %s." % when)
	_check.expect(not lesson.visible, "The imagined lesson is visible %s." % when)
	_check.expect(
		lesson.process_mode == Node.PROCESS_MODE_DISABLED,
		"The imagined lesson is processing %s." % when
	)
	_check.expect(
		not (lesson.get_node(^"Wave") as CanvasLayer).visible,
		"The screen filter is shown %s." % when
	)
	_check.expect(
		is_zero_approx(lesson.get_dream()), "The dream is %.2f %s." % [lesson.get_dream(), when]
	)


func _check_figures(lesson: ImaginedLesson, seat: Vector3) -> void:
	var figures := lesson.get_figures()
	_check.expect(
		figures.size() == 3,
		"Expected the lead and two after-images, found %d figures." % figures.size()
	)
	var motion := load(MOTION) as AnimationLibrary
	for index in figures.size():
		var figure := figures[index]
		var echo := index > 0
		_check.expect(
			figure.scene_file_path == "res://assets/models/teacher_b/teacher_b.glb",
			"Figure %d is not the shipped teacher_b.glb ('%s')." % [index, figure.scene_file_path]
		)
		_check.expect(
			figure.find_children("*", "Skeleton3D", true, false).size() == 1,
			"Figure %d has no single skeleton." % index
		)
		var player := figure.get_node_or_null(^"Motion") as AnimationPlayer
		_check.expect(
			player != null and player.get_animation_library(ImaginedLesson.LIBRARY) == motion,
			"Figure %d does not hold the shipped motion library." % index
		)
		var meshes := figure.find_children("*", "MeshInstance3D", true, false)
		_check.expect(
			meshes.size() == 13,
			"Figure %d has %d meshes, not the GLB's 13." % [index, meshes.size()]
		)
		for node in meshes:
			var mesh := node as MeshInstance3D
			var material := mesh.material_override as ShaderMaterial
			var ink := material.next_pass as ShaderMaterial if material != null else null
			_check.expect(
				material != null and material.shader.resource_path == FIGURE_SHADER,
				"Figure %d's %s is not drawn by the dream shader." % [index, mesh.name]
			)
			_check.expect(
				ink != null and ink.shader.resource_path == INK_SHADER,
				"Figure %d's %s has no dream ink." % [index, mesh.name]
			)
			if material == null:
				continue
			_check.expect(
				is_equal_approx(_param(material, &"echo"), 1.0 if echo else 0.0),
				"Figure %d's %s has the wrong echo setting." % [index, mesh.name]
			)
			_check.expect(
				(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF) == echo,
				"Figure %d's %s has the wrong shadow setting." % [index, mesh.name]
			)
	if figures.is_empty():
		return
	var lead := figures[0]
	_check.expect(
		lead.scale.x > 1.2, "The lead figure is not larger than life (scale %.2f)." % lead.scale.x
	)
	var at := lead.global_position
	_check.expect(
		absf(at.x) < 6.0 and at.z > -4.6 and at.z < 4.6 and absf(at.y) < 0.2,
		"The lead figure stands outside the room (%s)." % str(at)
	)
	var forward := -lead.global_basis.z
	forward.y = 0.0
	var to_seat := seat - at
	to_seat.y = 0.0
	_check.expect(
		forward.normalized().dot(to_seat.normalized()) > 0.95,
		"The lead figure does not face the protagonist's seat."
	)


func _check_filter(lesson: ImaginedLesson) -> void:
	var layer := lesson.get_node_or_null(^"Wave") as CanvasLayer
	var filter := lesson.get_node_or_null(^"Wave/Filter") as ColorRect
	_check.expect(layer != null and filter != null, "The imagined lesson has no Wave/Filter.")
	if layer == null or filter == null:
		return
	_check.expect(
		layer.layer < 1, "The filter's layer (%d) is not under the game UI's (1)." % layer.layer
	)
	_check.expect(
		filter.mouse_filter == Control.MOUSE_FILTER_IGNORE, "The filter would take mouse input."
	)
	var material := filter.material as ShaderMaterial
	_check.expect(
		material != null and material.shader.resource_path == WAVE_SHADER,
		"The filter is not drawn by munch_wave.gdshader."
	)
	if material != null:
		_check.expect(
			material.shader.get_mode() == Shader.MODE_CANVAS_ITEM,
			"The filter is not a canvas item shader."
		)
		_check.expect(
			"hint_screen_texture" in material.shader.code,
			"The filter does not read the screen texture."
		)
		_check.expect(
			not ("hint_depth_texture" in material.shader.code), "The filter needs a depth buffer."
		)


func _figure_materials(lesson: ImaginedLesson) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for figure in lesson.get_figures():
		for node in figure.find_children("*", "MeshInstance3D", true, false):
			var material := (node as MeshInstance3D).material_override as ShaderMaterial
			if material != null and not result.has(material):
				result.append(material)
	return result
