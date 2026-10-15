extends "res://dev/check_harness.gd"
## Проверка прогрессии души (карточка «Игровой цикл — от и до» §4.1, §5, §7):
## очки за поглощение сознаний по классу тела и их множители, навык по рангам
## с бонусом за условие, копление условий между забегами, «только новые клетки»
## и разбивка очков по источникам в сводке забега.
##
## Ломается это тихо: ×2 за первый вид, который достался и второму; бонус
## условия, налипший на ранг, чьё условие не выполнено; километры, набитые
## кругами по одной клетке; прогресс, обнулившийся со смертью, — игрок видит
## только «что-то долго не открывается». Числа таблицы (RS_SoulPointsTable) и
## цен баланс пересчитает, поэтому проверка сверяет ПРАВИЛА (кратные
## множители, порядок классов, бонус только своему рангу), а не сами очки.
##
## Сейвы навыков и мира на время прогона подменяются и возвращаются на место:
## проверка пишет на диск (очки, прогресс условий, контрольные точки).
##
## Запускать: godot --headless dev/soul_progression_check.tscn

const WALKER := "res://src/entities/body/e_body_walker.tscn"
const CRAWLER := "res://src/entities/body/e_body_crawler.tscn"
const HOUND := "res://src/entities/body/e_body_hound.tscn"
const CORPSE := "res://src/entities/body/e_body.tscn"
const RUN_SEED := 424242
const TMP_STATS := "user://_soul_progression_check.tres"

var _skill_save: PlayerSkillSave
var _world_save: RS_WorldSave
var _world_backup := PackedByteArray()
var _had_world_file := false
var _original_stats: RS_RunStats


func _ready() -> void:
	_skill_save = SkillManager.save
	_world_save = WorldSave.save
	_world_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_world_file = not _world_backup.is_empty()
	_original_stats = RunStats.current

	_check_table()
	_check_capture_points()
	_check_run_save_roundtrip()
	_check_rank_fold()
	_check_condition_progress()
	_check_capture_conditions()
	_check_cell_credit()
	await _check_walk_in_world()
	_check_breakdown_rows()
	_restore()
	_finish()


# ---------------------------------------------------------------------------
# Очки за поглощение
# ---------------------------------------------------------------------------


func _check_table() -> void:
	var table := RS_SoulPointsTable.current()
	var increasing := true
	for body_class in range(1, table.class_points.size()):
		increasing = increasing and table.class_points[body_class] > table.class_points[body_class - 1]
	_check("очки растут с классом: L0 меньше всех, L5 больше всех",
		increasing and table.class_points.size() == 6, str(table.class_points))

	var base := table.class_points[2]
	_check("первый захват вида — ×2", table.points_for(2, 0) == roundi(base * 2.0), str(table.points_for(2, 0)))
	_check("первый повтор — ×0.5", table.points_for(2, 1) == roundi(base * 0.5), str(table.points_for(2, 1)))
	_check("второй повтор — ×0.25", table.points_for(2, 2) == roundi(base * 0.25), str(table.points_for(2, 2)))
	_check("дальше повторов — ноль", table.points_for(2, 3) == 0 and table.points_for(2, 9) == 0, "")
	_check("класс вне шкалы не роняет таблицу",
		table.points_for(99, 0) == table.points_for(5, 0), str(table.points_for(99, 0)))
	_check("шкала на порядке десятков-сотен, не единиц",
		table.class_points[0] >= 10 and table.class_points[5] <= 1000, str(table.class_points))

	_check("класс берётся из сцены тела",
		E_Body.class_of_scene(WALKER) == 1 and E_Body.class_of_scene(CRAWLER) == 2
		and E_Body.class_of_scene(HOUND) == 3, "%d/%d/%d" % [
			E_Body.class_of_scene(WALKER), E_Body.class_of_scene(CRAWLER), E_Body.class_of_scene(HOUND)])
	_check("у несуществующей сцены класс нулевой", E_Body.class_of_scene("res://нет.tscn") == 0, "")


