extends RefCounted
## Limb keys for the protagonist's curtain and ladder beats. These are semantic offsets
## consumed by CharacterAnimation, not rotations of the model as a whole. Each row is
## [time, torso (lean, bank, nod), left leg, right leg, left arm, right arm]. Legs are
## (hip, knee, toe); arms are (shoulder, outward reach, elbow). Angles are in degrees.

const Z := Vector3.ZERO
const LEAN := [Vector3(29, -7, 19), Vector3(-29, 30, 1), Vector3(14, 11, 10),
	Vector3(-41, 27, -25), Vector3(-12, 41, -23)]
const GRIP := [Vector3(10, 0, -7), Vector3(-34, 49, -5), Vector3(-10, 28, -4),
	Vector3(-115, 13, -33), Vector3(-94, 16, -49)]


static func clips() -> Dictionary:
	var down: Array = [
		[0.0] + GRIP,
		[0.18, Vector3(12, 6, -12), Vector3(-32, 52, -2), Vector3(-20, 54, 5),
			Vector3(-119, 12, -46), Vector3(-66, 26, -67)],
		[0.40, Vector3(8, 4, 2), Vector3(-12, 26, -4), Vector3(-32, 43, 1),
			Vector3(-94, 16, -49), Vector3(-115, 13, -33)],
		[0.58] + _mirror(GRIP),
	]
	var other: Array = []
	for row: Array in down:
		other.append([row[0]] + _mirror(row.slice(1)))
	return {
		"curtain_reach": _clip([
			[0.0, Z, Z, Z, Z, Z],
			[0.38, Vector3(14, 2, 4), Z, Z, Vector3(-18, 12, -34), Vector3(-76, 6, -26)],
		]),
		"curtain_draw": _clip([
			[0.0, Vector3(14, 2, 4), Z, Z, Vector3(-18, 12, -34), Vector3(-76, 6, -26)],
			[0.28, Vector3(13, 9, 4), Vector3(-16, 22, -4), Vector3(3, 11, 2),
				Vector3(-15, 16, -24), Vector3(-72, 29, -26)],
			[0.68, Vector3(6, 10, -3), Vector3(-7, 8, -2), Vector3(-12, 16, 2),
				Vector3(-12, 16, -24), Vector3(-46, 48, -33)],
			[1.0, Z, Z, Z, Z, Z],
		]),
		"void_lean": _clip([
			[0.0, Z, Z, Z, Z, Z],
			[0.24, Vector3(8, -4, 4), Vector3(-35, 42, -8), Vector3(8, 8, 7),
				Vector3(-10, 17, -25), Vector3(-17, 24, -20)],
			[0.49, Vector3(17, -6, 8), Vector3(-20, 19, -6), Vector3(12, 12, 10),
				Vector3(-28, 22, -28), Vector3(-10, 29, -23)],
			[0.84] + LEAN,
		]),
		"void_recover": _clip([
			[0.0] + LEAN,
			[0.22, Vector3(-8, 8, -5), Vector3(-25, 40, -6), Vector3(-20, 27, -3),
				Vector3(-28, 54, -31), Vector3(-25, 51, -33)],
			[0.43, Vector3(4, 1, 4), Vector3(8, 22, 9), Vector3(-12, 16, -4),
				Vector3(-10, 17, -29), Vector3(-9, 19, -21)],
			[0.70, Z, Z, Z, Z, Z],
		]),
		"void_step": _clip([
			[0.0, Z, Z, Z, Z, Z],
			[0.19, Vector3(16, -2, 11), Vector3(-17, 31, 2), Vector3(-21, 38, 6),
				Vector3(18, 12, -22), Vector3(11, 15, -27)],
			[0.37, Vector3(9, 3, -5), Vector3(-40, 43, -7), Vector3(19, 20, 20),
				Vector3(-57, 20, -32), Vector3(-35, 29, -28)],
			[0.77, Vector3(12, 0, 10), Vector3(-18, 28, -3), Vector3(-14, 23, -4),
				Vector3(-42, 27, -33), Vector3(-39, 27, -33)],
		]),
		"void_slip": _clip([
			[0.0] + LEAN,
			[0.16, Vector3(10, 20, -10), Vector3(-5, 27, 25), Vector3(-35, 44, 8),
				Vector3(-79, 64, -26), Vector3(-45, 75, -12)],
			[0.38, Vector3(36, -17, 6), Vector3(-42, 59, -3), Vector3(26, 40, 12),
				Vector3(-105, 39, -41), Vector3(-62, 51, -43)],
			[0.73, Vector3(21, -12, -7), Vector3(-20, 39, 13), Vector3(-32, 48, 4),
				Vector3(-64, 34, -40), Vector3(-21, 42, -24)],
		]),
		"roof_brace": _clip([
			[0.0, Vector3(12, 0, 10), Vector3(-18, 28, -3), Vector3(-14, 23, -4),
				Vector3(-42, 27, -33), Vector3(-39, 27, -33)],
			[0.16, Vector3(9, 0, 12), Vector3(-9, 16, -3), Vector3(-9, 16, -3),
				Vector3(-36, 23, -19), Vector3(-35, 24, -20)],
			[0.30, Vector3(23, 0, 11), Vector3(-39, 63, -11), Vector3(-35, 59, -10),
				Vector3(-61, 21, -31), Vector3(-60, 22, -32)],
			[0.54, Vector3(8, 0, -4), Vector3(-15, 28, -6), Vector3(-15, 28, -6),
				Vector3(-20, 16, -32), Vector3(-18, 15, -25)],
			[0.84, Z, Z, Z, Z, Z],
		]),
		"roof_impact": _clip([
			[0.0, Vector3(21, -12, -7), Vector3(-20, 39, 13), Vector3(-32, 48, 4),
				Vector3(-64, 34, -40), Vector3(-21, 42, -24)],
			[0.22, Vector3(26, -12, 18), Vector3(-22, 44, -14), Vector3(-40, 36, 6),
				Vector3(-74, 21, -12), Vector3(-26, 32, -18)],
			[0.42, Vector3(58, -23, 12), Vector3(-60, 108, 18), Vector3(-78, 90, -8),
				Vector3(-12, 14, -14), Vector3(-35, 23, -37)],
			[0.72, Vector3(53, -21, 16), Vector3(-58, 104, 9), Vector3(-72, 85, -10),
				Vector3(-9, 18, -14), Vector3(-21, 22, -46)],
			[1.15, Vector3(16, 10, 15), Vector3(-30, 50, 9), Vector3(-36, 59, -7),
				Vector3(-18, 18, -35), Vector3(-35, 18, -43)],
			[1.55, Z, Z, Z, Z, Z],
		]),
		"ladder_mount": _clip([
			[0.0, Z, Z, Z, Z, Z],
			[0.30, Vector3(21, 0, 13), Vector3(-28, 51, -8), Vector3(-21, 39, -7),
				Vector3(-65, 28, -54), Vector3(-74, 24, -43)],
			[0.66, Vector3(16, 8, 12), Vector3(-27, 44, 3), Vector3(9, 31, 22),
				Vector3(-109, 15, -41), Vector3(-95, 19, -49)],
			[1.0] + GRIP,
		]),
		"ladder_right": _clip(down),
		"ladder_left": _clip(other),
		"ladder_dismount": _clip([
			[0.0] + _mirror(GRIP),
			[0.24, Vector3(6, 4, 8), Vector3(-10, 31, 3), Vector3(17, 24, 9),
				Vector3(-73, 19, -54), Vector3(-88, 19, -53)],
			[0.44, Vector3(-3, 0, -5), Vector3(-12, 26, -9), Vector3(-4, 9, -4),
				Vector3(-30, 18, -44), Vector3(-36, 16, -41)],
			[0.64, Z, Z, Z, Z, Z],
		]),
	}


