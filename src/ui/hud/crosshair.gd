class_name UI_Crosshair
extends Control

@export var dot_radius: float = 2.0
@export var hover_dot_radius: float = 5.0
@export var dot_color: Color = Color(1, 1, 1, 0.85)

var _hovering: bool = false

func _ready() -> void:
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)


func _on_world_changed(world: World) -> void:
	_hovering = false
	if world:
		_connect_world_signals(world)
	queue_redraw()


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_added):
		world.component_added.connect(_on_component_added)
	if not world.component_removed.is_connected(_on_component_removed):
		world.component_removed.connect(_on_component_removed)


func _on_component_added(_entity: Entity, component: Variant) -> void:
	if component is C_Highlighted:
		_hovering = true
		queue_redraw()


func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is C_Highlighted:
		_hovering = false
		queue_redraw()


func _draw() -> void:
	var center := size / 2.0
	var radius := hover_dot_radius if _hovering else dot_radius
	draw_circle(center, radius, dot_color)
