# res://src/ui/hud/thought_label.gd
## Подпись HUD, звучащая мыслью: тень — сиреневое «эхо», дрожащее на смятение T (§5 «HUD — спека»); вид — вариация темы, здесь только движение эха.
class_name UI_ThoughtLabel
extends Label

## Разводит эхо соседних строк по фазе — чтобы не дрожали хором.
var echo_phase := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		UI_HudMood.apply_echo(self, echo_phase)
