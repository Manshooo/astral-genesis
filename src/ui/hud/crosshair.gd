class_name UI_Crosshair
extends Control

@export var dot_radius: float = 2.0
@export var dot_color: Color = Color(1, 1, 1, 0.85)

func _ready() -> void:
	pass # Replace with function body.


func _draw() -> void:
	var center := size / 2.0
	draw_circle(center, dot_radius, dot_color)
