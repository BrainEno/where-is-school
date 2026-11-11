class_name EndCard
extends Control
## Deliberate stop at the end of the implemented slice.
##
## This is a build marker, not a story event: it names where the milestone ends
## instead of inventing narrative content that the brief defers.
##
## At the end of the slice it also offers the way on (issue #95): **Start again**, which
## asks first and then runs `Session.start_new_game()`, and **Title**. The card that
## reports an unreadable save uses the same surface and shows neither.

signal restart_confirmed

const SAVE_NOTICE_TITLE_KEY := "save.error.title"

@onready var _title: Label = %EndTitle
@onready var _body: Label = %EndBody
@onready var _hint: Label = %EndHint

var _actions: HBoxContainer = null
var _restart: Button = null
var _title_button: Button = null
var _confirm: ConfirmPrompt = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	_build_actions()
	var settings := get_node_or_null(^"/root/Settings")
	if settings != null:
		settings.connect("setting_changed", _on_setting_changed)
	var loc := get_node_or_null(^"/root/Loc")
	if loc != null:
		loc.connect("locale_changed", _on_locale_changed)
	UiTextScale.apply(self, UiTextScale.current(self))


func _build_actions() -> void:
	var layout := _title.get_parent()
	_actions = HBoxContainer.new()
	_actions.name = "EndActions"
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override(&"separation", 28)
	_actions.visible = false
	layout.add_child(_actions)
	_restart = MenuStyle.entry_button("", MenuStyle.BODY_SIZE, 1.0)
	_restart.name = "Restart"
	_restart.autowrap_mode = TextServer.AUTOWRAP_OFF
	_restart.pressed.connect(ask_restart)
	_actions.add_child(_restart)
	_title_button = MenuStyle.entry_button("", MenuStyle.BODY_SIZE, 1.0)
	_title_button.name = "ToTitle"
	_title_button.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title_button.pressed.connect(_on_title_pressed)
	_actions.add_child(_title_button)
	_confirm = ConfirmPrompt.new()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_restart_confirmed)
	_confirm.cancelled.connect(_focus_restart)
	_refresh_action_text()


## True while the card offers Start again / Title.
func has_actions() -> bool:
	return _actions != null and _actions.visible


func get_restart_button() -> Button:
	return _restart


func get_title_button() -> Button:
	return _title_button


func get_confirm() -> ConfirmPrompt:
	return _confirm


## Asks before starting over: the save holds the end of the run.
func ask_restart() -> void:
	_confirm.ask(
		L10n.t("menu.confirm_new_game"), L10n.t("menu.confirm_yes"), L10n.t("menu.confirm_no")
	)


func _on_restart_confirmed() -> void:
	restart_confirmed.emit()
	var session := get_node_or_null(^"/root/Session")
	if session != null:
		session.call("start_new_game")


func _on_title_pressed() -> void:
	var session := get_node_or_null(^"/root/Session")
	if session != null:
		session.call("go_to_title")


func _focus_restart() -> void:
	if _restart != null and _restart.is_visible_in_tree():
		_restart.grab_focus()


func _refresh_action_text() -> void:
	if _restart == null:
		return
	_restart.text = L10n.t("menu.start_again")
	_title_button.text = L10n.t("menu.title")


func _on_locale_changed(_locale: String) -> void:
	_refresh_action_text()


func _on_setting_changed(key: StringName) -> void:
	if UiTextScale.is_text_size_key(key):
		UiTextScale.apply(self, UiTextScale.current(self))


## Text currently on the card, for the language switch and for tests.
func get_title() -> String:
	return _title.text if _title != null else ""


func get_body() -> String:
	return _body.text if _body != null else ""


func present(title: String, body: String, hint: String = "") -> void:
	_title.text = title
	_body.text = body
	_hint.text = hint
	_hint.visible = not hint.is_empty()
	# The unreadable-save notice leaves by itself; every other card is the end of a run.
	var actions := title != L10n.t(SAVE_NOTICE_TITLE_KEY)
	_actions.visible = actions
	_refresh_action_text()
	show()
	move_to_front()
	if actions:
		_focus_restart.call_deferred()
	modulate = Color(1, 1, 1, 0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.9)


## Fades the card out and hides it. The end of the slice leaves its card up on purpose;
## a card that is only reporting something - a save that could not be read - has to be
## able to leave again without the player doing anything.
func dismiss(duration: float = 0.6) -> void:
	if not visible:
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	await tween.finished
	hide()
	_actions.visible = false
