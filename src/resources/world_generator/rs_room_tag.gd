## res://src/resources/world_generator/rs_room_tag.gd
## Описание одного структурного тега комнаты (data/room_tag_catalog.tres). ОПИСАТЕЛЬНЫЙ ресурс, не разрешительный: подбор сравнивает сырые StringName,
## в каталог не заглядывает — иначе «+ тег» в Room Wizard молча ломал бы генерацию.
@tool  # каталог правится из вкладки «Редактор пресетов» — иначе placeholder
class_name RS_RoomTag
extends Resource

## Ключ тега (`floor_hub`, `vertical_hub`, `level_exit`) — он же в RS_RoomPreset.tags и RS_LevelNode.tags.
@export var id: StringName = &""

## Имя для инструментов; пустое — ключ.
@export var display_name: String = ""

## Зачем тег и когда его вешать — текст для дизайнера, в игру не попадает.
@export_multiline var description: String = ""

## Тег, который генератор ставит узлам САМ: ключ захардкожен в графе, переименовать только в пресетах нельзя (подбор сломается молча); инструменты запрещают.
@export var set_by_generator: bool = false


## Для инструментов и логов: имя, если задано, иначе ключ.
func label() -> String:
	return display_name if display_name != "" else String(id)
