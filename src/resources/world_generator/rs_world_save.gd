## res://src/resources/world_generator/rs_world_save.gd
## Персистентное состояние ОДНОГО прохождения игры (не комплекса!).
## "Новая игра" создаёт новый world_seed и обнуляет death_count.
##
## Комплекс НЕ сериализуется покомнатно: он детерминированно восстанавливается
## из (world_seed, death_count) при входе (см. RunManager.enter_complex), а сейв
## хранит только то, что из сида не выводится, — где игрок остановился и сколько
## у БФЖ осталось запаса распада.
class_name RS_WorldSave
extends Resource

@export var world_seed: int = 0
@export var death_count: int = 0

@export_group("Прогресс забега")
## Есть ли НЕЗАВЕРШЁННЫЙ забег. false (новая игра / смерть / побег на поверхность)
## = загрузка начинает с входного узла графа.
@export var run_in_progress: bool = false
## Узел графа, в котором игрок был на момент последнего сохранения. Валиден
## только при run_in_progress; при рассинхроне с графом RunManager откатится на
## входной узел.
@export var current_node_id: StringName = &""
## Посещённые узлы текущего забега — под карту комплекса и статистику.
@export var visited_node_ids: Array[StringName] = []
## Остаток C_Lifespan БФЖ. Отрицательное = "не сохранено" (берём полный запас
## из компонента). Сохраняем, чтобы загрузка не работала как бесплатное
## восстановление распада.
@export var lifespan_remaining: float = -1.0


## Детерминированный сид генерации комплекса из состояния прохождения. Каждая
## смерть (death_count++) даёт другую раскладку при том же world_seed.
func run_seed() -> int:
	return hash([world_seed, death_count])


## Сбрасывает прогресс забега, оставляя прохождение (world_seed/death_count).
func clear_run() -> void:
	run_in_progress = false
	current_node_id = &""
	visited_node_ids.clear()
	lifespan_remaining = -1.0
