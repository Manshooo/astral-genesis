class_name UI_Hud
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	#set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)
