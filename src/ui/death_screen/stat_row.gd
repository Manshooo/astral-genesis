# res://src/ui/death_screen/stat_row.gd
## Строка сводки итогов — «показатель ···· значение» (§9 «Меню — спека»); выноска (UI_StatLeader) тянется на остаток. Устройство — в stat_row.tscn, скрипт решает только перенос длинного значения.
class_name UI_StatRow
extends HBoxContainer

## Дальше этой ширины значение переносится (список тел бывает длинным).
const VALUE_MAX_WIDTH := 300.0

@onready var _label: Label = %Label
@onready var _value: Label = %Value


## Текст уже переведён вызывающим или не подлежит переводу: автоперевод подписей выключен в сцене.
func setup(label_text: String, value_text: String) -> void:
	_label.text = label_text
	_value.text = value_text
	var width := _value.get_theme_font(&"font").get_string_size(
			value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _value.get_theme_font_size(&"font_size")).x
	if width > VALUE_MAX_WIDTH:
		_value.custom_minimum_size.x = VALUE_MAX_WIDTH
		_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
