## res://src/resources/world_generator/rs_room_layout.gd
## Геометрические соглашения комнат: с какой стороны стоит дверь и куда смещается
## соседняя клетка сетки при раскладке слоя.
##
## Общее место для рантайма (RunManager расставляет комнаты слоя и раздаёт рёбра
## по дверям) и редакторского инструмента (проверка сцен комнат): правило «где
## север» должно быть ОДНО, иначе инструмент будет проверять не то, что делает
## игра.
##
## Только статика — инстанцировать нечего.
@tool
class_name RS_RoomLayout
extends RefCounted

## Куда смещается соседняя клетка за дверью с этой стороны. Клетка — Vector2i(x, z);
## north = −Z, south = +Z, west = −X, east = +X. Порядок ключей фиксирован: по
## нему перебираются направления при раскладке, а она обязана быть детерминированной.
const OFFSETS := {
	&"north": Vector2i(0, -1),
	&"east": Vector2i(1, 0),
	&"south": Vector2i(0, 1),
	&"west": Vector2i(-1, 0),
}
## Сторона, которой сосед из этого направления смотрит на нас.
const OPPOSITE := {
	&"north": &"south",
	&"east": &"west",
	&"south": &"north",
	&"west": &"east",
}


## Сторона комнаты, к которой прижата дверь. Определяем по ГЕОМЕТРИИ, а не по
## C_DoorSlot.slot_id: slot_id — лишь стабильный идентификатор слота, и в
## пресетах (vertical_hub_*) он сплошь и рядом не совпадает с реальной стеной.
static func door_direction(door: Node3D, room: Node) -> StringName:
	if door == null or room == null:
		return &""
	var offset := origin_relative_to(door, room)
	if absf(offset.x) >= absf(offset.z):
		return &"east" if offset.x > 0.0 else &"west"
	return &"south" if offset.z > 0.0 else &"north"


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
static func door_directions(room: Node) -> Array[StringName]:
	var directions: Array[StringName] = []
	for door in door_entities(room):
		var direction := door_direction(door as Node as Node3D, room)
		if direction != &"" and not directions.has(direction):
			directions.append(direction)
	return directions


## Кэш «путь сцены → стороны дверей». Стороны зависят ТОЛЬКО от сцены, не от
## узла графа, поэтому считаются один раз за запуск.
static var _directions_by_scene: Dictionary[String, Array] = {}


## Стороны дверей комнаты по пути её сцены — без инстанцирования на каждый вызов.
##
## Ради этого кэша всё и затевалось: раскладка слоя (RunManager._plan_layer)
## переставала требовать заспавненные комнаты и стала считаться для ЛЮБОГО слоя —
## это нужно карте комплекса, которая рисует и незагруженные слои. Побочно
## ускорился и сам спавн: раньше каждый узел инстанцировал свою комнату только
## чтобы посчитать двери, хотя один пресет повторяется по слою многократно.
static func door_directions_of_scene(scene_path: String) -> Array[StringName]:
	if _directions_by_scene.has(scene_path):
		return _directions_by_scene[scene_path]

	var directions: Array[StringName] = []
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		directions = door_directions(room)
		room.free()
	_directions_by_scene[scene_path] = directions
	return directions
