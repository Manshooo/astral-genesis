## res://src/resources/world_generator/rs_room_preset.gd
## Один вариант комнаты для процедурной подстановки.
## Чистые данные: какая сцена, что она умеет (tags), сколько в ней дверных
## слотов и с каким весом её выбирать. Подбором занимается RS_RoomPresetLibrary.
@icon("res://addons/game_design_tool/assets/room_preset.svg")
@tool  # правится и проверяется из редакторского дока «Генератор»
class_name RS_RoomPreset
extends Resource

## Для читаемости в инспекторе/логах. На логику не влияет.
@export var display_name: String = ""

## Сцена комнаты. Должна содержать ровно slot_count сущностей с C_DoorSlot и
## (по желанию) SpawnPoint. Путь берётся из scene.resource_path при подстановке.
@export var scene: PackedScene

## Возможности пресета. Узел подойдёт этому пресету, только если ВСЕ теги узла
## содержатся здесь (node.tags ⊆ tags). Пустой список = «обычная» комната,
## годная лишь для узлов без тегов. Примеры: "vertical_hub", "floor_hub",
## "level_exit", "hazard", "safe_room".
@export var tags: Array[StringName] = []

## Сколько дверных слотов (C_DoorSlot) в сцене. Должно совпадать с фактическим
## числом в scene — RS_RoomPresetLibrary.validate() ловит рассинхрон. Определяет
## верхнюю границу числа рёбер узла, которое комната может обслужить.
@export var slot_count: int = 1

## Вес взвешенного выбора среди равно-подходящих пресетов. <= 0 исключает из
## случайной выборки (но пресет всё ещё считается кандидатом для fallback-логики).
@export var weight: float = 1.0
