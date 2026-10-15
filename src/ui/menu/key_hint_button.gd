# res://src/ui/menu/key_hint_button.gd
## Подсказка клавиши в углу экрана — «[Esc] Назад» — и кнопка заодно: мышью по
## ней кликают так же, как жмут клавишу. Скобки и клавиша — отдельные подписи
## (как в UI_ThoughtLine у HUD): строка перевода хранит только действие, а
## скобки красятся по-своему.
##
## Esc — не из настроек управления: pause_game намеренно не переназначается
## (SettingsManager.REBINDABLE_ACTIONS), и OS.get_keycode_string назвал бы её
## «Escape», а на клавише написано «Esc».
##
## Устройство — в key_hint_button.tscn: экраны ставят подсказку экземпляром
## сцены, .new() дал бы кнопку без подписей. Отступ строки от края кнопки в
## сцене повторяет поля StyleBox «MenuHintButton» темы (10 × 6).
class_name UI_KeyHintButton
extends Button

@export var key_text := "Esc"
## Ключ перевода действия.
@export var action_key := "HINT_BACK"

@onready var _row: HBoxContainer = %Row
@onready var _key: Label = %Key
@onready var _action: Label = %Action

## Своё, а не is_hovered(): в обработчике mouse_exited кнопка ещё может
## считать себя наведённой.
var _hover := false


func _ready() -> void:
	_key.text = key_text
	# Перевод — здесь, а не автопереводом подписи: перед действием стоят пробелы,
	# и строка целиком ключом уже не была бы.
	_action.text = "  " + tr(action_key)
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	focus_entered.connect(_paint)
	focus_exited.connect(_paint)
	_layout.call_deferred()


## Размер кнопки — по строке: у Button с пустым text минимум нулевой, и без
## этого она была бы некликабельной точкой. Поля симметричны, поэтому справа и
## снизу — тот же отступ, что у строки слева и сверху.
func _layout() -> void:
	_row.size = _row.get_combined_minimum_size()
	custom_minimum_size = _row.size + _row.position * 2.0


func _set_hover(value: bool) -> void:
	_hover = value
	_paint()


## Наведение и фокус высветляют подпись действия; сиреневое у клавиши остаётся
## как есть — оно и так «внимание души».
func _paint() -> void:
	if _hover or has_focus():
		_action.add_theme_color_override(&"font_color", UI_MenuStyle.TEXT)
	else:
		_action.remove_theme_color_override(&"font_color")
	queue_redraw()


func _draw() -> void:
	if has_focus():
		# Фокус — подчёркивание сиреневым под строкой (.ag-esc:focus-visible).
		var y := _row.position.y + _row.size.y + 3.0
		draw_line(Vector2(_row.position.x, y), Vector2(_row.position.x + _row.size.x, y),
				UI_HudMood.SOUL, 1.0)
