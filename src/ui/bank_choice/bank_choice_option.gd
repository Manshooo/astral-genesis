# res://src/ui/bank_choice/bank_choice_option.gd
## Ячейка банка на экране полного банка: кнопка 48 px с иконкой, имя и слот; при наведении ячейка светлеет к over, а подпись говорит «заменить» (макет 16).
## Устройство — bank_choice_option.tscn, инстанс на ячейку банка.
class_name UI_BankChoiceOption
extends VBoxContainer

signal chosen

@onready var _pick: Button = %Pick
@onready var _cell: UI_AbilityCell = %Cell
@onready var _name: Label = %Name
@onready var _sub: Label = %Sub

var _slot_text := ""


func _ready() -> void:
	_pick.pressed.connect(chosen.emit)
	_pick.mouse_entered.connect(_set_hover.bind(true))
	_pick.mouse_exited.connect(_set_hover.bind(false))
	_pick.focus_entered.connect(_set_hover.bind(true))
	_pick.focus_exited.connect(_set_hover.bind(false))


func setup(ability: C_Ability) -> void:
	_cell.show_ability(UI_AbilityCell.State.SOUL, ability)
	_name.text = tr(ability.name_key)
	_slot_text = tr("HUD_BANK_SLOT") % ability.slot
	_set_hover(false)


func button() -> Button:
	return _pick


func _set_hover(value: bool) -> void:
	_cell.hovered = value
	_sub.text = tr("HUD_BANK_HOVER") if value else _slot_text
	if value:
		_sub.add_theme_color_override(&"font_color", UI_HudMood.SOUL_KEY)
	else:
		_sub.remove_theme_color_override(&"font_color")