func _check_capture_points() -> void:
	var save := PlayerSkillSave.new()
	SkillManager.save = save
	RunStats.current = RS_RunStats.new()
	var table := RS_SoulPointsTable.current()

	RunStats.record_body(CRAWLER)
	var first := save.skill_points
	_check("захват начисляет очки сразу, по классу и ×2", first == table.points_for(2, 0), str(first))
	RunStats.record_body(CRAWLER)
	_check("повторный захват того же вида — ×0.5",
		save.skill_points - first == table.points_for(2, 1), str(save.skill_points - first))
	var before := save.skill_points
	RunStats.record_body(CRAWLER)
	RunStats.record_body(CRAWLER)
	_check("третий и дальше — ничего",
		save.skill_points - before == table.points_for(2, 2), str(save.skill_points - before))

	before = save.skill_points
	RunStats.record_body(HOUND)
	_check("другой вид — снова ×2 и свой класс",
		save.skill_points - before == table.points_for(3, 0), str(save.skill_points - before))
	_check("сводка забега: итог равен выданному, разбивка — тому же",
		is_equal_approx(RunStats.current.value(RS_RunStats.SKILL_POINTS), float(save.skill_points))
		and is_equal_approx(RunStats.current.value(RS_RunStats.POINTS_ABSORB), float(save.skill_points)),
		"%.0f / %.0f / %d" % [RunStats.current.value(RS_RunStats.SKILL_POINTS),
			RunStats.current.value(RS_RunStats.POINTS_ABSORB), save.skill_points])

	# Чистый выход пишется своим источником, а не растворяется в общей сумме.
	RunStats.award_soul_points(RS_RunStats.POINTS_CLEAN_EXIT, 7)
	_check("чистый выход — отдельная строка разбивки",
		is_equal_approx(RunStats.current.value(RS_RunStats.POINTS_CLEAN_EXIT), 7.0)
		and is_equal_approx(RunStats.current.value(RS_RunStats.SKILL_POINTS), float(save.skill_points)), "")

	# Без забега очки за захват не начисляются: считать повторы не по чему.
	RunStats.current = null
	var frozen := save.skill_points
	RunStats.record_body(WALKER)
	_check("вне забега захват очков не даёт", save.skill_points == frozen, "")


## Повторы считаются по записям тел в сейве забега — они едут вместе с сохранением,
## поэтому загрузка продолжает счёт, а не начинает его заново.
func _check_run_save_roundtrip() -> void:
	var save := PlayerSkillSave.new()
	SkillManager.save = save
	var stats := RS_RunStats.new()
	RunStats.current = stats
	RunStats.record_body(WALKER)
	stats.cell_credit["0:1:0:1"] = 5.0
	ResourceSaver.save(stats, TMP_STATS)
	var loaded := ResourceLoader.load(TMP_STATS, "", ResourceLoader.CACHE_MODE_IGNORE) as RS_RunStats
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_STATS))
	_check("сейв забега хранит захваченные виды", loaded != null and loaded.captures_of_kind(WALKER) == 1, "")
	_check("и разбивку очков", loaded != null and loaded.value(RS_RunStats.POINTS_ABSORB) > 0.0, "")
	_check("и кредит клеток", loaded != null and is_equal_approx(float(loaded.cell_credit.get("0:1:0:1", 0.0)), 5.0), "")

	RunStats.current = loaded
	var before := save.skill_points
	RunStats.record_body(WALKER)
	_check("после загрузки повтор вида дешевеет, а не считается первым",
		save.skill_points - before == RS_SoulPointsTable.current().points_for(1, 1),
		str(save.skill_points - before))
	RunStats.current = null


# ---------------------------------------------------------------------------
# Навык: значение ранга × (1 + бонус), если выполнено условие ЭТОГО ранга
# ---------------------------------------------------------------------------


func _check_rank_fold() -> void:
	var def := SkillManager.SKILL_TREE.get_definition(&"steady_legs")
	var modifier := def.modifiers[0]
	var save := PlayerSkillSave.new()
	save.ranks = {&"steady_legs": 2}
	SkillManager.save = save

	_check("значение на каждый ранг, а не линейное",
		is_equal_approx(modifier.value_at(1), 0.10) and is_equal_approx(modifier.value_at(2), 0.12)
		and is_equal_approx(modifier.value_at(3), 0.15), str(modifier.values))
	_check("бонус навыка — доля", is_equal_approx(def.condition_bonus, 0.2), str(def.condition_bonus))

	_check("без условия — значение ранга как есть (×1.12)",
		is_equal_approx(_walk_mult(), 1.12), "%.4f" % _walk_mult())

	# Условие ДРУГОГО ранга бонуса не даёт.
	save.condition_progress[SkillManager.condition_key(&"steady_legs", 1)] = 1000.0
	_check("условие ранга 1 не усиливает ранг 2", is_equal_approx(_walk_mult(), 1.12), "%.4f" % _walk_mult())

	save.condition_progress[SkillManager.condition_key(&"steady_legs", 2)] = 2000.0
	_check("условие своего ранга: 0.12 × 1.2 = ×1.144", is_equal_approx(_walk_mult(), 1.144), "%.4f" % _walk_mult())

	# Множитель не копится: ранг 3 берёт СВОЁ значение, а не ранг 2 с бонусом.
	save.ranks = {&"steady_legs": 3}
	save.condition_progress[SkillManager.condition_key(&"steady_legs", 3)] = 3000.0
	_check("ранг 3 с условием: 0.15 × 1.2 = ×1.18, бонус не копится",
		is_equal_approx(_walk_mult(), 1.18), "%.4f" % _walk_mult())

	# Навыки старого вида (линейный per_rank, без условий) работают как прежде.
	save.ranks = {&"lifespan": 2}
	var flat := {}
	var mult := {}
	SkillManager.fold_modifiers(flat, mult)
	_check("линейный навык без значений по рангам не изменился",
		is_equal_approx(float(flat.get(C_StatModifiers.SOUL_LIFESPAN, 0.0)), 40.0), str(flat))

	var problems := SkillManager.SKILL_TREE.validate()
	_check("дерево навыков сходится после ранговых полей", problems.is_empty(), "; ".join(problems))


