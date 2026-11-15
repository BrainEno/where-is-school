extends SceneTree
## Headless check of `tests/clock_reading.gd`, the reader `capture_classroom_clock.gd` uses to
## say what time the classroom clock shows in a rendered frame (#173).
##
## The capture can only run with a real renderer, and a reader that is only ever run on the
## frame it is meant to pass proves little. So this test draws its own dials - front-on,
## seen at an angle, and as small as the clock is from the aisle - with hands at known
## angles, and checks that the reader:
##
## 1. turns hand angles into the time a person would read (`reading()`), and back;
## 2. finds each hand in a pair of frames to within a degree or two, wherever it points,
##    including on a dial foreshortened into an ellipse;
## 3. refuses what is not a readable hand: a hand that is not there, one too faint to tell
##    from the dial, a smudge around the pivot, an edge-on dial, frames of different sizes;
## 4. ignores changes outside the dial's rim, so something moving elsewhere in the room
##    cannot be read as a hand;
## 5. reads a hand node in the scene the way the pixels are read (`scene_hand_degrees()`),
##    including from behind, where nine and three trade places;
## 6. reads nine o'clock off the classroom's own clock nodes.

const Harness = preload("res://tests/test_harness.gd")
const ClockReading = preload("res://tests/clock_reading.gd")

const BACKGROUND := Color(0.32, 0.34, 0.33)
const DIAL := Color(0.93, 0.9, 0.82)
const TICK := Color(0.2, 0.2, 0.22)
const INK := Color(0.08, 0.08, 0.1)

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	Harness.arm_watchdog(self, 120.0, "clock_reading_test.gd")
	call_deferred("_run")


func _run() -> void:
	_check_reading()
	_check_front_on()
	_check_foreshortened()
	_check_small()
	_check_refusals()
	_check_outside_the_rim()
	_check_scene_hands()
	await _check_classroom_clock()
	Harness.finish(self, _failures, "%d clock-reading checks." % _checks)


# --- 1. angles and times ------------------------------------------------------------


func _check_reading() -> void:
	for case: Array in [
		[270.0, 0.0, "9:00"],
		[90.0, 0.0, "3:00"],
		[0.0, 0.0, "12:00"],
		[0.0, 359.0, "12:00"],
		[272.5, 30.0, "9:05"],
		[285.0, 180.0, "9:30"],
		[7.5, 90.0, "12:15"],
		# A minute hand a few degrees short of twelve still reads the hour it is about to be.
		[269.6, 355.0, "8:59"],
	]:
		var shown := ClockReading.reading(case[0], case[1])
		_expect(
			String(shown["text"]) == String(case[2]),
			"hands at %.1f / %.1f read %s, expected %s" % [case[0], case[1], shown["text"], case[2]]
		)
	var nine := ClockReading.hand_degrees_at(540.0)
	_expect(is_equal_approx(float(nine["hour"]), 270.0), "nine o'clock puts the hour hand at %s" % nine["hour"])
	_expect(is_equal_approx(float(nine["minute"]), 0.0), "nine o'clock puts the minute hand at %s" % nine["minute"])
	var round_trip := ClockReading.reading(float(nine["hour"]), float(nine["minute"]))
	_expect(int(round_trip["minutes"]) == 540, "nine o'clock reads back as %s minutes" % round_trip["minutes"])
	_expect(is_equal_approx(ClockReading.degrees_off(359.0, 1.0), 2.0), "359 and 1 degrees are 2 apart")
	_expect(is_equal_approx(ClockReading.degrees_off(90.0, 270.0), 180.0), "opposite directions are 180 apart")
	_expect(String(ClockReading.reading(NAN, 0.0)["text"]) == "?", "a missing hand reads as nothing")


# --- 2. hands found in drawn frames -------------------------------------------------


