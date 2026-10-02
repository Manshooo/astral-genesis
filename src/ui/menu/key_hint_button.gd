# res://src/ui/menu/key_hint_button.gd
## Подсказка клавиши в углу экрана — «[Esc] Назад» — и кнопка заодно: мышью по
## ней кликают так же, как жмут клавишу. Скобки и клавиша — отдельные подписи
## (как в UI_ThoughtLine у HUD): строка перевода хранит только действие, а
## скобки красятся по-своему.
##
## Esc — не из настроек управления: pause_game намеренно не переназначается
## (SettingsManager.REBINDABLE_ACTIONS), и OS.get_keycode_string назвал бы её
## «Escape», а на клавише написано «Esc».
class_name UI_KeyHintButton
extends Button

@export var key_text := "Esc"
## Ключ перевода действия.
@export var action_key := "HINT_BACK"

var _row: HBoxContainer
## Своё, а не is_hovered(): в обработчике mouse_exited кнопка ещё может
## считать себя наведённой.
var _hover := false


func _ready() -> void:
	theme_type_variation = &"MenuHintButton"
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 1)
	add_child(_row)
	_add(&"MenuHintBracket", "[")
	_add(&"MenuHintKey", key_text)
	_add(&"MenuHintBracket", "]")
	# Перевод — здесь, а не автопереводом подписи: перед действием стоят пробелы,
	# и строка целиком ключом уже не была бы.
	_add(&"MenuHint", "  " + tr(action_key))
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_entered.connect(_paint)
	focus_exited.connect(_paint)
	_layout.call_deferred()


func _add(variation: StringName, text_value: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text_value
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(label)
	return label


## Размер кнопки — по строке: у Button с пустым text минимум нулевой, и без
## этого она была бы некликабельной точкой.
func _layout() -> void:
	var style := get_theme_stylebox(&"normal")
	_row.position = Vector2(style.get_margin(SIDE_LEFT), style.get_margin(SIDE_TOP))
	_row.size = _row.get_combined_minimum_size()
	custom_minimum_size = _row.size + style.get_minimum_size()


func _set_hover(value: bool) -> void:
	_hover = value
	_paint()


## Наведение и фокус высветляют подпись действия; сиреневое у клавиши остаётся
## как есть — оно и так «внимание души».
func _paint() -> void:
	var label := _row.get_child(3) as Label
	if _hover or has_focus():
		label.add_theme_color_override(&"font_color", UI_MenuStyle.TEXT)
	else:
		label.remove_theme_color_override(&"font_color")
	queue_redraw()


func _draw() -> void:
	if has_focus():
		# Фокус — подчёркивание сиреневым под строкой (.ag-esc:focus-visible).
		var y := _row.position.y + _row.size.y + 3.0
		draw_line(Vector2(_row.position.x, y), Vector2(_row.position.x + _row.size.x, y),
				UI_HudMood.SOUL, 1.0)
