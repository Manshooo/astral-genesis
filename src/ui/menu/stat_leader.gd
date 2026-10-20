# res://src/ui/menu/stat_leader.gd
## Выноска строки итогов: пунктир 1:3 от показателя к значению (§9 «Меню — спека») — след взгляда, не линейка; чуть ниже середины, на уровне базовой линии.
class_name UI_StatLeader
extends Control

const BASELINE_DROP := 4.0


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var y := roundf(size.y / 2.0 + BASELINE_DROP)
	UI_MenuStyle.draw_dotted(self, Vector2(0.0, y), Vector2(size.x, y), Color(UI_MenuStyle.TEXT, 0.28))
