## res://src/resources/world_generator/rs_level_node.gd
## Один узел графа уровня — комната/зал/кластер. Чистые данные, никакой сцены.
## Реальная сцена комнаты подбирается по tags через RS_RoomPresetLibrary
## и лежит в room_scene_path после генерации.
@tool  # граф строится в т.ч. из редакторского дока «Генератор» — см. RS_LevelGraph
class_name RS_LevelNode
extends Resource

@export var id: StringName = &""
## L4 (самый глубокий) ... L0 (поверхность). Домашний слой игрока — L3.
@export var depth: int = 3
## Этаж ВНУТРИ слоя (0-indexed). В SceneTree одновременно существует весь
## слой целиком — все его этажи разом, поэтому это скорее метка для
## расстановки/группировки комнат, чем отдельная единица подгрузки.
@export var floor_index: int = 0
## Сквозной индекс комнаты внутри слоя (across всех этажей). Задаёт порядок
## комнат в ряду при раскладке слоя по сетке (RS_LayerPlan) —
## поэтому он обязан быть детерминированным: от него зависит, куда физически
## встанет комната при повторной загрузке того же сида.
@export var index_in_layer: int = 0
## Путь до .tscn выбранного пресета комнаты. Заполняется генератором,
## не редактируется руками.
@export var room_scene_path: String = ""
## Теги для подбора пресета и для игровой логики ("vertical_hub", "floor_hub",
## "level_exit", "hazard", "loot", "safe_room" и т.д.)
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
