## res://src/resources/world_generator/rs_room_layout.gd
## Геометрические соглашения комнат: к какой стене прижата дверь.
##
## Общее место для рантайма (RunManager расставляет комнаты слоя и раздаёт рёбра
## по дверям) и редакторского инструмента (проверка сцен комнат): правило «где
## север» должно быть ОДНО, иначе инструмент будет проверять не то, что делает
## игра.
##
## Стена двери — сторона клетки квадратной сетки (SquareGridTopology.Side):
## комната стоит в клетке плана, и дверь смотрит в соседа за этой стороной.
## Имена стен остаются только для людей — slot_id дверей в сценах и сообщения
## проверок.
##
## Только статика — инстанцировать нечего.
@tool
class_name RS_RoomLayout
extends RefCounted

## Имя стены по индексу стороны — так стены называют slot_id дверей в сценах.
const SIDE_NAMES: Array[StringName] = [&"north", &"east", &"south", &"west"]


## Имя стены стороны [param side]; "" — стороны нет.
static func side_name(side: int) -> StringName:
	return SIDE_NAMES[side] if side >= 0 and side < SIDE_NAMES.size() else &""


## Сторона комнаты, к которой прижата дверь. Определяем по ГЕОМЕТРИИ, а не по
## C_DoorSlot.slot_id: slot_id — лишь стабильный идентификатор слота, и в
## пресетах (vertical_hub_*) он сплошь и рядом не совпадает с реальной стеной.
## GridTopology.NO_SIDE — двери или комнаты нет.
static func door_side(door: Node3D, room: Node) -> int:
	if door == null or room == null:
		return GridTopology.NO_SIDE
	var offset := origin_relative_to(door, room)
	if absf(offset.x) >= absf(offset.z):
		return SquareGridTopology.Side.EAST if offset.x > 0.0 else SquareGridTopology.Side.WEST
	return SquareGridTopology.Side.SOUTH if offset.z > 0.0 else SquareGridTopology.Side.NORTH


## Положение узла относительно корня комнаты. global_transform не годится:
## Node3D узнаёт своего родителя только при входе в SceneTree, а комнату мы
## разглядываем ещё detached — поэтому складываем локальные трансформы вручную.
static func origin_relative_to(node: Node3D, room: Node) -> Vector3:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != room:
		var spatial := parent as Node3D
		if spatial:
			result = spatial.transform * result
		parent = parent.get_parent()
	return result.origin


## Все двери комнаты (сущности с C_DoorSlot), в порядке обхода дерева.
static func door_entities(room: Node) -> Array[Entity]:
	var doors: Array[Entity] = []
	if room == null:
		return doors
	# owned=false — иначе двери, вставленные как инстансы под-сцены, не находятся.
	for node in room.find_children("*", "Entity", true, false):
		var entity := node as Entity
		if entity and has_door_slot(entity):
			doors.append(entity)
	return doors


## Есть ли на сущности слот двери. Смотрим И has_component (сущность уже в мире,
## _initialize отработал), И component_resources (detached-инстанс — компоненты
## ещё «не разложены», но @export-массив доступен сразу после instantiate).
static func has_door_slot(entity: Entity) -> bool:
	if entity.has_component(C_DoorSlot):
		return true
	for component in entity.component_resources:
		if component is C_DoorSlot:
			return true
	return false


## slot_id двери — из компонента, если он уже разложен, иначе из component_resources.
static func slot_id_of(entity: Entity) -> StringName:
	var slot := entity.get_component(C_DoorSlot) as C_DoorSlot
	if slot:
		return slot.slot_id
	for component in entity.component_resources:
		if component is C_DoorSlot:
			return (component as C_DoorSlot).slot_id
	return &""


## Стороны, с которых у комнаты есть дверь (без повторов).
static func door_sides(room: Node) -> Array[int]:
	var sides: Array[int] = []
	for door in door_entities(room):
		var side := door_side(door as Node as Node3D, room)
		if side != GridTopology.NO_SIDE and not sides.has(side):
			sides.append(side)
	return sides


