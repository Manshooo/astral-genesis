# res://src/autoloads/run_stats.gd
extends Node
## Собирает статистику забега ПО ХОДУ забега и держит снимок последнего
## завершённого — его показывает экран итогов.
##
## ПОЧЕМУ ПО ХОДУ, А НЕ В КОНЦЕ. В конце собирать не из чего: комплекс не
## сериализуется покомнатно (он выводится из сида), `RunManager.die()` сносит
## слой и обнуляет граф ДО показа экрана, а `death_count++` меняет сид — к
## моменту сводки прошедшего забега физически нет.
##
## ПОЧЕМУ АВТОЛОАД, А НЕ УЗЕЛ МИРА. Экран итогов — отдельная сцена: мир к моменту
## его показа уже выгружен. Пережить смену сцены может только автолоад.
##
## ПОЧЕМУ НЕ ВНУТРИ RunManager. Накопитель нужен и истории забегов на доске в
## хабе (v0.7.0), где никакого текущего забега нет вовсе, — а RunManager про один
## идущий забег и только про него.
##
## Наполняется СОБЫТИЯМИ, а не опросом мира: сигналами RunManager и через
## `O_RunStats` — событиями ECS (`body_snatched`, `damage_dealt`).

## Накопитель идущего забега. Он же лежит в сейве (`RS_WorldSave.run_stats`) —
## ОДИН И ТОТ ЖЕ объект, поэтому любая контрольная точка сохраняет статистику
## заодно, и «выход в меню» посреди забега её не теряет. null — забег не идёт.
var current: RS_RunStats

## Снимок последнего ЗАВЕРШЁННОГО забега. Живёт отдельной ссылкой, потому что
## сразу после снимка сейв свою обнуляет (`WorldSave.record_death`).
var last: RS_RunStats


func _ready() -> void:
	RunManager.complex_entered.connect(_on_complex_entered)
	RunManager.room_changed.connect(_on_room_changed)


## Время забега идёт РЕАЛЬНОЕ, но без пауз: узел оставлен pausable (в отличие от
## UIManager), поэтому на паузе `_process` не зовётся вовсе. Тикаем, только пока
## забег загружен, — состояние графа тут авторитетнее любого флага, который
## пришлось бы держать в двух местах.
func _process(delta: float) -> void:
	if current == null or RunManager.current_graph == null:
		return
	current.add(RS_RunStats.TIME, delta)


## Вход в комплекс. Продолжение начатого забега (загрузка сейва, возврат из
## меню) обязано ПОДХВАТИТЬ накопленное, а не начать с нуля: `run_in_progress` в
## этот момент ещё описывает состояние ДО входа, по нему и различаем.
func _on_complex_entered(_graph: RS_LevelGraph) -> void:
	var saved := WorldSave.save
	if saved.run_in_progress and saved.run_stats != null:
		current = saved.run_stats
		return
	current = RS_RunStats.new()
	saved.run_stats = current


## Комнаты не считаем сами: их уже считает сейв (`visited_node_ids`, только
## уникальные). Свой счётчик по этому сигналу разъехался бы с ним при первом же
## возврате в пройденную комнату — дверь проходима в обе стороны.
func _on_room_changed(_node_id: StringName) -> void:
	if current == null:
		return
	current.put(RS_RunStats.ROOMS, float(WorldSave.save.visited_node_ids.size()))


## Захват тела. Имя берётся из СЦЕНЫ тела ключом перевода (см.
## `E_Body.name_key_of_scene`): к этому моменту самой сущности уже нет — захват
## её поглотил.
func record_body(scene_path: String) -> void:
	if current == null or scene_path.is_empty():
		return
	current.note_body(scene_path, E_Body.name_key_of_scene(scene_path))


## Одно нанесение урона — из единственной воронки (`S_Health.deal_damage`).
## Своим/чужим урон делает наличие C_BodySnatch: этот компонент уникален для
## души игрока (см. S_EnemyAI о том, почему не C_PlayerInput).
##
## Атрибуция («чем нанесён») в счётчики пока не идёт: способностей, которыми
## наносят урон, ещё нет. Но она уже доезжает сюда целиком, и когда появятся —
## раскладывать будет откуда.
func record_damage(damage: S_Health.Damage) -> void:
	if current == null or damage == null or damage.amount <= 0.0:
		return
	if damage.target != null and damage.target.has_component(C_BodySnatch):
		current.add(RS_RunStats.DAMAGE_TAKEN, damage.amount)
	elif damage.source != null and damage.source.has_component(C_BodySnatch):
		current.add(RS_RunStats.DAMAGE_DEALT, damage.amount)


## Забег окончен: замораживаем накопитель и откладываем его для экрана итогов.
## Зовётся ДО `WorldSave.record_death()` и `RunManager._end_run()` — после них
## ни графа, ни посещённых комнат уже нет.
## [param skill_points] награда за забег: её начисляет RunManager, и знать о ней
## накопитель может только с его слов.
func finish(outcome: StringName, skill_points: int) -> void:
	if current == null:
		return
	current.outcome = outcome
	current.add(RS_RunStats.SKILL_POINTS, float(skill_points))
	last = current
	current = null
