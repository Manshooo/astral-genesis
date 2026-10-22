# res://src/autoloads/world_save.gd
extends Node
## Персистентное состояние прохождения (world_seed, death_count, прогресс забега). Сам комплекс не
## сериализуется — выводится из save.run_seed(). Вики: [[Цикл забега]] §5.

## Прогресс забега ушёл на диск — HUD показывает «Сохранено». Сигнал у сейва: точку ставят из нескольких мест.
signal progress_saved

const SAVE_PATH := "user://world_save.tres"

var save: RS_WorldSave
## Лежит ли на диске валидный сейв; пока false, «Загрузить» неактивна.
var has_save_file: bool = false


func _ready() -> void:
	save = _load()


## Новая игра: новый мир, счётчик смертей обнулён, прогресс прошлого забега снят.
func new_game() -> void:
	save = RS_WorldSave.new()
	save.world_seed = randi()
	save.death_count = 0
	_save()


## Смерть: death_count входит в сид, незавершённый забег больше не продолжить.
func record_death() -> void:
	save.death_count += 1
	save.clear_run()
	_save()


## Контрольная точка забега (гранула сохранения — смена комнаты). Компонентов не принимает —
## разбирает RunManager._checkpoint. [param lifespan_left] < 0 = нет C_Lifespan; пустой
## [param body_scene_path] = душа развоплощена; [param persist] false — только память: на входе
## в забег писать нечего, но узел обязан попасть в visited_node_ids.
func record_progress(
	node_id: StringName,
	lifespan_left: float = -1.0,
	body_scene_path: String = "",
	body_health: float = 0.0,
	body_health_max: float = 0.0,
	body_lifespan_left: float = 0.0,
	body_lifespan_max: float = 0.0,
	persist: bool = true,
) -> void:
	save.run_in_progress = true
	save.current_node_id = node_id
	if not save.visited_node_ids.has(node_id):
		save.visited_node_ids.append(node_id)
	save.lifespan_remaining = lifespan_left
	save.body_scene_path = body_scene_path
	save.body_health = body_health
	save.body_health_max = body_health_max
	save.body_lifespan_remaining = body_lifespan_left
	save.body_lifespan_max = body_lifespan_max
	if not persist:
		return
	_save()
	progress_saved.emit()


## Поглощённые способности к следующей контрольной точке: на диск их пишет record_progress. Копии — сейв не делит объекты с живой душой.
func record_abilities(slots: Array, bank: Array) -> void:
	var saved_slots: Array[C_Ability] = []
	for ability in slots:
		saved_slots.append(_saved_copy(ability))
	var saved_bank: Array[C_Ability] = []
	for ability in bank:
		saved_bank.append(_saved_copy(ability))
	save.ability_slots = saved_slots
	save.ability_bank = saved_bank


static func _saved_copy(ability: C_Ability) -> C_Ability:
	return ability.absorbed_copy() if ability else null


## Итоги ЗАВЕРШЁННОГО забега: переживают clear_run() и пишутся на диск сразу (закрытая на экране итогов игра).
func record_run_summary(stats: RS_RunStats) -> void:
	save.last_run = stats
	_save()


## Тело поглощено — в этом забеге не появится. На диск сразу: выход в меню воскресил бы дубликат.
func mark_body_consumed(body_id: StringName) -> void:
	if body_id == &"" or save.consumed_body_ids.has(body_id):
		return
	save.consumed_body_ids.append(body_id)
	_save()


## Забрать разовую награду узла; false — уже забрали. На диск до самой награды: иначе выход в меню дал бы вторую.
func claim_node_reward(node_id: StringName) -> bool:
	if node_id == &"" or save.rewarded_node_ids.has(node_id):
		return false
	save.rewarded_node_ids.append(node_id)
	_save()
	return true


## Взята ли награда node_id — чтобы находка не появлялась при повторном спавне слоя.
func is_node_reward_claimed(node_id: StringName) -> bool:
	return save.rewarded_node_ids.has(node_id)


## Штатный конец забега (побег): прохождение остаётся, продолжать нечего. Для смерти — record_death.
func clear_run() -> void:
	save.clear_run()
	_save()


## Побег — финал игры: прохождение помечается пройденным, сейв остаётся ради концовки в главном меню.
func mark_game_completed() -> void:
	save.game_completed = true
	_save()


func _save() -> void:
	if UserResourceFile.write(save, SAVE_PATH, "WorldSave"):
		has_save_file = true


func _load() -> RS_WorldSave:
	var loaded := UserResourceFile.read(SAVE_PATH, RS_WorldSave, "WorldSave") as RS_WorldSave
	if loaded:
		has_save_file = true
		return loaded
	var fresh := RS_WorldSave.new()
	fresh.world_seed = randi()
	return fresh