func _check_front_on() -> void:
	var size := Vector2i(800, 640)
	var centre := Vector2(400.5, 320.5)
	var twelve := Vector2(0.0, -280.0)
	var three := Vector2(280.0, 0.0)
	for minutes: float in [540.0, 0.0, 135.0, 400.0, 705.0]:
		var hands := ClockReading.hand_degrees_at(minutes)
		var hour := _measure(size, centre, twelve, three, float(hands["hour"]), 0.5, 0.06)
		var minute := _measure(size, centre, twelve, three, float(hands["minute"]), 0.82, 0.035)
		var label := "front-on dial at %s" % ClockReading.reading(float(hands["hour"]), float(hands["minute"]))["text"]
		_expect_hand(label + ", hour hand", hour, float(hands["hour"]), 1.0)
		_expect_hand(label + ", minute hand", minute, float(hands["minute"]), 1.0)
		if bool(hour["ok"]) and bool(minute["ok"]):
			var shown := ClockReading.reading(float(hour["degrees"]), float(minute["degrees"]))
			_expect(
				int(shown["minutes"]) == int(minutes) % 720,
				"%s reads %s off the pixels" % [label, shown["text"]]
			)
			_expect(
				float(minute["length"]) > float(hour["length"]) * 1.3,
				"%s: the minute hand measures %.2f, the hour hand %.2f" % [label, minute["length"], hour["length"]]
			)
			_expect(absf(float(minute["length"]) - 0.82) < 0.04, "%s: the minute hand's reach is %.3f" % [label, minute["length"]])
			_expect(float(hour["concentration"]) > 0.95, "%s: the hour hand reads as a line (%.3f)" % [label, hour["concentration"]])
			_expect(float(minute["contrast"]) > 0.6, "%s: ink on ivory has contrast %.2f" % [label, minute["contrast"]])
			_expect(
				absf(float(minute["length_px"]) - 0.82 * 280.0) < 12.0,
				"%s: the minute hand is %.1f px long" % [label, minute["length_px"]]
			)


func _check_foreshortened() -> void:
	# The dial seen from below and to the side: twelve leans right, three dips, and the face
	# is an ellipse half as tall as it is wide. The reading is still the dial's.
	var size := Vector2i(900, 700)
	var centre := Vector2(450.0, 350.0)
	var twelve := Vector2(60.0, -130.0)
	var three := Vector2(250.0, 40.0)
	for minutes: float in [540.0, 200.0, 610.0]:
		var hands := ClockReading.hand_degrees_at(minutes)
		var hour := _measure(size, centre, twelve, three, float(hands["hour"]), 0.5, 0.07)
		var minute := _measure(size, centre, twelve, three, float(hands["minute"]), 0.8, 0.045)
		_expect_hand("foreshortened dial, hour hand at %d min" % int(minutes), hour, float(hands["hour"]), 2.0)
		_expect_hand("foreshortened dial, minute hand at %d min" % int(minutes), minute, float(hands["minute"]), 2.0)
	# Read naively off the screen, as if the ellipse were a circle, the minute hand of this
	# nine o'clock leans well past twelve: the dial's own axes are what make the reading right.
	var upright := _measure(size, centre, twelve, three, 0.0, 0.8, 0.045)
	var naive := ClockReading.measure_hand(
		_dial_frame(size, centre, twelve, three), _hand_frame(size, centre, twelve, three, 0.0, 0.8, 0.045, INK),
		centre, Vector2(0.0, -140.0), Vector2(140.0, 0.0)
	)
	_expect(
		bool(upright["ok"]) and bool(naive["ok"]) and ClockReading.degrees_off(float(naive["degrees"]), 0.0) > 15.0,
		"reading the ellipse as a circle should have been visibly wrong (got %.1f)" % float(naive["degrees"])
	)


func _check_small() -> void:
	# About the size the clock is from the aisle: a face 40 px across.
	var size := Vector2i(160, 120)
	var centre := Vector2(80.0, 60.0)
	var twelve := Vector2(2.0, -20.0)
	var three := Vector2(20.0, 1.0)
	var hour := _measure(size, centre, twelve, three, 270.0, 0.55, 0.12)
	var minute := _measure(size, centre, twelve, three, 0.0, 0.85, 0.09)
	_expect_hand("40 px dial, hour hand", hour, 270.0, 12.0)
	_expect_hand("40 px dial, minute hand", minute, 0.0, 12.0)
	if bool(hour["ok"]) and bool(minute["ok"]):
		_expect(
			String(ClockReading.reading(float(hour["degrees"]), float(minute["degrees"]))["text"]) == "9:00",
			"the 40 px dial does not read nine"
		)
		_expect(float(minute["length_px"]) > float(hour["length_px"]), "on the 40 px dial the minute hand is not the longer")


