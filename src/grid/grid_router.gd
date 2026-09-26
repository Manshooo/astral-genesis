## res://src/grid/grid_router.gd
## Поиск трассы по сетке: самый дешёвый путь от клетки до цели, где шаг стоит 1,
## а поворот — дороже. Пишется поверх топологии и ничего не знает о её форме:
## «прямо» — выход через сторону напротив входа (GridTopology.opposite), поэтому
## и на другой сетке цена поворота значит то же самое.
##
## Без цены поворота все кратчайшие пути равны, и поиск выдаёт «лесенку» — на ките
## это ряд угловых кусков вместо прямого коридора.
@tool
class_name GridRouter
extends RefCounted


## Самый дешёвый путь от [param start] до первой клетки, где [param goal]
## истинна: шаг стоит 1, поворот — [param turn_cost] сверху. Путь — от start до
## этой клетки ВКЛЮЧИТЕЛЬНО; пустой — не нашлось.
##
## [param passable] решает за каждую клетку, кроме целевых, в том числе где
## кончается область поиска: у сетки своих границ нет, и без ограничения поиск
## при недостижимой цели не остановился бы.
##
## Дейкстра по состояниям «клетка + сторона, через которую вошли» — иначе цену
## поворота не посчитать; очередь — вёдрами по цене, цены здесь мелкие целые.
## Соседи перебираются по порядку сторон, и при равной цене побеждает первый
## найденный: трасса обязана быть одной и той же от запуска к запуску.
static func find_path(
	topology: GridTopology, start: Vector3i, goal: Callable, passable: Callable, turn_cost: int
) -> Array[Vector3i]:
	var origin := Vector4i(start.x, start.y, start.z, GridTopology.NO_SIDE)
	var best: Dictionary[Vector4i, int] = {origin: 0}
	var came: Dictionary[Vector4i, Vector4i] = {}
	var buckets: Array[Array] = [[origin]]
	var cost := 0
	while cost < buckets.size():
		var bucket: Array = buckets[cost]
		for state: Vector4i in bucket:
			if best[state] != cost:
				continue  # устаревшая запись: сюда уже дошли дешевле
			var cell := Vector3i(state.x, state.y, state.z)
			if state != origin and goal.call(cell):
				return _unwind(came, origin, state)
			var entry := state.w
			var straight := GridTopology.NO_SIDE if entry == GridTopology.NO_SIDE else topology.opposite(cell, entry)
			for side in topology.side_count(cell):
				var next := topology.neighbour(cell, side)
				if not goal.call(next) and not passable.call(next):
					continue
				var step := 1
				if entry != GridTopology.NO_SIDE and side != straight:
					step += turn_cost
				var back := topology.back_side(cell, side)
				var next_state := Vector4i(next.x, next.y, next.z, back)
				var total := cost + step
				if best.has(next_state) and best[next_state] <= total:
					continue
				best[next_state] = total
				came[next_state] = state
				while buckets.size() <= total:
					buckets.append([])
				buckets[total].append(next_state)
		cost += 1
	return []


static func _unwind(came: Dictionary[Vector4i, Vector4i], origin: Vector4i, last: Vector4i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [Vector3i(last.x, last.y, last.z)]
	var state := last
	while state != origin:
		state = came[state]
		path.push_front(Vector3i(state.x, state.y, state.z))
	return path
