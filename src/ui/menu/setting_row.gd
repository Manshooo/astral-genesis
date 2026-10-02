# res://src/ui/menu/setting_row.gd
## Строка экрана настроек (§9 «Меню — спека»): подпись слева, контрол с x 340
## строки, у слайдера — значение справа. Первым ребёнком в сцене лежит подпись,
## дальше — контрол настройки и что ему нужно.
##
## Фокус показывает строка, а не контрол: у слайдера Godot зажигает один и тот же
## бегунок-highlight и на наведение, и на фокус, а у списка и флажка своего знака
## фокуса в языке нет. Поэтому фокус внутри строки зажигает точку души слева от
## подписи и эхо самой подписи — так же, как у кнопки-мысли.
##
## Строка же сообщает экрану, что на неё смотрят ([signal looked_at]): подсказка
## живёт в отдельной колонке, а не тултипом (§9), и ей нужно знать, про что
## рассказывать.
class_name UI_SettingRow
extends HBoxContainer

signal looked_at(row: UI_SettingRow)

## Ключ перевода подсказки в колонке; пусто — колонка покажет только название.
@export var hint_key := ""

## Высота строки и ширина подписи вместе с зазором до контрола (§4).
const ROW_HEIGHT := 46.0
const LABEL_WIDTH := 340.0
const SEPARATION := 18
## Точка фокуса — левее подписи, в поле экрана.
const DOT_X := -14.0
const ECHO_IN := 0.14

var _label: Label
var _echo := 0.0
var _active := false
var _disabled := false
## Что уже выставлено подписи: цвет, цвет эха, сдвиг эха.
var _painted: Array = []


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, ROW_HEIGHT)
	add_theme_constant_override(&"separation", SEPARATION)
	_label = get_child(0) as Label
	if _label:
		_label.custom_minimum_size.x = LABEL_WIDTH - SEPARATION
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Название строки, переведённое, — для заголовка подсказки. В text подписи
## лежит ключ: переводит её автоперевод при отрисовке, а не присваивание.
func title() -> String:
	return _label.atr(_label.text) if _label else ""


## Недоступная строка: подпись гаснет, контрол не трогается. Причину называет
## подсказка строки («Недоступно, пока тени выключены»).
func set_row_disabled(value: bool) -> void:
	_disabled = value
	if _label:
		_label.modulate.a = 0.4 if value else 1.0
	for child in get_children():
		if child is Range:
			(child as Range).editable = not value
			(child as Control).focus_mode = Control.FOCUS_NONE if value else Control.FOCUS_ALL
		elif child is BaseButton:
			(child as BaseButton).disabled = value
		if child is Control and child != _label:
			(child as Control).modulate.a = 0.3 if value else 1.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var focused := _has_focus_inside()
	var hovered := get_global_rect().has_point(get_global_mouse_position())
	var active := (focused or hovered) and not _disabled
	if active and not _active:
		looked_at.emit(self)
	_active = active
	_echo = move_toward(_echo, 1.0 if active else 0.0, delta / ECHO_IN)
	if _label:
		var shadow := UI_MenuStyle.ECHO
		shadow.a *= _echo
		var offset := UI_MenuStyle.echo_offset(float(get_index()) * 1.3)
		_paint_label(UI_MenuStyle.TEXT if active else UI_MenuStyle.TEXT_MSG, shadow,
				Vector2i(roundi(offset.x), roundi(offset.y)))
	queue_redraw()



## Переопределения — только когда что-то поменялось: каждое из них зовёт у
## подписи пересчёт темы, а строк на экране с десяток и кадров — шестьдесят.
func _paint_label(color: Color, shadow: Color, offset: Vector2i) -> void:
	var state := [color, shadow, offset]
	if state == _painted:
		return
	_painted = state
	_label.add_theme_color_override(&"font_color", color)
	_label.add_theme_color_override(&"font_shadow_color", shadow)
	_label.add_theme_constant_override(&"shadow_offset_x", offset.x)
	_label.add_theme_constant_override(&"shadow_offset_y", offset.y)


func _draw() -> void:
	if not _has_focus_inside():
		return
	var center := Vector2(DOT_X, size.y / 2.0)
	draw_circle(center, 8.0, UI_MenuStyle.HALO)
	draw_circle(center, 3.0, UI_HudMood.SOUL)


func _has_focus_inside() -> bool:
	var owner_control := get_viewport().gui_get_focus_owner()
	return owner_control != null and is_ancestor_of(owner_control)
