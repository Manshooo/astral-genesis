## res://src/resources/world_generator/rs_room_layout.gd
## Геометрические соглашения комнат: к какой стене прижата дверь; общее место для рантайма и редакторской проверки (правило «где север» одно).
## Стена двери — сторона клетки (SquareGridTopology.Side); имена стен только для людей (slot_id, сообщения). Только статика;
## кэши «сцена → …» читает и фоновая генерация, поэтому сцены кладутся заранее (warm_scene_cache). Вики: [[Цикл забега]].
@tool
class_name RS_RoomLayout
extends RefCounted

## Имя стены по индексу стороны — так стены называют slot_id дверей в сценах.
const SIDE_NAMES: Array[StringName] = [&"north", &"east", &"south", &"west"]


## Имя стены стороны side; "" — стороны нет.
static func side_name(side: int) -> StringName:
	return SIDE_NAMES[side] if side >= 0 and side < SIDE_NAMES.size() else &""


## Сторона, к которой прижата дверь — по ГЕОМЕТРИИ, не по slot_id (в пресетах vertical_hub_* он не совпадает со стеной). NO_SIDE — двери или комнаты нет.
static func door_side(door: Node3D, room: Node) -> int:
	if door == null or room == null:
		return GridTopology.NO_SIDE
	var offset := origin_relative_to(door, room)
	if absf(offset.x) >= absf(offset.z):
		return SquareGridTopology.Side.EAST if offset.x > 0.0 else SquareGridTopology.Side.WEST
	return SquareGridTopology.Side.SOUTH if offset.z > 0.0 else SquareGridTopology.Side.NORTH


## Положение узла относительно корня комнаты: global_transform не годится — комнату разглядываем detached.
static func origin_relative_to(node: Node3D, room: Node) -> Vector3:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != room:
		var spatial := parent as Node3D
		if spatial:
			result = spatial.transform * result
		parent = parent.get_parent()
	return result.origin


## Все двери комнаты (сущности с C_DoorSlot), в порядке обхода.
static func door_entities(room: Node) -> Array[Entity]:
	var doors: Array[Entity] = []
	if room == null:
		return doors
	# owned=false — иначе двери из инстансов под-сцен не находятся.
	for node in room.find_children("*", "Entity", true, false):
		var entity := node as Entity
		if entity and has_door_slot(entity):
			doors.append(entity)
	return doors


## Есть ли на сущности слот двери: смотрим и has_component (в мире), и component_resources (detached — компоненты ещё не разложены).
static func has_door_slot(entity: Entity) -> bool:
	if entity.has_component(C_DoorSlot):
		return true
	for component in entity.component_resources:
		if component is C_DoorSlot:
			return true
	return false


## slot_id двери — из компонента, иначе из component_resources.
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


## Кэш «путь сцены → стороны дверей» (зависят только от сцены).
static var _sides_by_scene: Dictionary[String, Array] = {}


## Стороны дверей по пути сцены без инстанцирования; массив из кэша общий — менять после копии. Ради кэша раскладка слоя считается для ЛЮБОГО слоя (карта комплекса, незагруженные слои).
static func door_sides_of_scene(scene_path: String) -> Array[int]:
	if _sides_by_scene.has(scene_path):
		return _sides_by_scene[scene_path]

	var sides: Array[int] = []
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := _instantiate_detached(scene_path)
		sides = door_sides(room)
		room.free()
	_sides_by_scene[scene_path] = sides
	return sides


## Кэш «путь сцены → половина габарита».
static var _half_extent_by_scene: Dictionary[String, float] = {}


## Половина габарита комнаты в метрах — по удалению дверей от центра (они у стен); для коробки пикинга в «Генераторе мира». 0.0 — дверей нет, мерить нечем.
static func half_extent_of_scene(scene_path: String) -> float:
	if _half_extent_by_scene.has(scene_path):
		return _half_extent_by_scene[scene_path]

	var extent := 0.0
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := _instantiate_detached(scene_path)
		for door in door_entities(room):
			var offset := origin_relative_to(door as Node as Node3D, room)
			extent = maxf(extent, maxf(absf(offset.x), absf(offset.z)))
		room.free()
	_half_extent_by_scene[scene_path] = extent
	return extent


## Кэш «путь сцены → число дверей».
static var _door_count_by_scene: Dictionary[String, int] = {}


## Сколько дверей (C_DoorSlot) в сцене — степень комнаты в коридорной генерации; фактические, не RS_RoomPreset.slot_count (рассинхрон дал бы ребро без двери). Не стороны.
static func door_count_of_scene(scene_path: String) -> int:
	if _door_count_by_scene.has(scene_path):
		return _door_count_by_scene[scene_path]

	var count := 0
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := _instantiate_detached(scene_path)
		count = door_entities(room).size()
		room.free()
	_door_count_by_scene[scene_path] = count
	return count


