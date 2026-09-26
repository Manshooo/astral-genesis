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


## Сбрасывает все кэши «сцена → …». Живут всю сессию редактора, поэтому без
## явного сброса дизайнер поправит дверь в сцене комнаты, нажмёт «Пересобрать»
## во вкладке «Генератор мира» — и увидит СТАРУЮ раскладку до перезапуска
## редактора. Зовётся из вкладки на пересборку, рантайму не нужен вовсе:
## RunManager инстанцирует граф ровно один раз за забег.
static func clear_scene_cache() -> void:
	_sides_by_scene.clear()
	_half_extent_by_scene.clear()
	_door_count_by_scene.clear()
