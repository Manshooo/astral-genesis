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

@export_group("Воплощение")
## Сцена тела, в котором БФЖ находится сейчас; "" = развоплощён (призрак).
## Храним путь («id пресета»), а не сам облик: меш живёт в сцене тела, писать его
## в сейв — дублировать источник правды (см. E_Body.visual_of). Из пути же
## выводится всё, что тело даёт при вселении.
@export var body_scene_path: String = ""
## HP занятого тела на момент сохранения. Значимо только при непустом
## body_scene_path. Текущее и потолок — оба состояние: потолок правят скиллы,
## поэтому пересчитывать его из сцены при загрузке было бы неверно.
@export var body_health: float = 0.0
@export var body_health_max: float = 0.0
## Остаток кармана тела и его исходный объём (C_BodyDecay.remaining/maximum).
## Тоже состояние: во плоти распад платится именно отсюда, и без этих чисел
## загрузка возвращала бы тело с полным запасом времени.
@export var body_lifespan_remaining: float = 0.0
@export var body_lifespan_max: float = 0.0
## Тела, уже поглощённые в этом забеге (C_BodyOrigin.body_id). Комнаты
## восстанавливаются из сида, а не из сейва, поэтому без этой пометки съеденное
## тело возродилось бы нетронутым — рядом с игроком, который в нём и сидит.
@export var consumed_body_ids: Array[StringName] = []


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
	# Воплощение — состояние забега, а не прохождения: новый забег начинается
	# призраком, и все тела комплекса снова целы.
	body_scene_path = ""
	body_health = 0.0
	body_health_max = 0.0
	body_lifespan_remaining = 0.0
	body_lifespan_max = 0.0
	consumed_body_ids.clear()
