## res://src/resources/rs_body_thoughts.gd
## Мысли поглощённых: что БФЖ думает чужой головой после захвата тела вида. Данные — data/body_thoughts.tres,
## читает O_BodyThoughts. Вид — по пути сцены тела (как C_Embodied.body_scene_path), а не по имени и классу: учёный и
## военный — одно скрипт-семейство, разные сцены. У неизвестного вида мысль запасная.
@tool
class_name RS_BodyThoughts
extends Resource

## Мысль для тела, которого в thoughts нет; ключ перевода.
@export var default_key: StringName = &"THOUGHT_DEFAULT"

## Путь сцены тела → ключи мыслей (ui.csv); несколько — на выбор, чтобы не повторяться. Пример: `"res://src/entities/body/e_body_walker.tscn": PackedStringArray("THOUGHT_BODY_WALKER")`
@export var thoughts: Dictionary[String, PackedStringArray] = {}


## Ключ мысли для тела со сценой scene_path: случайный из записи вида либо запасной (пустой путь — запасной).
func pick(scene_path: String) -> StringName:
	var keys: PackedStringArray = thoughts.get(scene_path, PackedStringArray())
	if keys.is_empty():
		return default_key
	return StringName(keys[randi() % keys.size()])
