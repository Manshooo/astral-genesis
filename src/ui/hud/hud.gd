# res://src/ui/hud/hud.gd
# Корень HUD — полноэкранный слой, только показывает: MOUSE_FILTER_STOP по умолчанию заслонил бы от кликов всё под ним.
class_name UI_Hud
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
