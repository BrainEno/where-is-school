extends Node
## Autoload `Loc`: the player's language choice, persisted between runs.
##
## All lookup logic lives in L10n (static, usable from headless tests). This node
## adds the two things a static class cannot: a `locale_changed` signal for the
## screens that have to redraw, and a saved preference.

signal locale_changed(locale: String)

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "display"
const SETTINGS_KEY := "locale"

var _last_error_count: int = 0


func _ready() -> void:
	var errors := L10n.load_tables()
	_last_error_count = errors.size()
	for message in errors:
		push_error("Loc: %s" % message)
	var saved := _load_saved_locale()
	if not saved.is_empty():
		L10n.set_locale(saved)
	TranslationServer.set_locale(L10n.current)
	# The switch is available from the first frame, including on the title fade.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_language"):
		return
	get_viewport().set_input_as_handled()
	toggle()


func get_locale() -> String:
	return L10n.current


func other_locale() -> String:
	return L10n.other_locale()


func locale_name(locale: String = "") -> String:
	return L10n.locale_name(locale)


func available_locales() -> Array[String]:
	return L10n.available_locales()


## Returns true when the language actually changed.
func set_locale(locale: String) -> bool:
	if not L10n.set_locale(locale):
		return false
	TranslationServer.set_locale(L10n.current)
	_save_locale(L10n.current)
	locale_changed.emit(L10n.current)
	return true


func toggle() -> bool:
	return set_locale(L10n.other_locale())


func load_errors() -> Array[String]:
	return L10n.errors()


func _load_saved_locale() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return ""
	return String(config.get_value(SETTINGS_SECTION, SETTINGS_KEY, ""))


func _save_locale(locale: String) -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, locale)
	config.save(SETTINGS_PATH)
