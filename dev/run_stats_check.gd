extends Node
## Проверка сводки забега: накопитель (RS_RunStats), каталог показателей,
## воронка урона и локализация.
##
## Что здесь важно поймать, потому что руками это ловится только смертью в конце
## получасового забега: статистика собирается ПО ХОДУ (в конце собирать не из
## чего), снятый снимок переживает обнуление сейва, «выход в меню» посреди забега
## не обнуляет накопленное, а урон считается по воронке, а не по падению HP —
## иначе лечение и смена тела выглядели бы уроном.
##
## Запускать: godot --headless dev/run_stats_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const WALKER_SCENE := "res://src/entities/body/e_body_walker.tscn"
const ENEMY_SCENE := "res://src/entities/enemy/e_enemy.tscn"
const CATALOG_PATH := "res://data/run_stat_catalog.tres"

var _ok := 0
var _fail := 0
var _pending_ticks := 0

## Сколько раз сейв отчитался о записи (WorldSave.progress_saved). Поле, а не
## локальная переменная в лямбде: лямбда GDScript захватывает переменную ПО
## ЗНАЧЕНИЮ, и счётчик внутри неё увеличивал бы копию.
var _saves := 0

## Настоящий сейв разработчика на момент старта проверки. Прогон пишет на диск
## (иначе контрольную точку не проверить), и чужой забег он ронять не должен.
var _save_backup := PackedByteArray()
var _had_save := false


func _ready() -> void:
	# ДО всего остального: конец забега (RunStats.finish) пишет итоги на диск, и
	# бэкап, снятый позже, застал бы уже испорченный файл.
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()

	var world := World.new()
	add_child(world)
	ECS.world = world

	for system in [
		S_BodySnatch.new(), S_Phasing.new(), S_Gravity.new(),
		S_EnemyAI.new(), S_Walk.new(), S_Jump.new(), S_Flight.new(), S_Movement.new(),
	]:
		system.group = "physics"
		world.add_system(system)

	var health_sys := S_Health.new()
	health_sys.group = "gameplay"
	world.add_system(health_sys)

	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_BodyVisual.new())
	world.add_observer(O_BodyForm.new())
	world.add_observer(O_SoulTraits.new())
	world.add_observer(O_RunStats.new())

	_check_catalog()
	_check_localization()
	_check_accumulator()
	await _check_world(world)
	_check_run_boundaries()
	await _check_screen()
	_check_autosave()
	_restore_save()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------
# Каталог показателей
# ---------------------------------------------------------------------------


func _check_catalog() -> void:
	var catalog := load(CATALOG_PATH) as RS_RunStatCatalog
	_check("каталог показателей грузится", catalog != null, CATALOG_PATH)
	if catalog == null:
		return

	var bad := PackedStringArray()
	for row: RS_RunStatRow in catalog.rows:
		if row == null or row.label_key == &"":
			bad.append("строка без ключа перевода")
		elif row.format != RS_RunStatRow.Format.BODY_LIST and row.key == &"":
			bad.append(String(row.label_key) + ": показатель без ключа значения")
	_check("у каждой строки каталога есть ключ перевода и показатель", bad.is_empty(), ", ".join(bad))

	_check("время показывается как ММ:СС", RS_RunStatCatalog.format_time(125.4) == "2:05",
		RS_RunStatCatalog.format_time(125.4))
	_check("нулевое время не уезжает в минус", RS_RunStatCatalog.format_time(-5.0) == "0:00",
		RS_RunStatCatalog.format_time(-5.0))

	# Показатель, которого в забеге не случилось, строкой в сводке быть не должен:
	# «урона получено: 0» — это не факт о забеге, а шум.
	var fresh := RS_RunStats.new()
	var labels := _label_keys(catalog, fresh)
	_check("в пустой сводке есть время", labels.has(&"RUN_STAT_TIME"), str(labels))
	_check("в пустой сводке нет урона", not labels.has(&"RUN_STAT_DAMAGE_TAKEN"), str(labels))
	_check("в пустой сводке нет списка тел", not labels.has(&"RUN_STAT_BODY_LIST"), str(labels))

	fresh.note_body(WALKER_SCENE, &"BODY_WALKER")
	fresh.add(RS_RunStats.DAMAGE_TAKEN, 12.0)
	labels = _label_keys(catalog, fresh)
	_check("занятое тело добавляет строку со списком", labels.has(&"RUN_STAT_BODY_LIST"), str(labels))
	_check("полученный урон добавляет свою строку", labels.has(&"RUN_STAT_DAMAGE_TAKEN"), str(labels))

	var body_row := _row_by_label(catalog, &"RUN_STAT_BODY_LIST")
	_check(
		"список тел показывает ПЕРЕВЕДЁННОЕ имя, а не ключ",
		body_row != null and catalog.value_text(body_row, fresh) == tr(&"BODY_WALKER"),
		catalog.value_text(body_row, fresh) if body_row else "строки нет"
	)


