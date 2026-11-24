extends RefCounted
## Narrow, one-way compatibility for the retired two-voice registry (#280).
##
## Only known shipped check identities are relabelled. The saved dice, values,
## modifiers, totals, margins, success and seed are historical outcomes, not inputs
## to run through today's rules again. Node/rule ids deliberately do not change.
## This is not an alias table: the ability loader still refuses retired abilities.

const CHECK_ABILITIES := {
	&"check:voice_notice:vn_1": &"insight",
	&"check:voice_arrival:va_1": &"inference",
	&"check:voice_hoop:vh_1": &"scrutiny",
	&"check:pg_shed:ps_boundary_check": &"scrutiny",
	&"check:pg_shed:ps_ledger_check": &"scrutiny",
	&"check:pg_ball:pb_boundary_check": &"scrutiny",
	&"check:pg_ball:pb_ledger_check": &"inference",
	&"check:pg_roof_jump:prj_check": &"inference",
	&"check:q_after_dismissal:ad_square_check": &"echo",
	&"check:expected_b:e3_whimsy": &"imagination",
	&"check:classroom_curtain:cc_edges_check": &"scrutiny",
	&"check:classroom_curtain_void:cv_balance_check": &"scrutiny",
	&"check:classroom_rear_door_borrow:rdb_check": &"inference",
	&"check:align_archive:bearing": &"inference",
	&"check:align_plan_room:bearing": &"inference",
	&"check:align_projection_room:bearing": &"scrutiny",
	&"check:align_computer_room:bearing": &"inference",
	&"check:align_vacant_office:bearing": &"scrutiny",
	&"check:align_principal_office:bearing": &"inference",
}
## A failed hidden check still spent its passive rule. Its fired flag, not the
## success of its roll, identifies which new voice owns that historical use.
const PASSIVE_OWNERS := {
	&"alley_notice_orientation": &"insight",
	&"playground_arrival_orientation": &"inference",
	&"playground_hoop_orientation": &"scrutiny",
}


static func migrate_flags(snapshot: Dictionary) -> Dictionary:
	var flags := snapshot.duplicate(true)
	var old_count := &"voice_count:orientation"
	var had_orientation := flags.has(old_count)
	for record_flag: StringName in CHECK_ABILITIES:
		var stored: Variant = flags.get(record_flag, null)
		if not (stored is Dictionary):
			continue
		var record: Dictionary = stored
		var target: StringName = CHECK_ABILITIES[record_flag]
		var retired := "whimsy" if target == &"imagination" else "orientation"
		var old_ability: Variant = record.get("ability", "")
		if not (old_ability is String or old_ability is StringName):
			continue
		if String(old_ability) != retired:
			continue
		had_orientation = had_orientation or retired == "orientation"
		# Preserve the stored string kind as well as every unrelated field.
		record["ability"] = target if record["ability"] is StringName else String(target)
	if had_orientation:
		# Never copy the old aggregate to every voice, or add it to current counts:
		# either would spend allowances for voices that never spoke. A mixed save
		# keeps the greater of the current counter and the evidenced historical use.
		for rule_id: StringName in PASSIVE_OWNERS:
			if flags.get(StoryFlags.passive_fired_flag(rule_id), false) != true:
				continue
			var ability_id: StringName = PASSIVE_OWNERS[rule_id]
			var count_flag := StoryFlags.passive_count_flag(ability_id)
			flags[count_flag] = maxi(_count(flags.get(count_flag, 0)), 1)
	flags.erase(old_count)
	var old_fancy_count := &"voice_count:whimsy"
	if flags.has(old_fancy_count):
		var count_flag := StoryFlags.passive_count_flag(&"imagination")
		flags[count_flag] = maxi(_count(flags.get(count_flag, 0)), _count(flags[old_fancy_count]))
		flags.erase(old_fancy_count)
	return flags


static func _count(value: Variant) -> int:
	# Older decoded saves can contain integral floats; arbitrary flag values are
	# legal, but a Dictionary must never be fed to int() as if it were a counter.
	if value is int or value is float:
		return maxi(0, int(value))
	return 0
