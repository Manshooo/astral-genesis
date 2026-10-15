## res://src/resources/rs_body_thoughts.gd
## Мысли поглощённых: что БФЖ думает чужой головой в первый миг после захвата
## тела определённого вида. Данные — `data/body_thoughts.tres`, правятся в
## редакторе; читает их O_BodyThoughts.
##
## Вид тела задан путём его сцены — тем же «id пресета», которым воплощение
## живёт в сейве (`C_Embodied.body_scene_path`), а не именем и не классом: два
## вида тела одного скрипта (учёный и военный) отличаются сценой. Добавить вид —
## одна запись в `thoughts`, ни кода, ни сцены тела это не трогает.
##
## По лору БФЖ думает так, как думал поглощённый, а цель у него — чужая: каждое
## тело приносит свой страх и своё «выбраться» (карточка «Игровой цикл — от и
## до», §6). Поэтому у вида мысль своя, а у неизвестного — запасная.
@tool
class_name RS_BodyThoughts
extends Resource

## Мысль для тела, которого в [member thoughts] нет. Ключ перевода.
@export var default_key: StringName = &"THOUGHT_DEFAULT"

## Путь сцены тела → ключи мыслей (assets/locale/ui.csv). Несколько ключей у
## вида — на выбор: так одно и то же тело не повторяет одну фразу из забега в
## забег. Пример записи в .tres:
## `"res://src/entities/body/e_body_walker.tscn": PackedStringArray("THOUGHT_BODY_WALKER")`
@export var thoughts: Dictionary[String, PackedStringArray] = {}


## Ключ мысли для тела со сценой [param scene_path]: случайный из записи вида
## либо запасной. Пустой путь тоже даёт запасной — тело без сцены (созданное
## кодом) всё равно кого-то поглотило.
func pick(scene_path: String) -> StringName:
	var keys: PackedStringArray = thoughts.get(scene_path, PackedStringArray())
	if keys.is_empty():
		return default_key
	return StringName(keys[randi() % keys.size()])
