# res://src/autoloads/run_manager.gd
extends Node
## Автомат забега: граф уровня + загруженный слой, контрольные точки, вход, смерть и побег.
## Спавн и снос слоя — LayerStreamer, постановка игрока — PlayerPlacement.
## Вики: [[Цикл забега]].

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)
## Загружен новый слой (все его комнаты уже в дереве). depth == -1 — слой снят.
signal layer_changed(depth: int)
## Игрок сбежал на поверхность — забег (и пока вся игра) окончен победой.
signal run_finished
## Душа потеряла стабильность: запас иссяк, пока она была развоплощена (проигрыш).
signal died

## Главное меню — куда ведёт кнопка «В меню» на экране концовки.
const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"
## Экран концовки после побега; заглушка на месте синематика.
const ENDING_SCENE := "res://src/ui/ending/ending_screen.tscn"
## Секунд затемнения между дверью наружу и концовкой.
const ENDING_FADE_DURATION := 1.4
## Экран итогов забега после потери стабильности души (имя осталось от экрана смерти).
const DEATH_SCENE := "res://src/ui/death_screen/death_screen.tscn"
## Сцена души-БФЖ: спавнится скриптом при входе в забег, а не лежит в world.tscn.
const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"

## "Слой не загружен" — см. LayerStreamer.NO_DEPTH.
const NO_DEPTH := LayerStreamer.NO_DEPTH

## Что сейчас в дереве: слой, его комнаты и тайлы, планы слоёв.
var layer := LayerStreamer.new()

## Граф забега. Сеттер отдаёт его стримеру — планы слоёв граф несёт в себе.
var current_graph: RS_LevelGraph:
	set(value):
		current_graph = value
		layer.set_graph(value)
var current_node_id: StringName = &""
## Глубина загруженного слоя (NO_DEPTH — ничего не загружено).
var current_depth: int:
	get:
		return layer.depth
## Наибольшая глубина за этот забег; справочное поле.
var _max_depth_reached: int = 0
## Идёт ли завершение забега (die/finish_run): экран гаснет по живому миру, и всё, что игрок
## успеет в это окно, обязано упереться сюда — входы извне проверяют его через _in_run().
var _ending: bool = false
## Снимок ручек, по которым построен current_graph (см. _run_gen_config).
var _gen_config: RS_WorldGenConfig
## Номер входа: пока асинхронный вход ждёт генерацию, мог начаться новый — граф старого уже чужой.
var _entry_serial: int = 0
## Идёт переход порталом: слой собирается порциями, второй портал или точка сохранения застали бы полслоя.
var _traveling: bool = false


## Точка входа в забег: генерирует комплекс и ставит игрока в стартовый узел. Синхронно —
## для проверок dev/; игровая сцена входит через enter_complex_async.
func enter_complex(run_seed: int = -1) -> void:
	run_seed = _begin_entry(run_seed)
	# Душа спавнится до графа; на место её ставит PlayerPlacement.in_room из _enter_node.
	_spawn_player()
	_gen_config = _run_gen_config()
	current_graph = RS_LevelGraph.new().generate_run(
		run_seed, GameConfig.config.room_preset_library, _gen_config
	)
	_finish_entry(_start_node_id())


## Тот же вход, но граф строится в фоне под загрузочным экраном (main.gd), слой — порциями.
## layer_changed летит раньше complex_entered; душа спавнится после слоя (без пола упала бы).
## false — вход отменён (сцену сменили или начат новый); недособранный слой снесёт _begin_entry.
func enter_complex_async(run_seed: int = -1) -> bool:
	run_seed = _begin_entry(run_seed)
	var entry := _entry_serial
	# Старый граф остался бы виден автосохранению и картам, пока строится новый.
	current_graph = null
	_gen_config = _run_gen_config()
	var graph := await _generate_in_background(run_seed, _gen_config)
	if not _entry_alive(entry):
		return false
	current_graph = graph
	var start := _start_node_id()
	var spawned := await layer.spawn_async(
		graph.get_node_data(start).depth, get_tree(), _entry_alive.bind(entry)
	)
	if not _entry_alive(entry):
		return false
	if spawned:
		_after_layer_spawned()
	_spawn_player()
	_finish_entry(start)
	return true


