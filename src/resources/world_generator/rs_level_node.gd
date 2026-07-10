## res://src/resources/level_gen/rs_level_node.gd
## Один узел графа уровня - комната/зал/кластер.
## Реальная сцена комнаты подбирается по tags через RS_RoomPresetLibrary
## и лежит в room_scene_path после генерации.
class_name RS_LevelNode
extends Resource

@export var id: StringName = &""
## L3 = 3 ... L0 = 0, соответствует слоям из ТЗ.
@export var depth: int = 3
## Путь до .tscn выбранного пресета комнаты. Заполняется генератором,
## не редактируется руками.
@export var room_scene_path: String = ""
## Теги для подбора пресета и для игровой логики ("vertical_hub", "level_exit",
## "hazard", "loot", "safe_room" и т.д.)
@export var tags: Array[StringName] = []
@export var connections: Array[RS_LevelConnection] = []


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


func add_tag_unique(tag: StringName) -> void:
	if not tags.has(tag):
		tags.append(tag)


func get_connection_to(target_id: StringName) -> RS_LevelConnection:
	for c in connections:
		if c.target_node_id == target_id:
			return c
	return null
