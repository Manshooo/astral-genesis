# res://src/autoloads/run_stats.gd
extends Node
## Накопитель статистики забега: собирает ПО ХОДУ (в конце собирать не из чего) событиями
## RunManager и O_RunStats, держит снимок последнего забега для экрана итогов.
## Автолоад — чтобы пережить смену сцены. Вики: [[Цикл забега]] (Сводка забега).

## Накопитель идущего забега — тот же объект, что в сейве (`RS_WorldSave.run_stats`): любая
## контрольная точка сохраняет и статистику. null — забег не идёт.
var current: RS_RunStats

## Снимок последнего ЗАВЕРШЁННОГО забега: сейв свою ссылку после снимка обнуляет (`record_death`).
var last: RS_RunStats


func _ready() -> void:
	# Итоги прошлого забега с диска: игру могли закрыть на экране итогов.
	last = WorldSave.save.last_run
	RunManager.complex_entered.connect(_on_complex_entered)
	RunManager.room_changed.connect(_on_room_changed)


## Время идёт реальное, но без пауз: узел pausable, на паузе `_process` не зовётся.
func _process(delta: float) -> void:
	if current == null or RunManager.current_graph == null:
		return
	current.add(RS_RunStats.TIME, delta)


## Вход в комплекс: продолжение начатого забега подхватывает накопленное. `run_in_progress`
## здесь ещё описывает состояние ДО входа — по нему и различаем.
func _on_complex_entered(_graph: RS_LevelGraph) -> void:
	var saved := WorldSave.save
	if saved.run_in_progress and saved.run_stats != null:
		current = saved.run_stats
		return
	current = RS_RunStats.new()
	saved.run_stats = current


## Комнаты считает сейв (`visited_node_ids`), своего счётчика нет — разъехался бы при возврате
## в пройденную. Коридоры тоже узлы графа, поэтому берём только комнаты (неизвестный узел — комната).
func _on_room_changed(_node_id: StringName) -> void:
	if current == null:
		return
	var graph := RunManager.current_graph
	var rooms := 0
	for id in WorldSave.save.visited_node_ids:
		var node := graph.get_node_data(id) if graph else null
		if node == null or node.role == RS_LevelNode.Role.ROOM:
			rooms += 1
	current.put(RS_RunStats.ROOMS, float(rooms))


## Захват тела. Имя — ключом перевода из СЦЕНЫ тела: самой сущности уже нет. Очки души и
## прогресс условий навыков начисляются только здесь (единственный путь — O_RunStats), иначе дважды.
func record_body(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	var body_class := E_Body.class_of_scene(scene_path)
	# Условия навыков копятся между забегами.
	SkillManager.note_capture(scene_path, body_class)
	if current == null:
		return
	# Повторы считаем ДО записи этого захвата.
	var prior := current.captures_of_kind(scene_path)
	current.note_body(scene_path, E_Body.name_key_of_scene(scene_path))
	award_soul_points(
		RS_RunStats.POINTS_ABSORB, RS_SoulPointsTable.current().points_for(body_class, prior)
	)


## Выдать очки души и записать источник. Сразу в кошелёк: смерть после захвата их не отнимает.
func award_soul_points(source: StringName, amount: int) -> void:
	if amount <= 0:
		return
	SkillManager.add_skill_points(amount)
	credit(source, amount)


## Выдать эссенцию Архитектору и записать источник (находки, тайники).
func award_essence(source: StringName, amount: int) -> void:
	if amount <= 0:
		return
	ArchitectManager.add_skill_points(amount)
	credit(source, amount)


## Только запись в разбивку забега; вне забега писать некуда — не ошибка.
func credit(source: StringName, amount: float) -> void:
	if current != null:
		current.credit(source, amount)


## Одно нанесение урона из воронки `S_Health.deal_damage`. Свой/чужой — по C_BodySnatch
## (почему не C_PlayerInput, см. S_EnemyAI). Атрибуция «чем нанесён» пока в счётчики не идёт.
func record_damage(damage: S_Health.Damage) -> void:
	if current == null or damage == null or damage.amount <= 0.0:
		return
	if damage.target != null and damage.target.has_component(C_BodySnatch):
		current.add(RS_RunStats.DAMAGE_TAKEN, damage.amount)
	elif damage.source != null and damage.source.has_component(C_BodySnatch):
		current.add(RS_RunStats.DAMAGE_DEALT, damage.amount)


## Забег окончен: замораживает накопитель и откладывает для экрана итогов. Зовётся ДО
## `record_death()` и `RunManager._end_run()` — после них ни графа, ни посещённых комнат.
func finish(outcome: StringName) -> void:
	if current == null:
		return
	current.outcome = outcome
	last = current
	current = null
	# Прогресс условий копился кадрами и мог не дойти до диска.
	SkillManager.flush()
	# Сразу на диск: следующий шаг зовущего отпустит ссылку сейва на забег.
	WorldSave.record_run_summary(last)
