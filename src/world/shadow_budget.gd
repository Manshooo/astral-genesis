# res://src/world/shadow_budget.gd
## Раздаёт тени лампам уровня (LevelLight), когда ячеек атласа не хватает (RS_ShadowLevel.cells_per_quadrant): иначе движок раздал бы их в порядке списка, и без тени осталась бы лампа в лицо игроку (свет сквозь стену).
## Очередь — по близости света к камере (внутри сферы — 0); дальше бюджета тень теряют. Не «игрок и соседи по графу»: замер на сиде 921090802 — в среднем 37 ламп, до 109. Лампы вне кадра и дальше ступени ячеек не занимают, тень сохраняют.
class_name ShadowBudget
extends Node

## Как часто пересчитывать очередь: лампы стоят, камера за 0.1 с заметно не уходит.
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


## Включает тень первым [method RS_ShadowLevel.lamp_budget] лампам в кадре по близости света к камере, остальным в кадре выключает. Статическая — проверка с подставной камерой.
static func distribute(lamps: Array, camera: Camera3D, level: RS_ShadowLevel) -> void:
	var eye := camera.global_position
	var queue: Array = []
	for node in lamps:
		var light := node as Light3D
		# Спрятанная лампа (LayerStreamer.reveal_around) не светит, а место в очереди заняла бы.
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
