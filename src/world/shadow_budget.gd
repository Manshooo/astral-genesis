# res://src/world/shadow_budget.gd
## Раздаёт тени лампам уровня (LevelLight), когда ячеек атласа на всех не хватает.
##
## Атлас режется на ячейки одного размера (RS_ShadowLevel.cells_per_quadrant),
## чтобы лампа вне кадра не проседала в разрешении, — и ячеек становится
## конечное число. Сколько ламп просит тень, решает движок: только те, что в
## кадре и ближе дальности ступени. Если их больше, чем ячеек, движок раздаёт
## ячейки в порядке своего списка, а не по важности, и без тени остаётся
## случайная лампа — возможно, та, что светит игроку в лицо, и её свет пройдёт
## сквозь стену. Поэтому очередь задаёт этот узел: первыми тень получают лампы,
## чей свет ближе всего к камере (камера внутри сферы света — расстояние 0),
## то есть те, что освещают помещение игрока и примыкающее к нему. Лампы
## дальше бюджета тень теряют — засветить они могут только то, что далеко.
##
## Не «узел игрока и его соседи по графу»: замер на сиде 921090802 дал в среднем
## 37 ламп на такой набор и до 109 — коридор тянется на много тайлов с лампой на
## каждом, а соседи бывают и на других этажах. Столько ячеек одного размера атлас
## не вместит, а близость света к камере выбирает то же самое, только по месту,
## а не по графу.
##
## Лампы вне кадра и дальше дальности ступени ячеек не занимают, поэтому в
## бюджет не считаются и тень сохраняют: повернул камеру — тень уже готова.
class_name ShadowBudget
extends Node

## Как часто пересчитывать очередь. Каждый кадр незачем: лампы стоят, а камера
## за 0.1 с не уходит настолько, чтобы очередь заметно поменялась.
const PERIOD := 0.1

var _wait := 0.0


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = PERIOD
	var level := SettingsManager.shadow_level()
	var camera := get_viewport().get_camera_3d()
	if level == null or camera == null:
		return
	distribute(get_tree().get_nodes_in_group(LevelLight.GROUP), camera, level)


## Включает тень первым [method RS_ShadowLevel.lamp_budget] лампам в кадре по
## близости их света к камере, остальным в кадре — выключает. Статическая — её
## зовёт проверка с подставной камерой.
static func distribute(lamps: Array, camera: Camera3D, level: RS_ShadowLevel) -> void:
	var eye := camera.global_position
	var queue: Array = []
	for node in lamps:
		var light := node as Light3D
		# Спрятанная лампа (узел дальше видимых, LayerStreamer.reveal_around) не
		# светит, а место в очереди заняла бы — и тень ушла бы у видимой.
		if not light.is_visible_in_tree():
			continue
		var distance := light.global_position.distance_to(eye)
		queue.append([maxf(0.0, distance - LevelLight.reach_of(light)), distance, light])
	queue.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var frustum := camera.get_frustum()
	var budget := level.lamp_budget()
	var used := 0
	for entry: Array in queue:
		var light: Light3D = entry[2]
		var on := true
		if entry[1] <= level.shadow_distance and _in_frustum(light, frustum):
			on = used < budget
			if on:
				used += 1
		if light.shadow_enabled != on:
			light.shadow_enabled = on


## Задевает ли сфера света лампы кадр: плоскости пирамиды камеры смотрят наружу.
static func _in_frustum(light: Light3D, frustum: Array[Plane]) -> bool:
	var reach := LevelLight.reach_of(light)
	for plane in frustum:
		if plane.distance_to(light.global_position) > reach:
			return false
	return true