func _walk_mult() -> float:
	var flat := {}
	var mult := {}
	SkillManager.fold_modifiers(flat, mult)
	return float(mult.get(C_StatModifiers.WALK_SPEED, 1.0))


# ---------------------------------------------------------------------------
# Прогресс условий
# ---------------------------------------------------------------------------


func _check_condition_progress() -> void:
	var save := PlayerSkillSave.new()
	save.ranks = {&"steady_legs": 1}
	SkillManager.save = save
	var done: Array = []
	var on_done := func(id: StringName, rank: int) -> void: done.append("%s:%d" % [id, rank])
	SkillManager.condition_completed.connect(on_done)

	SkillManager.add_distance(400.0)
	SkillManager.add_distance(300.0)
	_check("дистанция копится", is_equal_approx(SkillManager.get_condition_progress(&"steady_legs", 1), 700.0),
		str(SkillManager.get_condition_progress(&"steady_legs", 1)))
	_check("условие ещё не выполнено", done.is_empty() and not SkillManager.is_condition_met(&"steady_legs", 1), "")

	SkillManager.add_distance(5000.0)
	_check("выполнение шлёт сигнал ровно один раз", done == ["steady_legs:1"], str(done))
	_check("прогресс упирается в цель", is_equal_approx(
		SkillManager.get_condition_progress(&"steady_legs", 1), 1000.0), "")
	SkillManager.add_distance(100.0)
	_check("дальше условие не копится и не шлёт повторно", done.size() == 1, str(done))
	_check("условие ранга 2, которого у игрока нет, не идёт",
		is_zero_approx(SkillManager.get_condition_progress(&"steady_legs", 2)), "")
	SkillManager.condition_completed.disconnect(on_done)

	# «Копится между забегами»: новый накопитель забега прогресс не трогает, а
	# запись на диск его возвращает.
	RunStats.current = RS_RunStats.new()
	RunStats.current = null
	var reloaded := SkillManager._load()
	_check("прогресс условий переживает новый забег и перезапуск",
		is_equal_approx(float(reloaded.condition_progress.get("steady_legs:1", 0.0)), 1000.0),
		str(reloaded.condition_progress))

	# Прогресс идёт в буфер и доходит до диска по flush(), а не на каждый кадр.
	save.ranks = {&"steady_legs": 2}
	SkillManager.add_distance(10.0)
	SkillManager.flush()
	reloaded = SkillManager._load()
	_check("flush() дописывает накопленное кадрами",
		is_equal_approx(float(reloaded.condition_progress.get("steady_legs:2", 0.0)), 10.0), "")

	# Дефолтный сейв общий на процесс: прогресс не должен в него протечь.
	SkillManager.save = SkillManager._fresh_save()
	SkillManager.save.ranks[&"steady_legs"] = 1
	SkillManager.add_distance(50.0)
	_check("прогресс не пишется в дефолтный сейв",
		SkillManager.DEFAULT_SAVE.condition_progress.is_empty(), str(SkillManager.DEFAULT_SAVE.condition_progress))
	SkillManager.reset()
	_check("«Новая игра» чистит прогресс условий",
		SkillManager.save.condition_progress.is_empty() and SkillManager.save.condition_seen.is_empty(), "")


