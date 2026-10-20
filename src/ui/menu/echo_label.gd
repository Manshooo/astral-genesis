# res://src/ui/menu/echo_label.gd
## Подпись меню, звучащая мыслью: сиреневое эхо, дрожащее на смятение T, как UI_ThoughtLabel у HUD, но T — меню (UI_MenuStyle.turmoil: вне забега спокойное). Цвет эха и шрифт — вариация темы.
class_name UI_EchoLabel
extends Label

## Разводит эхо соседних подписей по фазе.
@export var echo_phase := 0.0


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var offset := UI_MenuStyle.echo_offset(echo_phase)
	add_theme_constant_override("shadow_offset_x", roundi(offset.x))
	add_theme_constant_override("shadow_offset_y", roundi(offset.y))
