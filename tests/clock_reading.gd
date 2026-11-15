extends RefCounted
## Reads the time a wall clock shows, from the scene and from a rendered frame (#173).
##
## Issue #173 asked for the classroom clock to read about nine, because Q says biology starts
## at nine. PR #176 turned the hands and `classroom_visual_slice` reads the transforms; what
## nobody had shown is that the **picture** reads nine - that a player looking at the frame
## sees the minute hand on the twelve and the hour hand on the nine, and that the hands stand
## out from the dial enough to be read at all. This file is that reading, shared by
## `tests/capture_classroom_clock.gd` (real renderer) and `tests/clock_reading_test.gd`
## (headless, on frames it draws itself, so every way of failing is exercised):
##
## - `scene_hand_degrees()` - where a hand points according to its node: the hand's outer tip
##   minus the dial's centre, measured in the dial's own plane.
## - `measure_hand()` - where a hand points according to the pixels. The caller renders the
##   same view twice, once without the hand and once with only that hand, so the hand's pixels
##   are exactly the ones that differ: nothing painted on the dial, no tick mark and no shadow
##   of the room can be mistaken for it. Each differing pixel inside the dial is mapped back
##   into dial coordinates through the projected twelve-o'clock and three-o'clock radii, so a
##   dial seen at an angle is read as the dial, not as the ellipse on the screen.
## - `reading()` - the two hand angles as `H:MM`, the way a person reads them.
##
## Angles are degrees clockwise from twelve, as seen from in front of the dial.

## A pixel belongs to the hand when one of its channels moved by at least this much (0..1)
## between the frame without the hand and the frame with it.
const DEFAULT_THRESHOLD := 0.12
## Pixels this far outside the dial's rim (as a fraction of its radius) are ignored: whatever
## changes there is not a hand.
const RIM := 1.05
## Pixels this close to the pivot (fraction of the radius) say nothing about direction - both
## hands cover them - and are left out of the direction, not out of the count.
const HUB := 0.12


## Degrees clockwise from twelve that `hand` points, given the box's length along its local Y
## and the dial's centre and orientation (`dial_up` is twelve o'clock, `dial_normal` points
## out of the face towards whoever reads it). NAN when the hand has no direction to read.
static func scene_hand_degrees(
	hand: Node3D, length: float, centre: Vector3, dial_up: Vector3, dial_normal: Vector3
) -> float:
	var up := dial_up.normalized()
	var normal := dial_normal.normalized()
	# Facing the dial (looking along -normal) with twelve at the top, three is to the right.
	var right := up.cross(normal).normalized()
	var inner := hand.global_transform * Vector3(0.0, -length * 0.5, 0.0)
	var outer := hand.global_transform * Vector3(0.0, length * 0.5, 0.0)
	# The tip that is further from the centre is the one a player reads.
	var tip := outer if (outer - centre).length() >= (inner - centre).length() else inner
	var offset := tip - centre
	var along_right := offset.dot(right)
	var along_up := offset.dot(up)
	if Vector2(along_right, along_up).length() < 1e-4:
		return NAN
	return fposmod(rad_to_deg(atan2(along_right, along_up)), 360.0)


