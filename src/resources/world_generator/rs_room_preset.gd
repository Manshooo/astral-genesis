## res://src/resources/world_generator/rs_room_preset.gd
## Один вариант комнаты для подстановки: сцена, возможности (tags), число дверных слотов, вес. Подбор — RS_RoomPresetLibrary.
@icon("res://addons/game_design_tool/assets/room_preset.svg")
@tool  # правится и проверяется из вкладки «Редактор пресетов»
class_name RS_RoomPreset
extends Resource

## Для инспектора и логов; на логику не влияет.
@export var display_name: String = ""

## Сцена комнаты: ровно slot_count сущностей с C_DoorSlot и (по желанию) SpawnPoint.
@export var scene: PackedScene

## Возможности пресета: узел подойдёт, только если ВСЕ его теги здесь (node.tags ⊆ tags). Пусто — «обычная» комната. Примеры: "vertical_hub", "level_exit", "hazard".
@export var tags: Array[StringName] = []

## Тип помещения (ключ RS_RoomTypeCatalog): арсенал, лаборатория, склад; пусто — безликое. ОТДЕЛЬНОЕ поле, не тег: тег — жёсткий фильтр,
## и тип там стал бы требованием (на этом перестали выпадать lab_room и exit_room). Мягкое правило — RS_RoomPresetLibrary._prefer_room_type.
@export var room_type: StringName = &""

## Дверных слотов (C_DoorSlot) в сцене; должно совпадать (validate() ловит) — верхняя граница рёбер узла. У сборной комнаты — doors_min/doors_max.
@export var slot_count: int = 1

## Диапазон дверей сборной комнаты: число бросается на каждый узел (RS_LevelGraph._roll_socket_doors), сокеты выбирает раскладка; не больше сокетов footprint (validate()).
@export var doors_min: int = 1
@export var doors_max: int = 1

## Вес среди равно-подходящих; <= 0 исключает из выборки (остаётся кандидатом для fallback).
@export var weight: float = 1.0
