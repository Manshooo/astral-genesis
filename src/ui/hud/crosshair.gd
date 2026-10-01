## Прицел с тремя состояниями, по тому, что сейчас под ним:
##   - пусто                 → маленькая точка;
##   - интерактив            → точка крупнее (метка C_Highlighted, см. Взаимодействие);
##   - тело для захвата      → крестик (метка C_SnatchTargeted, ставит S_SnatchTargetDetector).
##
## Оба состояния анимируются собственным прогрессом, а не переключаются рывком:
## точка растворяется ровно настолько, насколько проявился крестик, поэтому
## переход читается как превращение одного в другое.
##
## Вид — язык «Отголосок» (§4 «HUD — спека»): у крупной точки ореол, крестик
## сиреневый (красный теперь значит кровь) и с изломом в середине луча — тем
## сильнее, чем больше смятение T.
class_name UI_Crosshair
extends Control

@export_group("Точка")
@export var dot_radius: float = 2.0
@export var hover_dot_radius: float = 4.2
@export var dot_color: Color = UI_HudMood.DOT

@export_group("Крестик захвата")
## Длина каждого из четырёх лучей.
@export var cross_length: float = 7.0
## Дырка в середине: откуда луч начинается, если считать от центра.
@export var cross_gap: float = 3.0
@export var cross_width: float = 2.0
@export var cross_color: Color = UI_HudMood.CROSS

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
	# Крестик дрожит изломом, пока виден, — его перерисовываем каждый кадр.
	if hover == _hover_progress and snatch == _snatch_progress and snatch == 0.0:
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
		var fade := 1.0 - _snatch_progress
		# Ореол — не украшение: на светлой стене крупная точка без него сливалась
		# бы с фоном ровно тогда, когда должна сказать «здесь можно действовать».
		var halo := dot_color
		halo.a = 0.10 * _hover_progress * fade
		if halo.a > 0.0:
			draw_circle(center, 6.0 + 4.0 * _hover_progress, halo)
		var radius: float = lerpf(dot_radius, hover_dot_radius, _hover_progress)
		var color := dot_color
		color.a = (dot_color.a + 0.07 * _hover_progress) * fade
		draw_circle(center, radius, color)

	if _snatch_progress > 0.0:
		_draw_cross(center)


## Четыре луча из центра: вертикальная и горизонтальная пары, с отступом
## cross_gap от середины. Растут от нуля, поэтому крестик «раскрывается».
## Луч — ломаная в три точки, середина отведена вбок на излом: ровный крест
## читался бы прибором, а не ощущением.
func _draw_cross(center: Vector2) -> void:
	var color := cross_color
	color.a *= _snatch_progress
	var halo := cross_color
	halo.a = 0.08 * _snatch_progress
	draw_circle(center, 13.0, halo)

	var t := UI_HudMood.now()
	var kink := (0.5 + UI_HudMood.turmoil()) * (1.0 + 0.3 * UI_HudMood.noise(t * 5.0, 1.0))
	var length: float = cross_length * _snatch_progress
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var side := Vector2(-direction.y, direction.x)
		var points := PackedVector2Array([
			center + direction * cross_gap,
			center + direction * (cross_gap + length * 0.5) + side * 0.6 * kink,
			center + direction * (cross_gap + length) - side * 0.3 * kink,
		])
		draw_polyline(points, color, cross_width, true)
		draw_circle(points[0], cross_width / 2.0, color)
		draw_circle(points[2], cross_width / 2.0, color)
