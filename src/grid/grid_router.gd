## res://src/grid/grid_router.gd
## Поиск трассы по сетке: самый дешёвый путь, шаг стоит 1, поворот дороже (без этого кратчайшие равны и выходит «лесенка»).
## Поверх топологии, формы не знает: «прямо» — GridTopology.opposite. Вики: [[Цикл забега]] (сетка уровня).
@tool
class_name GridRouter
extends RefCounted


## Самый дешёвый путь от start до первой клетки, где goal истинна; путь включает обе, пустой — не нашлось.
## [param passable] решает за каждую клетку и задаёт границы области (у сетки своих нет). Дейкстра по «клетка + сторона
## входа», вёдра по цене; при равной цене побеждает первый найденный — трасса одна и та же от запуска к запуску.
## [param max_cost] (−1 — без предела) — потолок цены: путь дешевле потолка тот же, что и без него.
static func find_path(
	topology: GridTopology, start: Vector3i, goal: Callable, passable: Callable, turn_cost: int,
	max_cost: int = -1
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
				if max_cost >= 0 and total > max_cost:
					continue
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
