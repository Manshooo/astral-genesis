## res://src/resources/world_generator/rs_world_save.gd
## Персистентное состояние ОДНОГО прохождения игры (не комплекса!).
## "Новая игра" создаёт новый world_seed и обнуляет death_count.
## "Загрузить игру" просто восстанавливает эти два числа — сам комплекс
## всё равно генерируется заново при входе (см. RunManager.enter_complex),
## детерминированно из (world_seed, death_count).
class_name RS_WorldSave
extends Resource

@export var world_seed: int = 0
@export var death_count: int = 0