## Жив ли ещё вход номер [param entry]: его не перебили новым, и мир, в который
## он пишет, не ушёл вместе со сценой.
func _entry_alive(entry: int) -> bool:
	return entry == _entry_serial and is_instance_valid(ECS.world) and ECS.world.is_inside_tree()


## Начало входа в забег, общее для обоих путей; возвращает сид забега.
func _begin_entry(run_seed: int) -> int:
	_entry_serial += 1
	_traveling = false  # переход прошлого мира, перебитый входом, уже не закончится
	if run_seed == -1:
		run_seed = WorldSave.save.run_seed()  # детерминированно из (world_seed, death_count)

	# Сносим прошлую сессию ДО всего: RunManager переживает смену сцены, и в layer.rooms остаются
	# комнаты, убитые вместе со старой сценой («Trying to cast a freed object»).
	_despawn_layer()
	current_node_id = &""
	_max_depth_reached = 0  # _enter_node ниже сам поднимет её до глубины входа
	return run_seed


## Конец входа, общий для обоих путей. [param start] считается один раз — иначе предупреждение
## о пропавшем узле печаталось бы дважды.
func _finish_entry(start: StringName) -> void:
	complex_entered.emit(current_graph)
	_restore_player_progress()
	_enter_node(start)


## Граф строится в WorkerThreadPool с отдачей кадров. Кэши сцен комнат прогреваются до старта
## задачи: вне дерева узлы создаются только на главном потоке.
func _generate_in_background(run_seed: int, config: RS_WorldGenConfig) -> RS_LevelGraph:
	var library := GameConfig.config.room_preset_library
	RS_RoomLayout.warm_scene_cache(RS_LevelGraph.scene_paths(library, config))
	var job := _GenerationJob.new()
	var task := WorkerThreadPool.add_task(
		func() -> void: job.graph = RS_LevelGraph.new().generate_run(run_seed, library, config),
		false,
		"RunManager: генерация комплекса"
	)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	# Задача уже кончилась; ожидание её только снимает с учёта пула.
	WorkerThreadPool.wait_for_task_completion(task)
	return job.graph


## Объект, а не локальная переменная: лямбда захватывает локальные по значению.
class _GenerationJob:
	extends RefCounted
	var graph: RS_LevelGraph


## Ручки генерации ЭТОГО забега: продолжение — по снимку из сейва, новый — база плюс
## улучшения Архитектора ([[Цикл забега]] §5).
func _run_gen_config() -> RS_WorldGenConfig:
	var saved := WorldSave.save
	var resumed := saved.resumable_gen_config()
	if resumed != null:
		return resumed
	if saved.run_in_progress:
		# Забег начат на другом генераторе (до коридоров или иная GENERATOR_VERSION): сбрасываем на вход —
		# узлы нового графа названы так же, и старые посещённые и награды легли бы на чужие комнаты.
		# Запас и тело остаются.
		saved.current_node_id = &""
		saved.visited_node_ids.clear()
		saved.consumed_body_ids.clear()
		saved.rewarded_node_ids.clear()
	var base := GameConfig.config.world_gen
	if base == null:
		return null
	# Мелкая копия намеренно: глубокая утащила бы в сейв пресеты со сценами.
	saved.gen_config = base.duplicate() as RS_WorldGenConfig
	ArchitectManager.apply_to_gen_config(saved.gen_config)
	saved.generator_version = RS_LevelGraph.GENERATOR_VERSION
	return saved.gen_config


