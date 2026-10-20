# res://src/ui/menu/key_hint_button.gd
## Подсказка клавиши в углу — «[Esc] Назад» — и кнопка заодно. Скобки и клавиша отдельными подписями (как UI_ThoughtLine). Esc не из настроек: pause_game не переназначается (REBINDABLE_ACTIONS),
## OS.get_keycode_string назвал бы её «Escape». Устройство — key_hint_button.tscn (instantiate(), не .new()); отступ повторяет поля StyleBox «MenuHintButton» (10 × 6).
class_name UI_KeyHintButton
extends Button

@export var key_text := "Esc"
## Ключ перевода действия.
@export var action_key := "HINT_BACK"

@onready var _row: HBoxContainer = %Row
@onready var _key: Label = %Key
@onready var _action: Label = %Action

## Своё, а не is_hovered(): в mouse_exited кнопка ещё может считать себя наведённой.
var _hover := false


func _ready() -> void:
	_key.text = key_text
	# Перевод здесь: перед действием стоят пробелы, строка целиком ключом уже не была бы.
	_action.text = "  " + tr(action_key)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_entered.connect(_paint)
	focus_exited.connect(_paint)
	_layout.call_deferred()


## Размер кнопки — по строке: у Button с пустым text минимум нулевой (некликабельная точка); поля симметричны.
func _layout() -> void:
	_row.size = _row.get_combined_minimum_size()
	custom_minimum_size = _row.size + _row.position * 2.0


func _set_hover(value: bool) -> void:
	_hover = value
	_paint()


## Наведение и фокус высветляют подпись действия; сиреневое у клавиши остаётся.
func _paint() -> void:
	if _hover or has_focus():
		_action.add_theme_color_override(&"font_color", UI_MenuStyle.TEXT)
	else:
		_action.remove_theme_color_override(&"font_color")
	queue_redraw()


func _draw() -> void:
	if has_focus():
		# Фокус — подчёркивание сиреневым под строкой.
		var y := _row.position.y + _row.size.y + 3.0
		draw_line(Vector2(_row.position.x, y), Vector2(_row.position.x + _row.size.x, y),
				UI_HudMood.SOUL, 1.0)
