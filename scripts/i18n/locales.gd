class_name Locales
extends RefCounted
## The supported languages and their reading speeds. Add a profile here and provide
## its content under data/locale, data/dialogue and data/inspections.

const DEFAULT_LOCALE := "en"
const DEFAULT_READING_CPS := 18.0
const PROFILES := {
	"en": {"reading_cps": 22.0, "prefixes": ["en"], "aliases": []},
	"zh-CN": {"reading_cps": 8.0, "prefixes": ["zh"], "aliases": ["cn"]},
}


## Dictionary insertion order also defines the display/toggle and reference order.
static func codes(profiles: Dictionary = PROFILES) -> Array[String]:
	var result: Array[String] = []
	for code: Variant in profiles.keys():
		result.append(String(code))
	return result


## Exact codes take precedence over aliases (important when adding related locales).
static func normalize(locale: String, profiles: Dictionary = PROFILES) -> String:
	var code := locale.strip_edges()
	if profiles.has(code):
		return code
	var lowered := code.to_lower()
	for candidate: String in codes(profiles):
		if lowered == candidate.to_lower():
			return candidate
	for candidate: String in codes(profiles):
		var profile: Dictionary = profiles[candidate]
		for alias: Variant in profile.get("aliases", []):
			if lowered == String(alias).to_lower():
				return candidate
		for prefix: Variant in profile.get("prefixes", []):
			if lowered.begins_with(String(prefix).to_lower()):
				return candidate
	return DEFAULT_LOCALE


## Unknown locales or profiles without a speed deliberately use the neutral fallback.
static func reading_cps(locale: String, profiles: Dictionary = PROFILES) -> float:
	var profile: Dictionary = profiles.get(locale, {})
	return float(profile.get("reading_cps", DEFAULT_READING_CPS))


## Compatibility view for callers that need the complete speed table.
static func reading_speeds(profiles: Dictionary = PROFILES) -> Dictionary:
	var speeds: Dictionary = {}
	for code: String in codes(profiles):
		speeds[code] = reading_cps(code, profiles)
	return speeds
