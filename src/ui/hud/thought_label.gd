# res://src/ui/hud/thought_label.gd
## Подпись HUD, которая звучит мыслью: её тень — сиреневое «эхо», дрожащее на
## смятение T (§5 «HUD — спека»). Вид (шрифт, цвет, обводка) — вариация общей
## темы, здесь только движение эха: тема анимировать не умеет.
class_name UI_ThoughtLabel
extends Label

## Разводит эхо соседних строк по фазе, чтобы они не дрожали хором.
var echo_phase := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		UI_HudMood.apply_echo(self, echo_phase)
