## res://src/resources/world_generator/rs_world_save.gd
## Персистентное состояние ОДНОГО прохождения (не комплекса): комплекс выводится из (world_seed, death_count), здесь только то, что из сида не выводится.
## Вики: [[Цикл забега]] §5.
@tool  # читается вкладкой «Генератор мира» — «Забег из сейва»
class_name RS_WorldSave
extends Resource

@export var world_seed: int = 0
@export var death_count: int = 0
## Итоги последнего ЗАВЕРШЁННОГО забега (экран итогов); clear_run() их не трогает.
@export var last_run: RS_RunStats
## Игра пройдена (RunManager.finish_run): свойство прохождения; сейв после финала помечается, а не стирается — ради концовки в главном меню.
@export var game_completed: bool = false

@export_group("Прогресс забега")
## Есть ли НЕЗАВЕРШЁННЫЙ забег; false = загрузка начинает с входного узла.
@export var run_in_progress: bool = false
## Узел на момент сохранения; валиден при run_in_progress, при рассинхроне RunManager откатится на вход.
@export var current_node_id: StringName = &""
## Посещённые узлы текущего забега — под карту и статистику.
@export var visited_node_ids: Array[StringName] = []
## Остаток C_Lifespan; отрицательное — «не сохранено».
@export var lifespan_remaining: float = -1.0
## Статистика идущего забега (RunStats.current — ТОТ ЖЕ объект): «выход в меню» забег не кончает.
@export var run_stats: RS_RunStats
## Снимок RS_WorldGenConfig на старте ЭТОГО забега: сид задаёт комплекс только вместе с ручками. null — забег до снимков, берётся текущий конфиг.
@export var gen_config: RS_WorldGenConfig
## Версия генератора, на которой начат забег (RS_LevelGraph.GENERATOR_VERSION); с другой забег сбрасывается на вход. 0 — до версионирования.
@export var generator_version: int = 0

@export_group("Воплощение")
## Сцена тела, в котором БФЖ сейчас; "" = призрак. Путь («id пресета»), не облик — меш живёт в сцене тела (E_Body.visual_of).
@export var body_scene_path: String = ""
## HP занятого тела (значимо при непустом body_scene_path); потолок — состояние, его правят скиллы.
@export var body_health: float = 0.0
@export var body_health_max: float = 0.0
## Остаток кармана тела и его объём (C_BodyDecay): иначе загрузка вернула бы тело с полным запасом.
@export var body_lifespan_remaining: float = 0.0
@export var body_lifespan_max: float = 0.0
## Поглощённые способности (C_AbilityLoadout): слоты души по индексу (null — пусто) и банк. Копии компонентов — числа
## способности переживают правку сцены тела, как потолки HP и запаса.
@export var ability_slots: Array[C_Ability] = []
@export var ability_bank: Array[C_Ability] = []
## Тела, уже поглощённые в забеге (C_BodyOrigin.body_id): комнаты из сида, без пометки съеденное воскресло бы.
@export var consumed_body_ids: Array[StringName] = []
## Узлы, чью разовую награду забега уже забрали (встреча с Архитектором); иначе выход в меню давал бы награду заново.
@export var rewarded_node_ids: Array[StringName] = []


## Сид генерации из состояния прохождения; каждая смерть даёт другую раскладку.
func run_seed() -> int:
	return hash([world_seed, death_count])


## Снимок ручек для продолжения забега, или null (забега нет или другой генератор). Здесь, а не в RunManager: спрашивает и «Генератор мира» («Забег из сейва»).
func resumable_gen_config() -> RS_WorldGenConfig:
	if not run_in_progress or gen_config == null:
		return null
	if generator_version != RS_LevelGraph.GENERATOR_VERSION:
		return null
	return gen_config


## Сбрасывает прогресс забега, оставляя прохождение (world_seed/death_count).
func clear_run() -> void:
	run_in_progress = false
	current_node_id = &""
	visited_node_ids.clear()
	lifespan_remaining = -1.0
	# ОТВЯЗЫВАЕМ, а не чистим: снятый снимок (RunStats.last) держит этот же объект.
	run_stats = null
	# Следующий забег — по ручкам на его старте.
	gen_config = null
	generator_version = 0
	# Воплощение — состояние забега: новый начинается призраком, тела снова целы.
	body_scene_path = ""
	body_health = 0.0
	body_health_max = 0.0
	body_lifespan_remaining = 0.0
	body_lifespan_max = 0.0
	ability_slots = []
	ability_bank = []
	consumed_body_ids.clear()
	rewarded_node_ids.clear()