## Кэш «путь сцены → C_RoomShell или null».
static var _shell_by_scene: Dictionary[String, C_RoomShell] = {}


## Коробка сборной комнаты — C_RoomShell на корне сцены; null — двери запечены. Смотрим и has_component, и component_resources (detached).
static func shell_of_scene(scene_path: String) -> C_RoomShell:
	if _shell_by_scene.has(scene_path):
		return _shell_by_scene[scene_path]

	var shell: C_RoomShell = null
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := _instantiate_detached(scene_path)
		shell = shell_of(room)
		room.free()
	_shell_by_scene[scene_path] = shell
	return shell


## C_RoomShell на корне инстанцированной комнаты или null.
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


## Footprint в клетках (X, уровни Y, Z); у комнаты с дверями в сцене — одна клетка.
static func footprint_of_scene(scene_path: String) -> Vector3i:
	var shell := shell_of_scene(scene_path)
	return shell.size if shell else Vector3i.ONE


## Сколько сокетов у сборной комнаты; 0 — двери в сцене.
static func socket_count_of_scene(scene_path: String) -> int:
	return sockets_of_scene(scene_path).size()


## Сокеты сборной комнаты в осях сцены от нижней северо-западной клетки: объявленные коробкой, иначе все грани нижнего уровня по периметру. Пусто — двери в сцене.
static func sockets_of_scene(scene_path: String) -> Array[Vector4i]:
	var shell := shell_of_scene(scene_path)
	if shell == null:
		return []
	return sockets_of_shell(shell)


## Сокеты коробки shell — по разобранному компоненту (сборка стен получает корень, не путь).
static func sockets_of_shell(shell: C_RoomShell) -> Array[Vector4i]:
	if not shell.door_sockets.is_empty():
		return shell.door_sockets
	return SquareGridTopology.new().perimeter(SquareGridTopology.box(Vector3i.ZERO, shell.size))


## Сокеты комнаты в плане: грани мира при угловой клетке anchor и повороте turns.
static func sockets_in_plan(scene_path: String, turns: int, anchor: Vector3i) -> Array[Vector4i]:
	var faces: Array[Vector4i] = []
	var size := footprint_of_scene(scene_path)
	for face in sockets_of_scene(scene_path):
		faces.append(face_in_plan(face, size, turns, anchor))
	return faces


## Грань в осях сцены -> грань плана: сцена поворачивается вокруг центра footprint на turns четвертей, поэтому клетка крутится в полуклетках (остаться в целых);
## size — footprint в осях сцены, при нечётном повороте ширина и длина меняются местами.
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
	# Полуклетки здесь неотрицательны, отбрасывание дробной части = деление вниз.
	@warning_ignore("integer_division")
	var cell := anchor + Vector3i((x + world.x - 1) / 2, face.y, (z + world.z - 1) / 2)
	return GridTopology.face(cell, posmod(face.w - t, SquareGridTopology.SIDE_COUNT))


## Четверти оборота (как rotation.y у RS_CorridorKit), разворачивающие деталь с северной грани к стороне side: север — 0, запад — 1, восток — 3.
static func north_piece_turns(side: int) -> int:
	return posmod(-side, SquareGridTopology.SIDE_COUNT)


## Сколько раз сцена инстанцировалась не на главном потоке (_instantiate_detached) — читает проверка фоновой генерации.
static var off_main_thread_instances := 0


## Заполняет кэши для scene_paths на главном потоке, до ухода генерации в фон (RS_LevelGraph.scene_paths).
static func warm_scene_cache(scene_paths: Array[String]) -> void:
	for path in scene_paths:
		shell_of_scene(path)
		door_count_of_scene(path)
		door_sides_of_scene(path)


## Сцена комнаты вне дерева — прочитать двери или коробку. Только с главного потока: узлы, которые рисуют, из другого создавать небезопасно (рендер «Safe»).
## Промах кэша в фоне — ошибка прогрева: громко, со счётчиком, но со сценой — иначе генерация молча построила бы другой мир.
static func _instantiate_detached(scene_path: String) -> Node:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		off_main_thread_instances += 1
		push_error("RS_RoomLayout: сцена «%s» инстанцирована не на главном потоке — её нет в прогреве (RS_LevelGraph.scene_paths)" % scene_path)
	return (load(scene_path) as PackedScene).instantiate()


## Сбрасывает кэши: живут всю сессию редактора, без сброса «Пересобрать» покажет СТАРУЮ раскладку. Рантайму не нужен.
static func clear_scene_cache() -> void:
	_sides_by_scene.clear()
	_half_extent_by_scene.clear()
	_door_count_by_scene.clear()
	_shell_by_scene.clear()
