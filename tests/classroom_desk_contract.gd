extends RefCounted
## Expected layout shared by the placement, visual and playthrough checks.
## Keep the original twelve desk anchors. Each has exactly one companion 0.75 m away.

const ANCHORS := {
	"DeskA1": Vector3(-4.8, 0.0, -0.8),
	"DeskA2": Vector3(-1.6, 0.0, -0.8),
	"DeskA3": Vector3(1.6, 0.0, -0.8),
	"DeskA4": Vector3(4.8, 0.0, -0.8),
	"DeskB1": Vector3(-4.8, 0.0, 1.3),
	"DeskB2": Vector3(-1.6, 0.0, 1.3),
	"DeskB3": Vector3(1.6, 0.0, 1.3),
	"DeskB4": Vector3(4.8, 0.0, 1.3),
	"DeskC1": Vector3(-4.8, 0.0, 3.4),
	"DeskC2": Vector3(-1.6, 0.0, 3.4),
	"DeskC3": Vector3(1.6, 0.0, 3.4),
	"DeskC4": Vector3(4.8, 0.0, 3.4),
}
const PAIR_SPACING := 0.75


static func mate_of(anchor: String) -> String:
	return "DeskQ" if anchor == "DeskB2" else anchor + "Mate"


static func positions() -> Dictionary:
	var desks := ANCHORS.duplicate()
	for name: String in ANCHORS:
		var origin: Vector3 = ANCHORS[name]
		# Leave a standing area in front of the ordinary window beside A1.
		var toward := Vector3.RIGHT if name == "DeskA1" else Vector3.LEFT
		desks[mate_of(name)] = origin + toward * PAIR_SPACING
	return desks
