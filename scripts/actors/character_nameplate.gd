class_name CharacterNameplate
extends Label3D
## The name above a grey-box character, for development builds.
##
## The blockout silhouettes are deliberately faceless, and in a room with more than one
## of them that is not enough to tell who is speaking. This label restores the one
## piece of information the model cannot carry — the name — without touching the model:
## it is a separate node, it belongs to the character's scene, and replacing the mesh
## later leaves it working.
##
## Rules it keeps:
## - the name comes from `CharacterProfile` and the locale tables, never from a string
##   typed into a script, so a language switch renames the world along with the text;
## - it is a `Label3D`: no collision shape, no body, no input. It cannot be walked into,
##   cannot block a click, and cannot widen an interaction radius;
## - it always faces the camera, so it is readable while the camera orbits;
## - it is **off in release builds**. A shipped game does not label its people like a
##   debug view; a development build does, and `ui/nameplates/show_development_nameplates`
##   overrides either way.

## Project setting that forces the labels on or off. Absent by default: the labels then
## follow the build type, which is what a debug view should do.
const SETTING := "ui/nameplates/show_development_nameplates"

@export var character_id: StringName = &""
## Scene-level switch, so a single character can opt out without touching the project.
@export var show_in_development: bool = true
## Height of the label above the character's origin.
@export var label_height: float = 1.92


func _ready() -> void:
	_configure()
	refresh()
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null and loc.has_signal("locale_changed"):
		loc.locale_changed.connect(_on_locale_changed)


func _configure() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = false
	fixed_size = false
	shaded = false
	double_sided = true
	position = Vector3(0.0, label_height, 0.0)
	pixel_size = 0.0042
	font_size = 64
	outline_size = 18
	outline_modulate = Color(0.043, 0.051, 0.051, 0.92)
	modulate = Color(0.898, 0.871, 0.804, 1.0)
	render_priority = 1
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var project_theme := _project_theme()
	if project_theme != null and project_theme.default_font != null:
		font = project_theme.default_font
	else:
		font = ThemeDB.fallback_font


## The project ships exactly one font, for CJK coverage. The world label uses the same
## file rather than adding a second typeface.
func _project_theme() -> Theme:
	var theme_path := String(ProjectSettings.get_setting("gui/theme/custom", ""))
	if theme_path.is_empty() or not ResourceLoader.exists(theme_path):
		return null
	var loaded: Resource = ResourceLoader.load(theme_path)
	return loaded as Theme


## Re-reads the name. Called on a language switch and by the tests.
func refresh() -> void:
	text = _resolve_name()
	visible = is_enabled() and not text.is_empty()


func is_enabled() -> bool:
	if not show_in_development:
		return false
	if ProjectSettings.has_setting(SETTING):
		return bool(ProjectSettings.get_setting(SETTING))
	return OS.is_debug_build()


## The profile's name, translated. A character with no profile falls back to the
## locale table key and then to nothing at all, so a label is never a raw id.
func _resolve_name() -> String:
	if String(character_id).is_empty():
		return ""
	var directory := CharacterDirectory.load_cached()
	if directory.has_character(character_id):
		return directory.get_localized_name(character_id)
	var key := "name.%s" % String(character_id)
	if L10n.has_key(key):
		return L10n.t(key)
	return ""


func _on_locale_changed(_locale: String) -> void:
	refresh()