## Кэш «путь сцены → стороны дверей». Стороны зависят ТОЛЬКО от сцены, не от
## узла графа, поэтому считаются один раз за запуск.
static var _sides_by_scene: Dictionary[String, Array] = {}


## Стороны дверей комнаты по пути её сцены — без инстанцирования на каждый вызов.
## Массив из кэша общий: зовущий, которому нужно его менять, делает копию.
##
## Ради этого кэша всё и затевалось: раскладка слоя (RS_LayerPlan)
## переставала требовать заспавненные комнаты и стала считаться для ЛЮБОГО слоя —
## это нужно карте комплекса, которая рисует и незагруженные слои. Побочно
## ускорился и сам спавн: раньше каждый узел инстанцировал свою комнату только
## чтобы посчитать двери, хотя один пресет повторяется по слою многократно.
static func door_sides_of_scene(scene_path: String) -> Array[int]:
	if _sides_by_scene.has(scene_path):
		return _sides_by_scene[scene_path]

	var sides: Array[int] = []
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		sides = door_sides(room)
		room.free()
	_sides_by_scene[scene_path] = sides
	return sides


## Кэш «путь сцены → половина габарита». Как и стороны дверей, зависит только от
## сцены, поэтому считается один раз за запуск.
static var _half_extent_by_scene: Dictionary[String, float] = {}


## Половина габарита комнаты в метрах — по тому, как далеко от центра стоят её
## двери. Двери прижаты к стенам, так что это и есть расстояние до стены. Нужна
## коробке пикинга комнаты в «Генераторе мира»: клетка раскладки у комнат с
## разной геометрией заполнена по-разному, а клик должен ловить саму комнату.
##
## 0.0 — дверей нет, мерить нечем; зовущий решает, что с этим делать.
static func half_extent_of_scene(scene_path: String) -> float:
	if _half_extent_by_scene.has(scene_path):
		return _half_extent_by_scene[scene_path]

	var extent := 0.0
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		for door in door_entities(room):
			var offset := origin_relative_to(door as Node as Node3D, room)
			extent = maxf(extent, maxf(absf(offset.x), absf(offset.z)))
		room.free()
	_half_extent_by_scene[scene_path] = extent
	return extent


## Кэш «путь сцены → число дверей». Как и стороны, зависит только от сцены.
static var _door_count_by_scene: Dictionary[String, int] = {}


## Сколько дверей (сущностей с C_DoorSlot) в сцене комнаты. В коридорной
## генерации это и есть степень комнаты: каждая дверь получает ребро в ветку
## коридора, поэтому считать надо фактические двери сцены, а не заявленный
## RS_RoomPreset.slot_count — рассинхрон дал бы ребро без двери или дверь без
## ребра. Не стороны: две двери на одной стене — всё равно две двери.
static func door_count_of_scene(scene_path: String) -> int:
	if _door_count_by_scene.has(scene_path):
		return _door_count_by_scene[scene_path]

	var count := 0
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		count = door_entities(room).size()
		room.free()
	_door_count_by_scene[scene_path] = count
	return count


## Кэш «путь сцены → C_RoomShell или null». Как и двери, зависит только от сцены.
static var _shell_by_scene: Dictionary[String, C_RoomShell] = {}


## Коробка комнаты, собранной по маске сокетов, — C_RoomShell на корне сцены; null —
## двери запечены в сцену. Корень смотрим и через has_component, и через
## component_resources — по той же причине, что и has_door_slot: комнату здесь
## разглядывают detached, компоненты ещё не разложены.
static func shell_of_scene(scene_path: String) -> C_RoomShell:
	if _shell_by_scene.has(scene_path):
		return _shell_by_scene[scene_path]

	var shell: C_RoomShell = null
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		shell = shell_of(room)
		room.free()
	_shell_by_scene[scene_path] = shell
	return shell


## C_RoomShell на корне уже инстанцированной комнаты или null.
static func shell_of(room: Node) -> C_RoomShell:
	var entity := room as Entity
	if entity == null:
		return null
	var shell := entity.get_component(C_RoomShell) as C_RoomShell
	if shell:
		return shell
	for component in entity.component_resources:
		if component is C_RoomShell:
			return component
	return null


