# res://src/ui/menu/key_row.gd
## Строка перепривязки (§5, §9 «Меню — спека»): действие слева, «[ клавиша ]»
## справа — в духе подсказки HUD. Вся строка — кнопка: клик в любом её месте
## ждёт новую клавишу, а не только по клавише.
##
## Имя клавиши приходит значением (SettingsManager.code_display_name), не текстом
## макета: «ЛКМ», «Пробел» и «W» — одна и та же подстановка.
##
## Устройство — в key_row.tscn: ширина 412 — колонка, две колонки с зазором 56
## занимают строку 880 (§4); отступы строки повторяют поля StyleBox
## «MenuKeyRow» темы (24 слева, 8 справа). Число строк — из данных, поэтому их
## создают instantiate() из сцены — .new() дал бы кнопку без подписей.
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


## Ожидание новой клавиши: вместо клавиши — мигающий «_», слева подпись.
func set_waiting(value: bool) -> void:
	_waiting = value
	_wait.visible = value
	if value:
		_key.text = "_"


## Клавиша досталась этой строке обменом — вспыхивает, чтобы игрок заметил,
## что поменялась не только та строка, по которой он кликнул.
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
	# Только на смене: переопределение цвета зовёт у подписи пересчёт темы.
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