## Узел старта: сохранённый или входной; если узла в графе нет — молча на вход.
func _start_node_id() -> StringName:
	var saved := WorldSave.save
	if saved.run_in_progress and current_graph.get_node_data(saved.current_node_id) != null:
		return saved.current_node_id
	# Пустой узел — сброс без снимка ручек (_run_gen_config): предупреждать не о чем.
	if saved.run_in_progress and saved.current_node_id != &"":
		push_warning(
			"RunManager: сохранённый узел '%s' отсутствует в графе — старт с входного"
			% saved.current_node_id
		)
	return current_graph.entry_node_id


## Возвращает БФЖ то, что не выводится из сида: воплощение и остаток распада. Запас не
## обрезается по максимуму — после добровольного выхода из тела он законно больше.
func _restore_player_progress() -> void:
	var saved := WorldSave.save
	if not saved.run_in_progress:
		return
	var player := _get_player()
	if player == null:
		return

	_restore_embodiment(player, saved)

	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life and saved.lifespan_remaining >= 0.0:
		life.current = saved.lifespan_remaining

	# Карман тела убывает всё время; on_worn открыл его полным — правим числами из сейва.
	# Потолок из сейва, не из сцены: правка пресета не растянет начатый карман.
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	if decay:
		decay.maximum = saved.body_lifespan_max
		decay.remaining = saved.body_lifespan_remaining


## Возвращает душу в тело, в котором её сохранили. Облик и характеристики — из сцены тела
## (E_Body), из сейва только состояние и потолки; прибавки скиллов пересобирает O_ApplySkillEffects.
func _restore_embodiment(player: Entity, saved: RS_WorldSave) -> void:
	if saved.body_scene_path.is_empty():
		return  # сохранились призраком — восстанавливать нечего

	var embodied := C_Embodied.new()
	embodied.body_scene_path = saved.body_scene_path
	player.add_component(embodied)

	# Характеристики — из СЦЕНЫ общим механизмом захвата: перечисление по именам завело бы вторую копию правила.
	for worn in E_Body.traits_of_scene(saved.body_scene_path):
		if worn is C_BodyTrait:
			(worn as C_BodyTrait).on_worn(player)
		player.add_component(worn)

	# HP — чистое состояние: числами из сейва, вместе с потолком.
	var health := player.get_component(C_Health) as C_Health
	if health:
		health.maximum = saved.body_health_max
		health.current = saved.body_health

	# Габарит и уровень глаз — из сцены, не из сейва.
	var form := E_Body.form_of_scene(saved.body_scene_path)
	if form:
		player.add_component(form)

	var visual := E_Body.visual_of_scene(saved.body_scene_path)
	if visual:
		player.add_component(visual)
	else:
		# Игрок выглядит призраком — обычно сцену тела переименовали или удалили.
		push_warning(
			"RunManager: не удалось прочитать облик тела из «%s» — БФЖ во плоти, но без вида"
			% saved.body_scene_path
		)


## Инстанцирует душу-БФЖ и регистрирует в мире, если её там ещё нет. Позиционирует PlayerPlacement.in_room.
func _spawn_player() -> void:
	if _get_player() != null:
		return  # уже в мире (напр. повторный enter_complex в той же сцене)
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	ECS.world.add_entity(player)

	# Перки прокачаны между забегами, а душа новая: иначе модификаторы появились бы при следующей покупке.
	SkillManager.reapply_all()

	# Полный запас — ПОСЛЕ модификаторов: перк на длительность жизни поднимает потолок.
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life:
		life.current = life.effective_max(player)


## Как менять сцену на конце забега (по умолчанию SceneLoader.change_to). Поле ради проверок:
## подмена показывает, КУДА повели. Сигнатура — (tree: SceneTree, path: String).
var scene_changer: Callable = SceneLoader.change_to