# ---------------------------------------------------------------------------
# Локализация
# ---------------------------------------------------------------------------


func _check_localization() -> void:
	# Перевод, вернувший сам ключ, — это не перевод: либо .csv не подключён в
	# project.godot, либо ключа в нём нет. И то, и другое в игре выглядит как
	# «BODY_WALKER» вместо имени тела.
	for key in [&"RUN_SUMMARY_TITLE_DEATH", &"RUN_SUMMARY_REVIVE", &"RUN_STAT_TIME", &"BODY_WALKER"]:
		_check("ключ «%s» переведён" % key, tr(key) != String(key), tr(key))

	_check(
		"имя тела читается из СЦЕНЫ тела, а не из словаря в коде",
		E_Body.name_key_of_scene(WALKER_SCENE) == &"BODY_WALKER",
		String(E_Body.name_key_of_scene(WALKER_SCENE))
	)
	_check(
		"несуществующая сцена тела не роняет сводку",
		E_Body.name_key_of_scene("res://нет-такого.tscn") == &"",
		""
	)


# ---------------------------------------------------------------------------
# Накопитель
# ---------------------------------------------------------------------------


func _check_accumulator() -> void:
	var stats := RS_RunStats.new()
	_check("незнакомый показатель читается нулём", is_zero_approx(stats.value(&"чего-то-нет")), "")

	stats.add(RS_RunStats.DAMAGE_DEALT, 5.0)
	stats.add(RS_RunStats.DAMAGE_DEALT, 7.5)
	_check("накопительный показатель складывается", is_equal_approx(stats.value(RS_RunStats.DAMAGE_DEALT), 12.5),
		"%.2f" % stats.value(RS_RunStats.DAMAGE_DEALT))

	stats.put(RS_RunStats.ROOMS, 3.0)
	stats.put(RS_RunStats.ROOMS, 3.0)
	_check("известный целиком показатель перезаписывается, а не суммируется",
		is_equal_approx(stats.value(RS_RunStats.ROOMS), 3.0), "%.2f" % stats.value(RS_RunStats.ROOMS))

	stats.add(RS_RunStats.TIME, 42.0)
	var record := stats.note_body(WALKER_SCENE, &"BODY_WALKER")
	_check("захват тела считается и числом, и записью",
		is_equal_approx(stats.value(RS_RunStats.BODIES), 1.0) and stats.bodies.size() == 1, "")
	_check("запись тела помнит момент захвата", is_equal_approx(record.taken_at, 42.0), "%.2f" % record.taken_at)
	_check("текущее тело — последнее занятое", stats.current_body() == record, "")


# ---------------------------------------------------------------------------
# Мир: захват и урон доходят до накопителя событиями
# ---------------------------------------------------------------------------


