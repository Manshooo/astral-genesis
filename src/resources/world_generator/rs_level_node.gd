## res://src/resources/world_generator/rs_level_node.gd
## Один узел графа уровня — комната или коридор. Чистые данные; сцена подбирается RS_RoomPresetLibrary и лежит в room_scene_path после генерации.
@tool  # граф строится в т.ч. из редакторской вкладки «Генератор мира» — см. RS_LevelGraph
class_name RS_LevelNode
extends Resource

## Роль узла: комната получает рёбер столько, сколько у неё дверей (door_count); коридор — ветка этажа, сцены нет, собирается из тайлов по трассе.
enum Role { ROOM, CORRIDOR }

@export var id: StringName = &""
@export var role: Role = Role.ROOM
## L5 (дно) … L0 (поверхность); домашний слой — L3.
@export var depth: int = 3
## Этаж ВНУТРИ слоя (0-indexed); слой в дереве целиком, поэтому это метка для группировки.
@export var floor_index: int = 0
## Сквозной индекс внутри слоя; детерминирован — от него зависит, куда встанет комната при повторной загрузке сида.
@export var index_in_layer: int = 0
## Путь .tscn выбранного пресета; заполняет генератор.
@export var room_scene_path: String = ""
## Теги для подбора пресета и игровой логики ("vertical_hub", "level_exit", "hazard", "safe_room" …).
@export var tags: Array[StringName] = []
## Тип помещения (ключ RS_RoomTypeCatalog) — ДРУГАЯ ось, не tags; структурных обязательств не несёт. Проходит генерацию дважды: сперва
## `_assign_room_types` кладёт ЗАГАДАННЫЙ тип, затем `_assign_room_scenes` переписывает ФАКТИЧЕСКИМ — после генерации здесь правда.
@export var room_type: StringName = &""
@export var connections: Array[RS_LevelConnection] = []
## Двери узла переставляют игрока, а не открываются (копия RS_UniqueRoom.door_teleports).
@export var door_teleports: bool = false
## Сколько сокетов сборной комнаты (C_RoomShell) станут дверями — разыграно из диапазона пресета; 0 — двери запечены в сцену.
@export var socket_doors: int = 0
## Четвертей оборота вокруг Y (как rotation.y = turns·π/2); разыграно у всех комнат: сторона сцены s смотрит в мир стороной s − turns.
@export var turns: int = 0


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## Сколько у комнаты дверей — столько рёбер в коридоры: разыгранное число у сборной, C_DoorSlot в сцене у остальных.
func door_count() -> int:
	if socket_doors > 0:
		return socket_doors
	return RS_RoomLayout.door_count_of_scene(room_scene_path)


func add_tag_unique(tag: StringName) -> void:
	if not tags.has(tag):
		tags.append(tag)


func get_connection_to(target_id: StringName) -> RS_LevelConnection:
	for c in connections:
		if c.target_node_id == target_id:
			return c
	return null