# --- 3. what is not a readable hand -------------------------------------------------


func _check_refusals() -> void:
	var size := Vector2i(400, 400)
	var centre := Vector2(200.0, 200.0)
	var twelve := Vector2(0.0, -150.0)
	var three := Vector2(150.0, 0.0)
	var dial := _dial_frame(size, centre, twelve, three)

	var missing := ClockReading.measure_hand(dial, _dial_frame(size, centre, twelve, three), centre, twelve, three)
	_expect(not bool(missing["ok"]) and int(missing["pixels"]) == 0, "a hand that is not drawn was found")

	# Ink only a few levels off the dial: there, but nobody reads it.
	var faint := DIAL.darkened(0.04)
	var ghost := ClockReading.measure_hand(
		dial, _hand_frame(size, centre, twelve, three, 270.0, 0.5, 0.06, faint), centre, twelve, three
	)
	_expect(not bool(ghost["ok"]), "a hand the colour of the dial was read (contrast %.3f)" % float(ghost["contrast"]))

	# A smudge around the pivot has pixels but no direction.
	var smudge := dial.duplicate() as Image
	_paint_dial_space(smudge, centre, twelve, three, func(a: float, b: float) -> bool: return a * a + b * b < 0.35 * 0.35, INK)
	var blob := ClockReading.measure_hand(dial, smudge, centre, twelve, three)
	_expect(
		int(blob["pixels"]) > 0 and float(blob["concentration"]) < 0.2,
		"a smudge round the pivot reads as a line (concentration %.3f)" % float(blob["concentration"])
	)

	var edge_on := ClockReading.measure_hand(dial, dial, centre, Vector2(0.0, -150.0), Vector2(0.0, -149.5))
	_expect(not bool(edge_on["ok"]) and String(edge_on["error"]).contains("edge-on"), "an edge-on dial was read")

	var other := Image.create_empty(200, 200, false, Image.FORMAT_RGB8)
	var mismatched := ClockReading.measure_hand(dial, other, centre, twelve, three)
	_expect(not bool(mismatched["ok"]) and String(mismatched["error"]).contains("frames are"), "frames of two sizes were compared")

	var nothing := ClockReading.measure_hand(null, dial, centre, twelve, three)
	_expect(not bool(nothing["ok"]), "a missing frame was read")

	# The wrong time is read as the wrong time, not rounded towards the right one.
	var hands := ClockReading.hand_degrees_at(15.0)
	var hour := _measure(size, centre, twelve, three, float(hands["hour"]), 0.5, 0.06)
	var minute := _measure(size, centre, twelve, three, float(hands["minute"]), 0.8, 0.04)
	if bool(hour["ok"]) and bool(minute["ok"]):
		var shown := ClockReading.reading(float(hour["degrees"]), float(minute["degrees"]))
		_expect(String(shown["text"]) == "12:15", "a quarter past twelve reads as %s" % shown["text"])
		_expect(
			ClockReading.degrees_off(float(minute["degrees"]), 0.0) > 80.0,
			"a quarter past twelve's minute hand is %.1f degrees off twelve" % ClockReading.degrees_off(float(minute["degrees"]), 0.0)
		)
	else:
		_failures.append("the quarter-past-twelve hands were not found: %s / %s" % [hour["error"], minute["error"]])


# --- 4. outside the rim -------------------------------------------------------------


