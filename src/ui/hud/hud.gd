# res://src/ui/hud/hud.gd
# Корень HUD — полноэкранный слой, который только показывает. Мышь ему не нужна,
# а Control по умолчанию её перехватывает (MOUSE_FILTER_STOP): растянутый на весь
# экран, он заслонил бы от кликов всё, что лежит под ним.
class_name UI_Hud
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
