# res://src/ui/death_screen/stat_row.gd
## Строка сводки итогов — «показатель ···· значение» (§9 «Меню — спека»):
## выноска (UI_StatLeader) тянется на всё, что осталось, поэтому длинное
## английское имя показателя просто укорачивает её.
##
## Устройство — в stat_row.tscn; строк столько, сколько показателей выдал
## каталог за этот забег, поэтому экран итогов создаёт их instantiate() из
## сцены. Скрипт решает только то, что зависит от текста: перенос длинного
## значения.
class_name UI_StatRow
extends HBoxContainer

## Дальше этой ширины значение переносится (§4): список тел бывает длинным, и
## без переноса он вытолкнул бы выноску в ноль.
const VALUE_MAX_WIDTH := 300.0

@onready var _label: Label = %Label
@onready var _value: Label = %Value


## Текст уже переведён вызывающим (tr) или переводу не подлежит (число):
## автоперевод у подписей выключен в сцене, иначе он искал бы ключ «12».
func setup(label_text: String, value_text: String) -> void:
	_label.text = label_text
	_value.text = value_text
	var width := _value.get_theme_font(&"font").get_string_size(
			value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _value.get_theme_font_size(&"font_size")).x
	if width > VALUE_MAX_WIDTH:
		_value.custom_minimum_size.x = VALUE_MAX_WIDTH
		_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
