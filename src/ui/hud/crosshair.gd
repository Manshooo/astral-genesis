## Прицел с тремя состояниями, по тому, что сейчас под ним:
##   - пусто                 → маленькая точка;
##   - интерактив            → точка крупнее (метка C_Highlighted, см. Взаимодействие);
##   - тело для захвата      → крестик (метка C_SnatchTargeted, ставит S_SnatchTargetDetector).
##
## Оба состояния анимируются собственным прогрессом, а не переключаются рывком:
## точка растворяется ровно настолько, насколько проявился крестик, поэтому
## переход читается как превращение одного в другое.
class_name UI_Crosshair
extends Control

@export_group("Точка")
@export var dot_radius: float = 2.0
@export var hover_dot_radius: float = 5.0
@export var dot_color: Color = Color(1, 1, 1, 0.85)

@export_group("Крестик захвата")
## Длина каждого из четырёх лучей.
@export var cross_length: float = 7.0
## Дырка в середине: откуда луч начинается, если считать от центра.
@export var cross_gap: float = 3.0
@export var cross_width: float = 2.0
@export var cross_color: Color = Color(1, 0.45, 0.4, 0.95)

@export_group("Анимация")
@export var animation_speed: float = 10.0

## Под крестиком интерактив (C_Highlighted).
var _hovering: bool = false
## Под крестиком захватываемое тело (C_SnatchTargeted).
var _snatchable: bool = false
var _hover_progress: float = 0.0
var _snatch_progress: float = 0.0


func _ready() -> void:
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)


func _process(delta: float) -> void:
	var step := animation_speed * delta
	var hover := move_toward(_hover_progress, 1.0 if _hovering else 0.0, step)
	var snatch := move_toward(_snatch_progress, 1.0 if _snatchable else 0.0, step)
	if hover == _hover_progress and snatch == _snatch_progress:
		return
	_hover_progress = hover
	_snatch_progress = snatch
	queue_redraw()  # Заставляет вызвать _draw() на следующем кадре


func _on_world_changed(world: World) -> void:
	_hovering = false
	_snatchable = false
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
	elif component is C_SnatchTargeted:
		_snatchable = true
	else:
		return
	queue_redraw()


func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is C_Highlighted:
		_hovering = false
	elif component is C_SnatchTargeted:
		_snatchable = false
	else:
		return
	queue_redraw()


func _draw() -> void:
	var center := size / 2.0

	# Точка гаснет по мере проявления крестика — иначе они наложились бы друг на
	# друга в середине.
	if _snatch_progress < 1.0:
		var radius: float = lerpf(dot_radius, hover_dot_radius, _hover_progress)
		var color := dot_color
		color.a *= 1.0 - _snatch_progress
		draw_circle(center, radius, color)

	if _snatch_progress > 0.0:
		_draw_cross(center)


## Четыре луча из центра: вертикальная и горизонтальная пары, с отступом
## cross_gap от середины. Растут от нуля, поэтому крестик «раскрывается».
func _draw_cross(center: Vector2) -> void:
	var color := cross_color
	color.a *= _snatch_progress
	var length: float = cross_length * _snatch_progress
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(
			center + direction * cross_gap,
			center + direction * (cross_gap + length),
			color,
			cross_width
		)
