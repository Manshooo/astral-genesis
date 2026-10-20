## res://src/resources/run_stats/rs_run_body.gd
## Одно тело, занятое за забег, — запись в RS_RunStats.bodies; свой словарь счётчиков под показатели ПО ТЕЛУ (пока не существуют).
class_name RS_RunBody
extends Resource

## Путь сцены тела — тот же «id пресета», что в сейве (`RS_WorldSave.body_scene_path`).
@export var scene_path: String = ""

## Ключ перевода имени тела (`E_Body.display_name_key`): сводку могут показать на другом языке.
@export var name_key: StringName = &""

## Секунда забега, на которой тело занято; для порядка событий (хроника забега).
@export var taken_at: float = 0.0

## Показатели, накопленные ИМЕННО в этом теле; пусто — пока ничего не считается.
@export var counters: Dictionary[StringName, float] = {}