func _check_outside_the_rim() -> void:
	var size := Vector2i(500, 400)
	var centre := Vector2(250.0, 200.0)
	var twelve := Vector2(0.0, -120.0)
	var three := Vector2(120.0, 0.0)
	var dial := _dial_frame(size, centre, twelve, three)
	var alone := _hand_frame(size, centre, twelve, three, 0.0, 0.8, 0.05, INK)
	var busy := alone.duplicate() as Image
	# A bright moving thing just outside the rim, right where the hour hand would point at three.
	busy.fill_rect(Rect2i(int(centre.x) + 130, int(centre.y) - 30, 90, 60), Color(1.0, 0.2, 0.1))
	var clean := ClockReading.measure_hand(dial, alone, centre, twelve, three)
	var noisy := ClockReading.measure_hand(dial, busy, centre, twelve, three)
	_expect(
		bool(noisy["ok"]) and int(noisy["pixels"]) == int(clean["pixels"]),
		"a change outside the dial was counted as the hand (%d against %d pixels)" % [noisy["pixels"], clean["pixels"]]
	)
	_expect_hand("minute hand with the room moving outside the rim", noisy, 0.0, 1.0)
	var settled := ClockReading.dial_change(dial, busy.duplicate() as Image, centre, twelve, three)
	_expect(int(settled["pixels"]) == int(clean["pixels"]), "dial_change counted pixels outside the dial")


# --- 5. scene hands -----------------------------------------------------------------


func _check_scene_hands() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var cases := [
		# pivot z rotation, hand offset along local Y, expected degrees seen from the front.
		[90.0, 0.05, 270.0],
		[0.0, 0.08, 0.0],
		[-90.0, 0.05, 90.0],
		[180.0, 0.05, 180.0],
		# A hand hung on the other side of its pivot points the other way.
		[90.0, -0.05, 90.0],
	]
	for case: Array in cases:
		var pivot := Node3D.new()
		pivot.rotation_degrees = Vector3(0.0, 0.0, case[0])
		var hand := Node3D.new()
		hand.position = Vector3(0.0, case[1], 0.0)
		pivot.add_child(hand)
		holder.add_child(pivot)
		var seen := ClockReading.scene_hand_degrees(hand, absf(case[1]) * 2.0, Vector3.ZERO, Vector3.UP, Vector3.BACK)
		_expect(
			ClockReading.degrees_off(seen, case[2]) < 0.01,
			"a hand on a pivot turned %.0f degrees reads %.2f, expected %.0f" % [case[0], seen, case[2]]
		)
		# From behind the wall the same hand points the mirror way: nine becomes three.
		var behind := ClockReading.scene_hand_degrees(hand, absf(case[1]) * 2.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
		_expect(
			ClockReading.degrees_off(behind, fposmod(360.0 - float(case[2]), 360.0)) < 0.01,
			"seen from behind, a hand at %.0f reads %.2f" % [case[2], behind]
		)
		pivot.queue_free()
	var centred := Node3D.new()
	holder.add_child(centred)
	_expect(
		is_nan(ClockReading.scene_hand_degrees(centred, 0.0, Vector3.ZERO, Vector3.UP, Vector3.BACK)),
		"a hand with no length has a direction"
	)
	holder.queue_free()


# --- 6. the classroom's clock -------------------------------------------------------


func _check_classroom_clock() -> void:
	var packed := load("res://scenes/locations/classroom/classroom.tscn") as PackedScene
	if packed == null:
		_failures.append("the classroom scene does not load")
		return
	var room := packed.instantiate() as Node3D
	root.add_child(room)
	await process_frame
	var dial := room.get_node_or_null(^"WallNorth/FrontWallDressing/ClockDial") as Node3D
	var hour := room.get_node_or_null(^"ClockHourPivot/ClockHandHour") as MeshInstance3D
	var minute := room.get_node_or_null(^"ClockMinutePivot/ClockHandMinute") as MeshInstance3D
	if dial == null or hour == null or minute == null or not hour.mesh is BoxMesh or not minute.mesh is BoxMesh:
		_failures.append("the classroom clock is not a dial with two box hands any more")
		room.queue_free()
		return
	var basis := dial.global_transform.basis
	# Out of the face is the side the hands are on.
	var normal := basis.z.normalized()
	if (minute.global_position - dial.global_position).dot(normal) < 0.0:
		normal = -normal
	var hour_degrees := ClockReading.scene_hand_degrees(
		hour, (hour.mesh as BoxMesh).size.y, dial.global_position, basis.y, normal
	)
	var minute_degrees := ClockReading.scene_hand_degrees(
		minute, (minute.mesh as BoxMesh).size.y, dial.global_position, basis.y, normal
	)
	var shown := ClockReading.reading(hour_degrees, minute_degrees)
	_expect(
		String(shown["text"]) == "9:00",
		"the classroom clock's nodes read %s (hour %.1f, minute %.1f); Q's class is at nine"
		% [shown["text"], hour_degrees, minute_degrees]
	)
	print("CLOCK_READING classroom nodes read %s (hour %.2f, minute %.2f)" % [shown["text"], hour_degrees, minute_degrees])
	room.queue_free()
	await process_frame


# --- drawing ------------------------------------------------------------------------


func _measure(
	size: Vector2i, centre: Vector2, twelve: Vector2, three: Vector2,
	degrees: float, length: float, width: float
) -> Dictionary:
	return ClockReading.measure_hand(
		_dial_frame(size, centre, twelve, three),
		_hand_frame(size, centre, twelve, three, degrees, length, width, INK),
		centre, twelve, three
	)


## A dial with twelve tick marks on a grey wall: the same in every frame of a pair, so the
## ticks must cancel out of the reading.
func _dial_frame(size: Vector2i, centre: Vector2, twelve: Vector2, three: Vector2) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGB8)
	image.fill(BACKGROUND)
	_paint_dial_space(image, centre, twelve, three, func(a: float, b: float) -> bool: return a * a + b * b <= 1.0, DIAL)
	var on_a_tick := func(a: float, b: float) -> bool:
		var rho := sqrt(a * a + b * b)
		if rho < 0.86 or rho > 0.97:
			return false
		var angle := fposmod(rad_to_deg(atan2(a, b)), 30.0)
		return angle < 2.0 or angle > 28.0
	_paint_dial_space(image, centre, twelve, three, on_a_tick, TICK)
	return image