## Побег на поверхность = окончание игры (победа), не возврат в хаб. Зовётся A_FinishRun из комнаты-выхода.
func finish_run() -> void:
	if not _in_run():
		return  # не в забеге (или он уже кончается смертью) — выходить неоткуда

	# Награды нет: очки даёт поглощение сознаний. Снимок статистики — ДО clear_run(), его читает экран концовки.
	RunStats.finish(RS_RunStats.OUTCOME_ESCAPE)

	WorldSave.clear_run()  # забег завершён: «Загрузить» начнёт этот мир заново

	# Помечаем пройденным сразу, до затемнения: закрытая в эти секунды игра иначе потеряла бы концовку.
	WorldSave.mark_game_completed()

	# Порядок как у die(): гаснет живой мир, потом сносится. На время затемнения забег кончается
	# (_ending): второй выход и смерть упрутся в него.
	_ending = true
	await UIManager.fade_to_black(ENDING_FADE_DURATION)

	_end_run()
	run_finished.emit()

	_ending = false
	# Экран уже чёрный: концовка грузится в фоне под ним, а проявляет её сама.
	await scene_changer.call(get_tree(), ENDING_SCENE)


## Секунд с последней контрольной точки — счётчик автосохранения.
var _since_autosave: float = 0.0


## Автосохранение по времени: внутри комнаты утекает распад и копится статистика.
## Узел pausable — на паузе счётчик стоит.
func _process(delta: float) -> void:
	if current_graph == null:
		return
	_since_autosave += delta
	if _since_autosave < GameConfig.config.autosave_interval:
		return
	save_progress()


## Ручное сохранение и общая точка входа автосохранений (смена комнаты, время, смена воплощения).
## false — сохранять нечего. Пока идёт смерть (_ending) точка не ставится: запись воскресила бы законченный забег.
func save_progress() -> bool:
	if not _in_run() or _traveling or current_node_id == &"":
		return false
	_checkpoint(current_node_id)
	return true


## Выход в меню из паузы: забег не кончается, ставим контрольную точку и отпускаем мир
## (ссылок на комнаты не держать, см. _begin_entry).
func leave_to_menu() -> void:
	if current_graph == null:
		return
	save_progress()
	_end_run()


## Настоящая смерть БФЖ (событие run_ended от S_Lifespan): фиксируется в сейве, ведёт на экран итогов.
## Зовётся отложенно из O_RunEnded — нельзя сносить забег посреди прохода ECS. Порядок шагов не произволен.
func die() -> void:
	if not _in_run():
		return  # не в забеге — умирать некому; уже умираем — второй раз не нужно

	# Флаг до затемнения: за почти секунду живого мира второй распад прошёл бы проверку на граф.
	_ending = true

	# Снимок ДО record_death() и _end_run(): они сносят то, из чего строится сводка.
	RunStats.finish(RS_RunStats.OUTCOME_DEATH)

	# Затемнение по живому миру, и лишь потом снос.
	await UIManager.fade_to_black(GameConfig.config.death_fade_duration)

	WorldSave.record_death()  # death_count++ → следующий run_seed() иной
	_end_run()
	died.emit()

	_ending = false
	# Экран уже чёрный: итоги грузятся в фоне под ним.
	await SceneLoader.change_to(get_tree(), DEATH_SCENE)


## Общий снос забега для finish_run/die. Игрока и системы не трогаем — уходят со сценой.
func _end_run() -> void:
	_despawn_layer()
	current_graph = null
	current_node_id = &""


## Забег идёт и не кончается прямо сейчас (см. _ending).
func _in_run() -> bool:
	return current_graph != null and not _ending


