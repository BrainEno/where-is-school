class_name CharacterProfile
extends Resource
## Display identity for a speaker. Text content lives in data files and refers
## to characters by `character_id`; this resource only holds presentation data.

## Which screen edge an optional dialogue portrait enters from.
enum PortraitSide { LEFT, RIGHT }

## Portraits whose (cropped) width / height falls outside this range are refused
## rather than squeezed into the composition: a strip that thin or that wide is a data
## mistake, not a portrait, and showing it would only push the text around.
const PORTRAIT_MIN_ASPECT := 0.2
const PORTRAIT_MAX_ASPECT := 2.0
const PORTRAIT_MIN_HEIGHT_RATIO := 0.3
const PORTRAIT_MAX_HEIGHT_RATIO := 0.95

@export var character_id: StringName = &""
@export var display_name: String = ""
## Short role shown next to the name, e.g. "classmate". Not a title or diagnosis.
@export var short_role: String = ""
@export var accent_color: Color = Color(0.776, 0.733, 0.643, 1.0)

@export_group("Dialogue portrait (optional)")
## An approved 2D portrait for dialogue. Empty (the default) means the speaker is
## presented by name only and the dialogue panel keeps its text-led layout exactly as
## it is without this field. Never fill this with a placeholder, a silhouette or a
## render of the 3D model: see docs/ART_BIBLE.md, "Portraits".
@export var portrait: Texture2D = null
## Alternative to `portrait`: a `res://` path resolved when the line is shown. Kept as
## a plain string so a profile that names a file which is missing or not a texture
## still loads, and the panel can report what is wrong instead of failing the whole
## resource. Ignored when `portrait` is set.
@export_file("*.png", "*.webp", "*.jpg", "*.tres") var portrait_path: String = ""
## Screen edge the portrait enters from. The text band moves away from it only as far
## as it has to.
@export var portrait_side: PortraitSide = PortraitSide.LEFT
## Height of the portrait as a fraction of the viewport height. The portrait stands on
## the bottom edge of the screen and is scaled down further if it would crowd the text.
@export_range(0.3, 0.95, 0.01) var portrait_height_ratio: float = 0.72
## Part of the texture to show, in normalised texture coordinates (0..1). The default
## is the whole image. Use it to frame a figure, never to letterbox it into a card.
@export var portrait_crop: Rect2 = Rect2(0.0, 0.0, 1.0, 1.0)


## True when the profile asks for a portrait at all. Says nothing about whether the
## reference is usable: `resolve_portrait()` answers that.
func has_portrait() -> bool:
	return portrait != null or not portrait_path.strip_edges().is_empty()


## Resolves the portrait reference into something the dialogue panel can draw.
##
## Never raises a script error and never calls `load()` on a path that does not exist
## (that would print an engine error for what is a content problem). The result is a
## dictionary:
##
## - `status`: "none" (no portrait requested), "ok", or one of the failure codes
##   "invalid_path", "missing", "not_texture", "empty_size", "bad_aspect", "bad_crop";
## - `message`: a human-readable explanation naming the character and the reference;
## - `texture`: the texture to draw (already cropped), or null unless `status` is "ok";
## - `source_size`: the size of the referenced texture, when there is one;
## - `aspect`: width / height of what will be drawn, when there is something.
func resolve_portrait() -> Dictionary:
	var result := {
		"status": "none",
		"message": "",
		"texture": null,
		"source_size": Vector2.ZERO,
		"aspect": 0.0,
	}
	if not has_portrait():
		return result

	var texture: Texture2D = portrait
	var reference := "the embedded portrait"
	if texture == null:
		var path := portrait_path.strip_edges()
		reference = "portrait_path '%s'" % path
		if not (path.begins_with("res://") or path.begins_with("uid://")):
			return _portrait_failure(
				result, "invalid_path", "%s is not a res:// or uid:// path." % reference
			)
		if not ResourceLoader.exists(path):
			return _portrait_failure(result, "missing", "%s does not exist." % reference)
		var loaded: Resource = ResourceLoader.load(path)
		if not (loaded is Texture2D):
			return _portrait_failure(
				result, "not_texture", "%s is not a Texture2D resource." % reference
			)
		texture = loaded

	var source_size := texture.get_size()
	result["source_size"] = source_size
	if source_size.x < 1.0 or source_size.y < 1.0:
		return _portrait_failure(
			result, "empty_size", "%s has no pixels (%s)." % [reference, source_size]
		)

	var unit := Rect2(0.0, 0.0, 1.0, 1.0)
	var crop := portrait_crop.abs().intersection(unit)
	var region := Rect2(crop.position * source_size, crop.size * source_size)
	if region.size.x < 1.0 or region.size.y < 1.0:
		return _portrait_failure(
			result,
			"bad_crop",
			"portrait_crop %s leaves nothing of %s (%s)." % [portrait_crop, reference, source_size]
		)
	var aspect := region.size.x / region.size.y
	result["aspect"] = aspect
	if aspect < PORTRAIT_MIN_ASPECT or aspect > PORTRAIT_MAX_ASPECT:
		return _portrait_failure(
			result,
			"bad_aspect",
			(
				"%s is %.0fx%.0f after cropping (aspect %.2f); portraits must be between %.2f and %.2f."
				% [
					reference,
					region.size.x,
					region.size.y,
					aspect,
					PORTRAIT_MIN_ASPECT,
					PORTRAIT_MAX_ASPECT
				]
			)
		)

	if region == Rect2(Vector2.ZERO, source_size):
		result["texture"] = texture
	else:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = region
		result["texture"] = atlas
	result["status"] = "ok"
	return result


## The height ratio actually used: out-of-range values from a hand-edited file are
## clamped instead of trusted.
func get_portrait_height_ratio() -> float:
	return clampf(portrait_height_ratio, PORTRAIT_MIN_HEIGHT_RATIO, PORTRAIT_MAX_HEIGHT_RATIO)


func _portrait_failure(result: Dictionary, status: String, detail: String) -> Dictionary:
	result["status"] = status
	result["texture"] = null
	result["message"] = "Character '%s': %s" % [String(character_id), detail]
	return result
