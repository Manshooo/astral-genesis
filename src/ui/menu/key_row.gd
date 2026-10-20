# res://src/ui/menu/key_row.gd
## Строка перепривязки (§5, §9 «Меню — спека»): действие слева, «[ клавиша ]» справа; вся строка — кнопка. Имя клавиши — значением (SettingsManager.code_display_name). Устройство — key_row.tscn (instantiate():
## .new() дал бы кнопку без подписей); ширина 412 — колонка, две с зазором 56 занимают 880 (§4); отступы повторяют StyleBox «MenuKeyRow» (24 / 8).
class_name UI_KeyRow
extends Button

const DOT_X := 8.0
## Мигание ожидания (§7: цикл 1 с, ступенькой).
const BLINK_PERIOD := 1.0
## Вспышка обмена клавиш: over → soul_key за 1.2 с.
const FLASH_TIME := 1.2

@onready var _action: Label = %Action
@onready var _wait: Label = %Wait
@onready var _key: Label = %Key

var _waiting := false
var _hot := false
var _flash_tween: Tween


func set_action(action_name: String) -> void:
	_action.text = action_name


func set_key(key_name: String) -> void:
	_key.text = key_name


## Ожидание новой клавиши: вместо клавиши мигающий «_».
func set_waiting(value: bool) -> void:
	_waiting = value
	_wait.visible = value
	if value:
		_key.text = "_"


## Клавиша досталась строке обменом — вспыхивает, чтобы игрок заметил.
func flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_key.add_theme_color_override(&"font_color", UI_HudMood.OVER)
	_flash_tween = create_tween()
	_flash_tween.tween_method(
		func(c: Color) -> void: _key.add_theme_color_override(&"font_color", c),
		UI_HudMood.OVER, UI_HudMood.SOUL_KEY, FLASH_TIME,
	).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var hot := is_hovered() or has_focus() or _waiting
	# Только на смене: переопределение цвета зовёт пересчёт темы.
	if hot != _hot:
		_hot = hot
		_action.add_theme_color_override(&"font_color", UI_MenuStyle.TEXT if hot else UI_MenuStyle.TEXT_MSG)
	if _waiting:
		_key.modulate.a = 1.0 if fmod(UI_HudMood.now(), BLINK_PERIOD) < BLINK_PERIOD / 2.0 else 0.0
	else:
		_key.modulate.a = 1.0
	queue_redraw()


func _draw() -> void:
	var lit := has_focus()
	if _waiting:
		lit = fmod(UI_HudMood.now(), BLINK_PERIOD) < BLINK_PERIOD / 2.0
	if not lit:
		return
	var center := Vector2(DOT_X, size.y / 2.0)
	draw_circle(center, 7.5, UI_MenuStyle.HALO)
	draw_circle(center, 2.5, UI_HudMood.SOUL)