## Переход порталом на другой слой под затемнением, пока слой собирается порциями. Пока слоя нет,
## C_Velocity снимается — иначе душа падала бы; портал и автосохранение молчат (_traveling), смерть обрывает сборку.
func travel_through_portal(node_id: StringName) -> void:
	if not _in_run() or _traveling:
		return
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null or node_data.depth == current_depth:
		travel_to(node_id)
		return
	_traveling = true
	var entry := _entry_serial
	var alive := func() -> bool: return _entry_alive(entry) and not _ending
	var came_from := current_node_id
	var player := _get_player()
	if player:
		player.remove_component(C_Velocity)

	var config := GameConfig.config
	var curtain: UI_LoadingScreen = null
	if config.portal_transition == RS_GameConfig.PortalTransition.CURTAIN:
		curtain = UI_LoadingScreen.create()
		get_tree().current_scene.add_child(curtain)
	else:
		await UIManager.fade_to_black(config.portal_fade_duration)

	if alive.call():
		_despawn_layer()
		if await layer.spawn_async(node_data.depth, get_tree(), alive):
			_after_layer_spawned()
	_traveling = false
	if not alive.call():
		return  # смерть или смена сцены — мир уже не наш
	if is_instance_valid(player):
		player.add_component(C_Velocity.new())
	_enter_node(node_id, came_from)
	if curtain:
		await curtain.dismiss()
	else:
		await UIManager.fade_from_black(config.portal_fade_duration)


## Мгновенный переход в узел за один кадр: перенос внутри слоя, отладочный телепорт, проверки.
## Внутри слоя портал только переставляет игрока, текущим узел станет по присутствию (note_presence).
## Смена глубины целиком здесь: слой сносится и спавнится.
func travel_to(node_id: StringName) -> void:
	if not _in_run():
		return
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null:
		push_warning("RunManager: некорректный переход в '%s'" % node_id)
		return
	if node_data.depth != current_depth:
		_enter_node(node_id, current_node_id)
		return
	var room := layer.room(node_id)
	if room == null:
		push_error("RunManager: комната узла '%s' не заспавнилась" % node_id)
		return
	# Текущим комнату сделает присутствие позже, а показать надо сейчас.
	layer.reveal_around(node_id)
	var player := _player_node()
	if player:
		PlayerPlacement.in_room(player, room, current_node_id)


## Игрок воспользовался дверью (A_TravelThroughDoor). Дверь в коридор не переносит, а открывается
## (S_DoorMotion.open); исключение — RS_LevelNode.door_teleports (хаб): игрока переставляют перед дверью.
func use_door(door: Entity, target: StringName) -> void:
	if not _in_run():
		return
	var target_data := current_graph.get_node_data(target)
	var in_place := (
		target_data != null
		and target_data.role == RS_LevelNode.Role.CORRIDOR
		and target_data.depth == current_depth
	)
	if not in_place:
		travel_through_portal(target)
		return
	var room := layer.room_of_door(door)
	var room_data := current_graph.get_node_data(room.node_id) if room else null
	if room_data != null and room_data.door_teleports:
		var player := _player_node()
		if player:
			PlayerPlacement.in_front_of(player, door, room, plan_for_depth(current_depth))
		return
	S_DoorMotion.open(door)


## Игрок стоит в точке: если это клетка другого узла загруженного слоя, он становится текущим.
## Зовётся каждый кадр (S_RoomPresence). Точка вне раскладки узел не меняет.
func note_presence(world_position: Vector3) -> void:
	if not _in_run() or current_depth == NO_DEPTH:
		return
	var node_id := plan_for_depth(current_depth).node_at(world_position)
	if node_id == &"" or node_id == current_node_id or not layer.is_spawned(node_id):
		return
	current_node_id = node_id
	layer.reveal_around(node_id)
	_sync_entry_seal()
	_checkpoint(node_id)
	room_changed.emit(node_id)