func _check_capture_conditions() -> void:
	var save := PlayerSkillSave.new()
	save.ranks = {&"capture_precision": 1}
	SkillManager.save = save
	RunStats.current = RS_RunStats.new()
	RunStats.record_body(WALKER)
	RunStats.record_body(WALKER)
	_check("тот же вид условие не двигает дважды",
		is_equal_approx(SkillManager.get_condition_progress(&"capture_precision", 1), 1.0),
		str(SkillManager.get_condition_progress(&"capture_precision", 1)))
	RunStats.record_body(CRAWLER)
	_check("второй вид закрывает условие ранга 1", SkillManager.is_condition_met(&"capture_precision", 1), "")

	# Ранг 2 засчитывает тела не слабее L1: труп (L0) не в счёт.
	save.ranks = {&"capture_precision": 2}
	RunStats.record_body(CORPSE)
	_check("слабое тело (L0) условию с порогом L1 не засчитано",
		is_zero_approx(SkillManager.get_condition_progress(&"capture_precision", 2)), "")
	RunStats.record_body(WALKER)
	RunStats.record_body(CRAWLER)
	_check("тела не слабее порога идут в счёт",
		is_equal_approx(SkillManager.get_condition_progress(&"capture_precision", 2), 2.0),
		str(SkillManager.get_condition_progress(&"capture_precision", 2)))
	RunStats.current = null


# ---------------------------------------------------------------------------
# Дистанция только по новым клеткам
# ---------------------------------------------------------------------------


func _check_cell_credit() -> void:
	var stats := RS_RunStats.new()
	var total := 0.0
	for i in 30:
		total += stats.credit_cell_distance("0:0:0:0", 1.0, 8.0)
	_check("кругами по одной клетке больше её стороны не набрать", is_equal_approx(total, 8.0), "%.1f" % total)
	_check("новая клетка — снова засчитывается",
		is_equal_approx(stats.credit_cell_distance("0:1:0:0", 3.0, 8.0), 3.0), "")
	_check("шаг на краю бюджета засчитывается частично",
		is_equal_approx(stats.credit_cell_distance("0:1:0:0", 6.0, 8.0), 5.0), "")
	_check("та же клетка на другом слое — другая клетка",
		RS_RunStats.cell_key(1, Vector3i(0, 0, 0)) != RS_RunStats.cell_key(2, Vector3i(0, 0, 0)), "")


## Сквозной прогон: настоящий забег, игрок ходит пешком в теле с ногами, а
## S_SkillConditions кормит SkillManager.
func _check_walk_in_world() -> void:
	var save := PlayerSkillSave.new()
	save.ranks = {&"steady_legs": 1}
	SkillManager.save = save
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	var world := _new_world()
	_add_systems(world, "gameplay", [S_RoomPresence.new(), S_SkillConditions.new(), S_ScreenMessage.new()])
	RunManager.enter_complex(RUN_SEED)
	await get_tree().process_frame

	var player := ECS.world.query.with_all([C_PlayerInput]).execute_one()
	var node := player as Node as Node3D
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	# Ровно центр клетки: центр многоклеточной комнаты лежит на границе клеток, и
	# качание на метр в обе стороны считалось бы по двум клеткам сразу.
	var entry_at := plan.position_of(RunManager.current_graph.entry_node_id)
	var center := plan.embedding.cell_origin(plan.embedding.cell_at(entry_at)) + Vector3(0.0, 1.0, 0.0)
	node.global_position = center
	ECS.process(0.016, "gameplay")
	var ghost_before := SkillManager.get_condition_progress(&"steady_legs", 1)

	# Призрак условия ходьбы не двигает.
	for i in 6:
		node.global_position = center + Vector3(1.0 if i % 2 == 0 else -1.0, 0.0, 0.0)
		ECS.process(0.016, "gameplay")
	_check("призрак условие ходьбы не двигает",
		is_equal_approx(SkillManager.get_condition_progress(&"steady_legs", 1), ghost_before), "")

	player.add_component(C_Embodied.new())
	player.add_component(C_Walk.new())
	node.global_position = center
	ECS.process(0.016, "gameplay")
	for i in 40:
		node.global_position = center + Vector3(1.0 if i % 2 == 0 else -1.0, 0.0, 0.0)
		ECS.process(0.016, "gameplay")
	var cell_size := (plan.embedding as SquareGridEmbedding).cell_size
	var walked := SkillManager.get_condition_progress(&"steady_legs", 1)
	_check("пешком по одной клетке засчитывается ровно её сторона",
		is_equal_approx(walked, cell_size), "%.2f при клетке %.1f" % [walked, cell_size])

	for i in 40:
		node.global_position = center + Vector3(1.0 if i % 2 == 0 else -1.0, 0.0, 0.0)
		ECS.process(0.016, "gameplay")
	_check("по уже пройденной клетке дистанция не растёт",
		is_equal_approx(SkillManager.get_condition_progress(&"steady_legs", 1), walked), "")

	# Загрузка забега: кредит клеток едет в сейве, и посещённая не отдаётся заново.
	RunStats.current.cell_credit = RunStats.current.cell_credit.duplicate(true)
	node.global_position = center
	ECS.process(0.016, "gameplay")
	for i in 20:
		node.global_position = center + Vector3(1.0 if i % 2 == 0 else -1.0, 0.0, 0.0)
		ECS.process(0.016, "gameplay")
	_check("после «загрузки» посещённые клетки не даются заново",
		is_equal_approx(SkillManager.get_condition_progress(&"steady_legs", 1), walked), "")

	# Перенос (портал, посадка в тело) шагом не считается.
	var before_jump := SkillManager.get_condition_progress(&"steady_legs", 1)
	node.global_position = center + Vector3(40.0, 0.0, 0.0)
	ECS.process(0.016, "gameplay")
	_check("скачок позиции — не ходьба",
		is_equal_approx(SkillManager.get_condition_progress(&"steady_legs", 1), before_jump), "")

	# Выполнение условия — мысль в HUD и бонус в свёртке.
	SkillManager.add_distance(5000.0)
	await get_tree().process_frame
	var message := player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check("выполненное условие говорит об этом мыслью в HUD",
		message != null and message.text.contains(tr("SKILL_STEADY_LEGS_NAME")),
		message.text if message else "сообщения нет")
	_check("и усиливает значение ранга", is_equal_approx(_walk_mult(), 1.0 + 0.10 * 1.2), "%.4f" % _walk_mult())

	RunManager._end_run()


