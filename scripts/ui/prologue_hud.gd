class_name PrologueHud
extends CanvasLayer
## Always-on presentation: interaction prompt, short status lines, the notebook
## button, and the cool overlay used while the protagonist is imagining.
##
## Holds no narrative state. PrologueFlow tells it what to display; the notebook
## window reads the ledger through the flow's public accessors.

signal note_book_requested
signal language_toggle_requested

@onready var prompt_label: Label = %PromptLabel
@onready var status_label: Label = %StatusLabel
@onready var note_button: Button = %NoteButton
@onready var language_button: Button = %LanguageButton
@onready var imagined_overlay: ColorRect = %ImaginedOverlay
@onready var bell_flash: ColorRect = %BellFlash

var _status_timer: float = 0.0
## Kept so a language switch can re-render text that is already on screen.
var _pending_prompt_zh: String = ""
var _pending_prompt_en: String = ""
var _pending_status_zh: String = ""
var _pending_status_en: String = ""
var _note_count: int = 0


func _ready() -> void:
	prompt_label.text = ""
	status_label.text = ""
	imagined_overlay.visible = false
	imagined_overlay.modulate.a = 0.0
	bell_flash.visible = false
	bell_flash.modulate.a = 0.0
	note_button.visible = false
	note_button.pressed.connect(func() -> void: note_book_requested.emit())
	language_button.pressed.connect(func() -> void: language_toggle_requested.emit())
	_refresh_language_button()
	set_process(true)


func _process(delta: float) -> void:
	if _status_timer > 0.0:
		_status_timer -= delta
		if _status_timer <= 0.0:
			status_label.text = ""
			status_label.modulate.a = 1.0
		elif _status_timer < 0.8:
			status_label.modulate.a = clampf(_status_timer / 0.8, 0.0, 1.0)
	if bell_flash.visible:
		bell_flash.modulate.a = move_toward(bell_flash.modulate.a, 0.0, delta * 0.6)
		if bell_flash.modulate.a <= 0.01:
			bell_flash.visible = false


func set_prompt(text_zh: String, text_en: String) -> void:
	_pending_prompt_zh = text_zh
	_pending_prompt_en = text_en
	if text_zh.is_empty() and text_en.is_empty():
		prompt_label.text = ""
		return
	prompt_label.text = Language.pick(text_zh, text_en)


func show_status(text_zh: String, text_en: String, duration: float = 4.0) -> void:
	_pending_status_zh = text_zh
	_pending_status_en = text_en
	status_label.text = Language.pick(text_zh, text_en)
	status_label.modulate.a = 1.0
	_status_timer = duration


func set_note_available(count: int) -> void:
	_note_count = count
	note_button.visible = count > 0
	note_button.text = "%s (%d)" % [Language.kb("N", "笔记", "notes"), count]


func _refresh_language_button() -> void:
	# The button shows the language you would switch TO, which is how players
	# read a language switch. The key hint is spelled out so it is discoverable.
	language_button.text = "%s [L]" % Language.other_label()


func refresh_language() -> void:
	_refresh_language_button()
	if _pending_prompt_zh != "" or _pending_prompt_en != "":
		set_prompt(_pending_prompt_zh, _pending_prompt_en)
	if _pending_status_zh != "" or _pending_status_en != "":
		status_label.text = Language.pick(_pending_status_zh, _pending_status_en)
	set_note_available(_note_count)


func set_note_count(count: int) -> void:
	set_note_available(count)


func set_imagined_overlay(enabled: bool) -> void:
	imagined_overlay.visible = enabled


func flash_bell() -> void:
	bell_flash.visible = true
	bell_flash.modulate.a = 0.35