func _hand_frame(
	size: Vector2i, centre: Vector2, twelve: Vector2, three: Vector2,
	degrees: float, length: float, width: float, colour: Color
) -> Image:
	var image := _dial_frame(size, centre, twelve, three)
	var along := Vector2(sin(deg_to_rad(degrees)), cos(deg_to_rad(degrees)))
	var on_the_hand := func(a: float, b: float) -> bool:
		var point := Vector2(a, b)
		var t := point.dot(along)
		var side := absf(point.dot(Vector2(along.y, -along.x)))
		return t >= -0.04 and t <= length and side <= width * 0.5
	_paint_dial_space(image, centre, twelve, three, on_the_hand, colour)
	return image


## Paints every pixel whose centre, mapped into dial coordinates, satisfies `inside`.
func _paint_dial_space(
	image: Image, centre: Vector2, twelve: Vector2, three: Vector2, inside: Callable, colour: Color
) -> void:
	var determinant := three.x * twelve.y - twelve.x * three.y
	var reach := maxf(twelve.length(), three.length()) * 1.1 + 2.0
	for y in range(maxi(0, int(centre.y - reach)), mini(image.get_height(), int(centre.y + reach) + 1)):
		for x in range(maxi(0, int(centre.x - reach)), mini(image.get_width(), int(centre.x + reach) + 1)):
			var offset := Vector2(float(x) + 0.5, float(y) + 0.5) - centre
			var a := (offset.x * twelve.y - twelve.x * offset.y) / determinant
			var b := (three.x * offset.y - offset.x * three.y) / determinant
			if bool(inside.call(a, b)):
				image.set_pixel(x, y, colour)


func _expect_hand(label: String, measured: Dictionary, wanted: float, slack: float) -> void:
	_checks += 1
	if not bool(measured["ok"]):
		_failures.append("%s was not found: %s" % [label, measured["error"]])
		return
	var off := ClockReading.degrees_off(float(measured["degrees"]), wanted)
	if off > slack:
		_failures.append(
			"%s reads %.2f degrees, %.2f off the %.1f it was drawn at (slack %.1f)"
			% [label, measured["degrees"], off, wanted, slack]
		)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
