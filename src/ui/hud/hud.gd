class_name Hud
extends Control

@export var dot_radius: float = 2.0
@export var dot_color: Color = Color(1, 1, 1, 0.85)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# перерисовываться при ресайзе окна
	resized.connect(queue_redraw)

func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, dot_radius, dot_color)