## Where a hand points in a rendered frame.
##
## `without` is the view with this hand hidden and `with_hand` the same view with only this
## hand shown (same camera, same frame of the room). `centre` is the dial's centre on screen,
## `twelve` and `three` the screen offsets from it to the rim at twelve and at three o'clock.
## Returns `{ok, error, pixels, degrees, length, length_px, contrast, concentration}`:
## - `degrees`: clockwise from twelve, from the hand's pixels weighted by how far out they lie;
## - `length`: how far out the hand reaches, as a fraction of the dial's radius (97th
##   percentile of its pixels, so one stray pixel does not lengthen it);
## - `length_px`: the same reach in screen pixels, along the hand's own direction;
## - `contrast`: how much the hand's pixels differ from the dial behind them (0..1);
## - `concentration`: 1.0 for pixels that all lie in one direction from the centre, near 0 for
##   a blob around it - a hand that is a line, not a smudge.
static func measure_hand(
	without: Image,
	with_hand: Image,
	centre: Vector2,
	twelve: Vector2,
	three: Vector2,
	threshold: float = DEFAULT_THRESHOLD
) -> Dictionary:
	var result := {
		"ok": false, "error": "", "pixels": 0, "degrees": NAN, "length": 0.0,
		"length_px": 0.0, "contrast": 0.0, "concentration": 0.0,
	}
	if without == null or with_hand == null or without.is_empty() or with_hand.is_empty():
		result["error"] = "a frame is missing"
		return result
	if without.get_size() != with_hand.get_size():
		result["error"] = "the two frames are %s and %s" % [without.get_size(), with_hand.get_size()]
		return result
	# Screen offset = a * three + b * twelve, with (a, b) the dial coordinates: a towards three,
	# b towards twelve, both 1.0 at the rim.
	var determinant := three.x * twelve.y - twelve.x * three.y
	if absf(determinant) < 1.0:
		result["error"] = "the dial is edge-on or smaller than a pixel on screen"
		return result
	var base := _rgb(without)
	var lit := _rgb(with_hand)
	var width := base.get_width()
	var height := base.get_height()
	var base_bytes := base.get_data()
	var lit_bytes := lit.get_data()
	var reach := maxf(twelve.length(), three.length()) * RIM + 1.0
	var x0 := clampi(int(floor(centre.x - reach)), 0, width - 1)
	var x1 := clampi(int(ceil(centre.x + reach)), 0, width - 1)
	var y0 := clampi(int(floor(centre.y - reach)), 0, height - 1)
	var y1 := clampi(int(ceil(centre.y + reach)), 0, height - 1)
	var sum_a := 0.0
	var sum_b := 0.0
	var sum_weight := 0.0
	var contrast_total := 0.0
	var reaches := PackedFloat32Array()
	var pixels := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var at := (y * width + x) * 3
			var change := maxf(
				absf(float(lit_bytes[at]) - float(base_bytes[at])),
				maxf(
					absf(float(lit_bytes[at + 1]) - float(base_bytes[at + 1])),
					absf(float(lit_bytes[at + 2]) - float(base_bytes[at + 2]))
				)
			) / 255.0
			if change < threshold:
				continue
			var offset := Vector2(float(x) + 0.5, float(y) + 0.5) - centre
			var a := (offset.x * twelve.y - twelve.x * offset.y) / determinant
			var b := (three.x * offset.y - offset.x * three.y) / determinant
			var rho := sqrt(a * a + b * b)
			if rho > RIM:
				continue
			pixels += 1
			contrast_total += change
			reaches.append(rho)
			if rho < HUB:
				continue
			var weight := change * rho
			sum_a += weight * a / rho
			sum_b += weight * b / rho
			sum_weight += weight
	result["pixels"] = pixels
	if pixels == 0 or sum_weight <= 0.0:
		result["error"] = "no pixel of the hand differs from the dial behind it"
		return result
	reaches.sort()
	var length := reaches[mini(reaches.size() - 1, int(floor(reaches.size() * 0.97)))]
	var degrees := fposmod(rad_to_deg(atan2(sum_a, sum_b)), 360.0)
	var direction := Vector2(sin(deg_to_rad(degrees)), cos(deg_to_rad(degrees)))
	result["ok"] = true
	result["degrees"] = degrees
	result["length"] = length
	result["length_px"] = (three * direction.x + twelve * direction.y).length() * length
	result["contrast"] = contrast_total / float(pixels)
	result["concentration"] = Vector2(sum_a, sum_b).length() / sum_weight
	return result


## The largest change (0..1) between two frames inside the dial, and how many pixels moved by
## at least `threshold`: two renders of the same view that differ here were not of the same
## moment, and a hand read from them would be read off something else.
static func dial_change(
	first: Image,
	second: Image,
	centre: Vector2,
	twelve: Vector2,
	three: Vector2,
	threshold: float = DEFAULT_THRESHOLD
) -> Dictionary:
	var probe := measure_hand(first, second, centre, twelve, three, threshold)
	return {"pixels": int(probe["pixels"]), "error": String(probe["error"])}


## The hands as a person reads them: `{hour, minute, minutes, text}`. The minute hand gives
## the minutes; the hour hand, less the half degree a minute it has crept on, gives the hour.
static func reading(hour_degrees: float, minute_degrees: float) -> Dictionary:
	if is_nan(hour_degrees) or is_nan(minute_degrees):
		return {"hour": 0, "minute": 0, "minutes": -1, "text": "?"}
	var minute := int(round(fposmod(minute_degrees, 360.0) / 6.0)) % 60
	var hour := int(round(fposmod(hour_degrees - minute * 0.5, 360.0) / 30.0)) % 12
	var shown_hour := 12 if hour == 0 else hour
	return {
		"hour": shown_hour,
		"minute": minute,
		"minutes": hour * 60 + minute,
		"text": "%d:%02d" % [shown_hour, minute],
	}


## Where each hand of a twelve-hour clock stands at `minutes` past twelve.
static func hand_degrees_at(minutes: float) -> Dictionary:
	return {
		"hour": fposmod(minutes * 0.5, 360.0),
		"minute": fposmod(minutes * 6.0, 360.0),
	}


## The angle between two directions, 0..180.
static func degrees_off(measured: float, wanted: float) -> float:
	if is_nan(measured) or is_nan(wanted):
		return INF
	return absf(fposmod(measured - wanted + 180.0, 360.0) - 180.0)


static func _rgb(image: Image) -> Image:
	if image.get_format() == Image.FORMAT_RGB8:
		return image
	var copy := image.duplicate() as Image
	copy.convert(Image.FORMAT_RGB8)
	return copy
