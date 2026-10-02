# res://src/ui/menu/key_row.gd
## Строка перепривязки (§5, §9 «Меню — спека»): действие слева, «[ клавиша ]»
## справа — в духе подсказки HUD. Вся строка — кнопка: клик в любом её месте
## ждёт новую клавишу, а не только по клавише.
##
## Имя клавиши приходит значением (SettingsManager.code_display_name), не текстом
## макета: «ЛКМ», «Пробел» и «W» — одна и та же подстановка.
class_name UI_KeyRow
extends Button

## Ширина колонки: две колонки по 412 с зазором 56 занимают строку 880 (§4).
const WIDTH := 412.0
const HEIGHT := 40.0
const DOT_X := 8.0
## Мигание ожидания (§7: цикл 1 с, ступенькой).
const BLINK_PERIOD := 1.0
## Вспышка обмена клавиш: over → soul_key за 1.2 с.
const FLASH_TIME := 1.2

var _action: Label
var _wait: Label
var _key: Label
var _waiting := false
var _hot := false
var _flash_tween: Tween


func _ready() -> void:
	theme_type_variation = &"MenuKeyRow"
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := get_theme_stylebox(&"normal")
	row.offset_left = style.get_margin(SIDE_LEFT)
	row.offset_right = -style.get_margin(SIDE_RIGHT)
	row.add_theme_constant_override(&"separation", 2)
	add_child(row)

	_action = _add(row, &"MenuRowLabel", "")
	_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_wait = _add(row, &"MenuCaption", tr("SETTINGS_REBIND_WAIT"))
	_wait.visible = false
	_add(row, &"MenuKeyBracket", "[")
	_key = _add(row, &"MenuKey", "")
	_key.custom_minimum_size.x = 12.0
	_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add(row, &"MenuKeyBracket", "]")


func _add(row: HBoxContainer, variation: StringName, value: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = value
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	row.add_child(label)
	return label


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
