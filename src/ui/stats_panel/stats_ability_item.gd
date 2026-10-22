# res://src/ui/stats_panel/stats_ability_item.gd
## Слот или ячейка банка на экране показателей: ячейка-кнопка, имя способности и строка происхождения под ней (макет 14).
## Устройство — stats_slot.tscn (56 px, с номером) и stats_bank_item.tscn (44 px); что писать, решает UI_StatsPanel.
class_name UI_StatsAbilityItem
extends VBoxContainer

signal chosen

@onready var _pick: Button = %Pick
@onready var _cell: UI_AbilityCell = %Cell
@onready var _name: Label = %Name
@onready var _sub: Label = %Sub


func _ready() -> void:
	_pick.pressed.connect(chosen.emit)
	_pick.mouse_entered.connect(_set_hover.bind(true))
	_pick.mouse_exited.connect(_set_hover.bind(false))


## [param title] пусто — строки имени нет (закрытая ячейка банка); [param dim] — имя цветом text_dim.
func show_item(
	state: UI_AbilityCell.State, ability: C_Ability, title: String, sub: String,
	number: int = 0, sleeping: bool = false, dim: bool = false,
) -> void:
	_cell.show_ability(state, ability, number, sleeping)
	_name.visible = title != ""
	_name.text = title
	if dim:
		_name.add_theme_color_override(&"font_color", UI_HudMood.TEXT_DIM)
	else:
		_name.remove_theme_color_override(&"font_color")
	_sub.visible = sub != ""
	_sub.text = sub


## Выбранная ячейка банка ждёт слота: свечение, как у новой способности на экране полного банка.
func set_selected(value: bool) -> void:
	_cell.glowing = value


func cell() -> UI_AbilityCell:
	return _cell


func button() -> Button:
	return _pick


func _set_hover(value: bool) -> void:
	_cell.hovered = value