static func _mirror(pose: Array) -> Array:
	var torso: Vector3 = pose[0]
	return [Vector3(torso.x, -torso.y, torso.z), pose[2], pose[1], pose[4], pose[3]]


static func _clip(frames: Array) -> Dictionary:
	var tracks: Dictionary = {}
	for frame: Array in frames:
		var time := float(frame[0])
		var torso: Vector3 = frame[1]
		_key(tracks, "spine", time, Vector3(torso.x * 0.74, 0, torso.y))
		_key(tracks, "chest", time, Vector3(torso.x * 0.26, 0, torso.y * 0.22))
		_key(tracks, "head", time, Vector3(torso.z, 0, -torso.y * 0.3))
		for side in 2:
			var suffix := ".L" if side == 0 else ".R"
			var sign_z := 1.0 if side == 0 else -1.0
			var leg: Vector3 = frame[2 + side]
			var arm: Vector3 = frame[4 + side]
			_key(tracks, "thigh" + suffix, time, Vector3(leg.x, 0, 3.0 * sign_z))
			_key(tracks, "shin" + suffix, time, Vector3(leg.y, 0, 0))
			_key(tracks, "foot" + suffix, time, Vector3(leg.z, 0, 0))
			_key(tracks, "upper_arm" + suffix, time, Vector3(arm.x, 0, arm.y * sign_z))
			_key(tracks, "fore_arm" + suffix, time, Vector3(arm.z, 0, 0))
	return {"length": float(frames.back()[0]), "tracks": tracks, "loop": false}


static func _key(tracks: Dictionary, bone: String, time: float, value: Vector3) -> void:
	if not tracks.has(bone):
		tracks[bone] = []
	tracks[bone].append([time, value])