## Делает node_id текущим: догружает слой при смене глубины и переставляет игрока.
## [param came_from] — откуда пришли (ставим к двери обратно); пусто = первый вход.
func _enter_node(node_id: StringName, came_from: StringName = &"") -> void:
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null:
		push_error("RunManager: нет данных узла '%s'" % node_id)
		return

	# Слой уже в дереве — комната-цель стоит на месте, грузить нечего.
	if node_data.depth != current_depth:
		_despawn_layer()
		_spawn_layer(node_data.depth)

	var room := layer.room(node_id)
	if room == null and not layer.corridor_tiles.has(node_id):
		push_error("RunManager: узел '%s' не заспавнился" % node_id)
		return

	current_node_id = node_id
	layer.reveal_around(node_id)
	_sync_entry_seal()
	# Смена комнаты — гранула сохранения. ВХОД в забег (came_from пуст) точкой не считается: на диске
	# уже это состояние; память обновляется всё равно (visited_node_ids).
	_checkpoint(node_id, came_from != &"")
	room_changed.emit(node_id)
	var player := _player_node()
	if player == null:
		return
	if room:
		PlayerPlacement.in_room(player, room, came_from)
	else:
		PlayerPlacement.in_corridor(player, layer.corridor_tiles.get(node_id, []))


## Хаб закрыт для всех, кроме того, кто в нём стоит (иначе — бесконечная жизнь у инкубатора).
## Выводится из текущего узла, не флагом.
func _sync_entry_seal() -> void:
	var hub := layer.room(current_graph.entry_node_id) if current_graph else null
	if hub == null:
		return
	var sealed := current_node_id != current_graph.entry_node_id
	for door in hub.doors:
		var portal := door.get_component(C_DoorPortal) as C_DoorPortal
		if portal == null or portal.target_node_id == &"":
			continue
		portal.locked_by = C_DoorPortal.ENTRY_SEAL if sealed else &""
		if sealed:
			S_DoorMotion.close(door)


## Загружает слой: спавн — у стримера, максимум глубины и сигнал — здесь.
func _spawn_layer(depth: int) -> void:
	if layer.spawn(depth):
		_after_layer_spawned()


## Состояние забега после того, как слой встал целиком, — на оба пути спавна.
func _after_layer_spawned() -> void:
	_max_depth_reached = maxi(_max_depth_reached, layer.depth)
	layer_changed.emit(layer.depth)


## Снимает загруженный слой; сигнал — только если было что снимать.
func _despawn_layer() -> void:
	if layer.despawn():
		layer_changed.emit(NO_DEPTH)


## План слоя; доступен и для незагруженных — на этом держится карта комплекса.
func plan_for_depth(depth: int) -> RS_LayerPlan:
	return layer.plan_for_depth(depth)


func _get_player() -> E_Player:
	return E_Player.find() as E_Player


## Игрок как Node3D — через Node: прямой каст Entity→Node3D анализатор не пропускает.
func _player_node() -> Node3D:
	return E_Player.find() as Node as Node3D


## Контрольная точка: снимает с БФЖ всё, что не выводится из сида. Разбор компонентов здесь,
## а не в WorldSave: тот про ECS не знает. [param persist] false — только память.
func _checkpoint(node_id: StringName, persist: bool = true) -> void:
	# Счётчик автосохранения обнуляет любая точка.
	_since_autosave = 0.0

	var lifespan_left := -1.0
	var body_scene_path := ""
	var body_health := 0.0
	var body_health_max := 0.0
	var body_lifespan_left := 0.0
	var body_lifespan_max := 0.0

	var player := _get_player()
	if player:
		var life := player.get_component(C_Lifespan) as C_Lifespan
		if life:
			lifespan_left = life.current
		# Карман тела есть только во плоти — вместе с самим телом.
		var decay := player.get_component(C_BodyDecay) as C_BodyDecay
		if decay:
			body_lifespan_left = decay.remaining
			body_lifespan_max = decay.maximum
		var embodied := player.get_component(C_Embodied) as C_Embodied
		if embodied:
			body_scene_path = embodied.body_scene_path
		# C_Health есть только во плоти: развоплощённая душа живёт по C_Lifespan.
		var health := player.get_component(C_Health) as C_Health
		if health:
			body_health = health.current
			body_health_max = health.maximum

	WorldSave.record_progress(
		node_id,
		lifespan_left,
		body_scene_path,
		body_health,
		body_health_max,
		body_lifespan_left,
		body_lifespan_max,
		persist
	)