## Footprint комнаты в клетках (ширина по X, уровней по Y, длина по Z). У комнаты
## с дверями в сцене — одна клетка: её арт и есть клетка.
static func footprint_of_scene(scene_path: String) -> Vector3i:
	var shell := shell_of_scene(scene_path)
	return shell.size if shell else Vector3i.ONE


## Сколько сокетов у комнаты, собранной по маске (sockets_of_scene). 0 — у
## комнаты двери в сцене, и сокетов у неё нет.
static func socket_count_of_scene(scene_path: String) -> int:
	return sockets_of_scene(scene_path).size()


## Сокеты комнаты, собранной по маске, — в осях сцены, от нижней северо-западной
## клетки footprint (как C_RoomShell.door_sockets): объявленные коробкой, а если
## она их не объявила — все грани нижнего уровня по периметру. Пусто — у комнаты
## двери в сцене.
static func sockets_of_scene(scene_path: String) -> Array[Vector4i]:
	var shell := shell_of_scene(scene_path)
	if shell == null:
		return []
	if not shell.door_sockets.is_empty():
		return shell.door_sockets
	return SquareGridTopology.new().perimeter(SquareGridTopology.box(Vector3i.ZERO, shell.size))


## Сокеты комнаты в плане: грани мира, если комната стоит угловой клеткой в
## [param anchor] и повёрнута на [param turns] (RS_LevelNode.turns).
static func sockets_in_plan(scene_path: String, turns: int, anchor: Vector3i) -> Array[Vector4i]:
	var faces: Array[Vector4i] = []
	var size := footprint_of_scene(scene_path)
	for face in sockets_of_scene(scene_path):
		faces.append(face_in_plan(face, size, turns, anchor))
	return faces


## Грань [param face] в осях сцены (клетка от нижней северо-западной и сторона) —
## в грань плана. Сцена поворачивается вокруг центра footprint на [param turns]
## четвертей (RS_LayerPlan.room_transform: сторона сцены s смотрит в мир стороной
## s − turns), поэтому и клетка крутится вокруг центра: считается в полуклетках от
## него, чтобы остаться в целых. [param size] — footprint в осях сцены; в мире у
## нечётного поворота ширина и длина меняются местами, и угловой клеткой
## становится другая.
static func face_in_plan(face: Vector4i, size: Vector3i, turns: int, anchor: Vector3i) -> Vector4i:
	var t := posmod(turns, SquareGridTopology.SIDE_COUNT)
	var x := face.x * 2 + 1 - size.x
	var z := face.z * 2 + 1 - size.z
	for i in t:
		# Четверть оборота по turn_basis: север (0, −1) уходит на запад (−1, 0).
		var turned := z
		z = -x
		x = turned
	var world := Vector3i(size.z, size.y, size.x) if t % 2 else size
	var cell := anchor + Vector3i((x + world.x - 1) / 2, face.y, (z + world.z - 1) / 2)
	return GridTopology.face(cell, posmod(face.w - t, SquareGridTopology.SIDE_COUNT))


## Четверти оборота вокруг Y (как rotation.y у кусков RS_CorridorKit), которые
## разворачивают деталь, нарисованную на северной грани клетки, к стороне
## [param side]: север остаётся на месте, запад — четверть против часовой, восток —
## три.
static func north_piece_turns(side: int) -> int:
	return posmod(-side, SquareGridTopology.SIDE_COUNT)


## Сбрасывает все кэши «сцена → …». Живут всю сессию редактора, поэтому без
## явного сброса дизайнер поправит дверь в сцене комнаты, нажмёт «Пересобрать»
## во вкладке «Генератор мира» — и увидит СТАРУЮ раскладку до перезапуска
## редактора. Зовётся из вкладки на пересборку, рантайму не нужен вовсе:
## RunManager инстанцирует граф ровно один раз за забег.
static func clear_scene_cache() -> void:
	_sides_by_scene.clear()
	_half_extent_by_scene.clear()
	_door_count_by_scene.clear()
	_shell_by_scene.clear()