func _check_world(world: World) -> void:
	RunStats.current = RS_RunStats.new()
	var stats := RunStats.current

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame

	var walker := _spawn_body(world, WALKER_SCENE, Vector3(20.0, 0.0, 20.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame

	_check("захват в мире дошёл до сводки записью", stats.bodies.size() == 1, str(stats.bodies.size()))
	_check(
		"в записи — имя того тела, которое заняли",
		not stats.bodies.is_empty() and stats.bodies[0].name_key == &"BODY_WALKER",
		String(stats.bodies[0].name_key) if not stats.bodies.is_empty() else "записи нет"
	)
	_check("тело, которого больше нет в мире, всё равно названо", is_instance_valid(walker) == false
		or not walker.is_inside_tree(), "")

	# --- Урон: чей он, решает воронка, а не падение HP ----------------------
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as E_Enemy
	world.add_entity(enemy)
	await get_tree().process_frame

	S_Health.deal_damage(player, 7.0, enemy, &"enemy_melee")
	_check("урон по игроку — «получено»", is_equal_approx(stats.value(RS_RunStats.DAMAGE_TAKEN), 7.0),
		"%.2f" % stats.value(RS_RunStats.DAMAGE_TAKEN))
	_check("урон по игроку не засчитан как нанесённый им",
		is_zero_approx(stats.value(RS_RunStats.DAMAGE_DEALT)), "")

	# Бить в ответ пока нечем и некого: у E_Enemy нет C_Health вовсе (боевой
	# системы ещё нет, см. «Система боя» в бэклоге). Проверяем оба факта разом —
	# что удар по неуязвимому не считается и не роняет игру, и что сам путь
	# «нанесено» работает, когда прочность у цели есть.
	S_Health.deal_damage(enemy, 4.0, player, &"")
	_check("удар по цели без прочности ничего не пишет и не роняет игру",
		is_zero_approx(stats.value(RS_RunStats.DAMAGE_DEALT)),
		"%.2f" % stats.value(RS_RunStats.DAMAGE_DEALT))

	var target_body := _spawn_body(world, WALKER_SCENE, Vector3(-20.0, 0.0, -20.0), false)
	await get_tree().process_frame
	S_Health.deal_damage(target_body, 4.0, player, &"")
	_check("урон игрока по цели с прочностью — «нанесено»",
		is_equal_approx(stats.value(RS_RunStats.DAMAGE_DEALT), 4.0),
		"%.2f" % stats.value(RS_RunStats.DAMAGE_DEALT))

	# Лечение и прочие правки HP мимо воронки в сводку попадать не должны —
	# ровно ради этого урон и перестал быть прямой записью в C_Health.
	var health := player.get_component(C_Health) as C_Health
	health.current -= 25.0
	_check("падение HP мимо воронки уроном не считается",
		is_equal_approx(stats.value(RS_RunStats.DAMAGE_TAKEN), 7.0),
		"%.2f" % stats.value(RS_RunStats.DAMAGE_TAKEN))


# ---------------------------------------------------------------------------
# Границы забега: снимок, обнуление сейва, продолжение начатого забега
# ---------------------------------------------------------------------------


func _check_run_boundaries() -> void:
	var saved := WorldSave.save

	# Новый забег: накопитель свежий и лежит в сейве тем же объектом — иначе
	# контрольные точки сохраняли бы пустую статистику.
	saved.run_in_progress = false
	RunManager.complex_entered.emit(null)
	var started := RunStats.current
	_check("вход в комплекс заводит накопитель", started != null, "")
	_check("накопитель лежит в сейве ТЕМ ЖЕ объектом", saved.run_stats == started, "")

	started.add(RS_RunStats.TIME, 100.0)
	started.note_body(WALKER_SCENE, &"BODY_WALKER")

	# Возврат в начатый забег («выход в меню» его не заканчивает): накопленное
	# обязано подхватиться, а не начаться заново.
	saved.run_in_progress = true
	RunManager.complex_entered.emit(null)
	_check("продолжение забега подхватывает накопленное", RunStats.current == started, "")
	_check("время забега не обнулилось", is_equal_approx(RunStats.current.value(RS_RunStats.TIME), 100.0),
		"%.2f" % RunStats.current.value(RS_RunStats.TIME))

	# Конец забега: снимок отложен, текущего накопителя больше нет.
	RunStats.finish(RS_RunStats.OUTCOME_DEATH, 3)
	_check("снимок забега отложен для экрана итогов", RunStats.last == started, "")
	_check("после конца забега копить некуда", RunStats.current == null, "")
	_check("награда за забег попала в сводку",
		is_equal_approx(RunStats.last.value(RS_RunStats.SKILL_POINTS), 3.0),
		"%.2f" % RunStats.last.value(RS_RunStats.SKILL_POINTS))
	_check("исход забега записан", RunStats.last.outcome == RS_RunStats.OUTCOME_DEATH,
		String(RunStats.last.outcome))

	# Регресс: record_death() чистит прогресс забега СРАЗУ после снимка. Если бы
	# clear_run() чистил статистику на месте, а не отвязывал ссылку, экран итогов
	# показал бы пустую сводку.
	saved.clear_run()
	_check("обнуление забега не стёрло уже снятый снимок",
		is_equal_approx(RunStats.last.value(RS_RunStats.TIME), 100.0)
		and RunStats.last.bodies.size() == 1,
		"%.2f / %d" % [RunStats.last.value(RS_RunStats.TIME), RunStats.last.bodies.size()])
	_check("сейв свою ссылку на статистику отпустил", saved.run_stats == null, "")

	# Урон после конца забега писать некуда — и это не должно ронять игру.
	RunStats.record_damage(null)
	_check("урон после конца забега не роняет накопитель", true, "")


# ---------------------------------------------------------------------------
# Экран итогов
# ---------------------------------------------------------------------------


## Headless не рисует ни пикселя, поэтому проверяем не вид, а связь: экран
## действительно собирает строки из каталога и кладёт их в тот узел, который у
## него в сцене. Разъехавшееся имя узла (%StatRows) иначе всплывает только
## смертью в живом прогоне — то есть в самом конце забега.
func _check_screen() -> void:
	var catalog := load(CATALOG_PATH) as RS_RunStatCatalog
	var stats := RS_RunStats.new()
	stats.add(RS_RunStats.TIME, 90.0)
	stats.put(RS_RunStats.ROOMS, 4.0)
	stats.note_body(WALKER_SCENE, &"BODY_WALKER")
	stats.add(RS_RunStats.DAMAGE_TAKEN, 30.0)
	RunStats.last = stats

	var screen := (load(RunManager.DEATH_SCENE) as PackedScene).instantiate()
	add_child(screen)
	await get_tree().process_frame

	var grid := screen.get_node_or_null("%StatRows") as GridContainer
	var expected := catalog.visible_rows(stats).size()
	_check("экран итогов нашёл свой контейнер строк", grid != null, "%StatRows")
	_check(
		"экран собрал ровно те строки, что выдал каталог (подпись + значение)",
		grid != null and grid.get_child_count() == expected * 2,
		"строк каталога %d, узлов в сетке %d" % [expected, grid.get_child_count() if grid else -1]
	)

	screen.queue_free()


# ---------------------------------------------------------------------------
# Автосохранение
# ---------------------------------------------------------------------------


## Контрольная точка проверяется настоящей записью на диск — иначе не проверяется
## вовсе. Сейв разработчика снят в _ready и возвращается в _restore_save.
func _check_autosave() -> void:
	WorldSave.progress_saved.connect(_count_save)

	# Итоги забега переживают обнуление прогресса: забег кончился, а его сводка —
	# уже часть прохождения. Иначе экран итогов, открытый после перезапуска,
	# оказался бы пустым.
	var summary := RS_RunStats.new()
	summary.add(RS_RunStats.TIME, 77.0)
	WorldSave.record_run_summary(summary)
	WorldSave.save.clear_run()
	_check("итоги забега не сносятся вместе с прогрессом", WorldSave.save.last_run == summary, "")

	# Дальше нужен «идущий забег»: save_progress() без графа отказывает первым же
	# условием и ничего бы не доказал.
	RunManager.current_graph = RS_LevelGraph.new()
	RunManager.current_node_id = &"проверочный_узел"
	RunManager._ending = false
	RunManager._since_autosave = 0.0

	_saves = 0
	_check("контрольная точка ставится и сообщает о себе", RunManager.save_progress() and _saves == 1,
		"записей: %d" % _saves)

	# Регресс: пока идёт смерть, точку не ставит НИКТО. die() к этому моменту уже
	# снял снимок статистики, и запись воскресила бы законченный забег в сейве.
	RunManager._ending = true
	_saves = 0
	_check("во время смерти точка не ставится", not RunManager.save_progress() and _saves == 0,
		"записей: %d" % _saves)
	RunManager._ending = false

	# Автосохранение по времени: до интервала молчит, после — пишет.
	var interval: float = GameConfig.config.autosave_interval
	RunManager._since_autosave = 0.0
	_saves = 0
	RunManager._process(interval * 0.5)
	_check("до интервала автосохранение молчит", _saves == 0, "записей: %d" % _saves)
	RunManager._process(interval * 0.6)
	_check("после интервала автосохранение пишет точку", _saves == 1, "записей: %d" % _saves)
	_check("своя точка обнуляет счётчик интервала", is_zero_approx(RunManager._since_autosave),
		"%.2f" % RunManager._since_autosave)

	WorldSave.progress_saved.disconnect(_count_save)
	RunManager.current_graph = null
	RunManager.current_node_id = &""


func _count_save() -> void:
	_saves += 1


## Возвращает сейв разработчика ровно таким, каким он был до прогона.
func _restore_save() -> void:
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------


func _label_keys(catalog: RS_RunStatCatalog, stats: RS_RunStats) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: RS_RunStatRow in catalog.visible_rows(stats):
		out.append(row.label_key)
	return out


func _row_by_label(catalog: RS_RunStatCatalog, label_key: StringName) -> RS_RunStatRow:
	for row: RS_RunStatRow in catalog.rows:
		if row != null and row.label_key == label_key:
			return row
	return null


## [param targeted] — пометить тело как цель захвата. Второе тело в мире метку
## получать НЕ должно: цель под крестиком ищется через execute_one(), и вторая
## помеченная сущность сделала бы выбор недетерминированным.
func _spawn_body(world: World, path: String, at: Vector3, targeted: bool = true) -> Entity:
	var body := (load(path) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = at
	world.add_entity(body)
	if targeted:
		body.add_component(C_SnatchTargeted.new())
	return body


func _physics_process(delta: float) -> void:
	if _pending_ticks <= 0:
		return
	_pending_ticks -= 1
	ECS.process(delta, "physics")
	ECS.process(delta, "gameplay")


func _physics(frames: int) -> void:
	_pending_ticks = frames
	while _pending_ticks > 0:
		await get_tree().physics_frame
	await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