# ---------------------------------------------------------------------------
# Разбивка по источникам в сводке
# ---------------------------------------------------------------------------


func _check_breakdown_rows() -> void:
	var catalog := load("res://data/run_stat_catalog.tres") as RS_RunStatCatalog
	var stats := RS_RunStats.new()
	var labels: Array[StringName] = []
	for row in catalog.visible_rows(stats):
		labels.append(row.label_key)
	_check("в пустой сводке источников нет",
		not labels.has(&"RUN_STAT_POINTS_ABSORB") and not labels.has(&"RUN_STAT_ESSENCE_ARCHITECT"), str(labels))

	stats.credit(RS_RunStats.POINTS_ABSORB, 100.0)
	stats.credit(RS_RunStats.POINTS_CLEAN_EXIT, 15.0)
	stats.credit(RS_RunStats.ESSENCE_ARCHITECT, 1.0)
	stats.credit(RS_RunStats.ESSENCE_PICKUP, 250.0)
	stats.credit(&"нет_такого_источника", 5.0)
	labels.clear()
	for row in catalog.visible_rows(stats):
		labels.append(row.label_key)
	_check("источники очков и эссенции видны в сводке",
		labels.has(&"RUN_STAT_POINTS_ABSORB") and labels.has(&"RUN_STAT_POINTS_CLEAN_EXIT")
		and labels.has(&"RUN_STAT_ESSENCE_ARCHITECT") and labels.has(&"RUN_STAT_ESSENCE_PICKUP"), str(labels))
	_check("итоги валют — сумма источников",
		is_equal_approx(stats.value(RS_RunStats.SKILL_POINTS), 115.0)
		and is_equal_approx(stats.value(RS_RunStats.ESSENCE), 251.0),
		"%.0f / %.0f" % [stats.value(RS_RunStats.SKILL_POINTS), stats.value(RS_RunStats.ESSENCE)])
	_check("неизвестный источник в итоги не попадает", is_zero_approx(stats.value(&"нет_такого_источника")), "")

	# API находок следующей волны: выдача и запись одним вызовом.
	var arch := PlayerSkillSave.new()
	var original_arch := ArchitectManager.save
	ArchitectManager.save = arch
	RunStats.current = RS_RunStats.new()
	RunStats.award_essence(RS_RunStats.ESSENCE_PICKUP, 120)
	_check("награда эссенцией за находку: в кошелёк Архитектора и в разбивку",
		arch.skill_points == 120 and is_equal_approx(RunStats.current.value(RS_RunStats.ESSENCE_PICKUP), 120.0),
		"%d" % arch.skill_points)
	RunStats.current = null
	ArchitectManager.save = original_arch


func _restore() -> void:
	RunStats.current = _original_stats
	SkillManager.save = _skill_save
	SkillManager._save()
	WorldSave.save = _world_save
	if _had_world_file:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_world_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	_check("сейв мира возвращён на место", FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _world_backup, "")
