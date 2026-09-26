# res://src/autoloads/run_manager.gd
extends Node
## Управляет одним "забегом": граф уровня + загруженный СЛОЙ.
##
## Гранула стриминга — СЛОЙ (все узлы одной depth разом в дереве сцены: комнаты
## и тайлы веток коридора), а не отдельная комната. Внутри этажа игрок ходит
## ногами — комнаты подвешены к веткам коридора (RS_LayerPlan); между этажами слоя
## переставляет портал; переход на другую глубину = деспавн всего слоя и спавн
## нового.
##
## Текущий узел внутри слоя меняется не дверью, а присутствием: в чьей клетке
## плана стоит игрок, тот узел и текущий (note_presence, S_RoomPresence).
##
## Двери и переходы: у дверей комнаты компонент C_DoorSlot; при спавне каждая
## дверь получает C_DoorPortal на ветку, которую план поставил на её сторону, а
## порталы — вертикальные рёбра узла. Дверь в коридор открывается на месте
## (use_door).
##
## Прогресс забега: смена узла — контрольная точка (WorldSave.record_progress),
## вход в забег стартует с сохранённого узла, если забег не завершён.
##
## Здесь — автомат забега и его контрольные точки. Что лежит в дереве (спавн и
## снос слоя, планы, раздача рёбер дверям) — LayerStreamer, куда поставить
## игрока — PlayerPlacement: раньше всё это жило в этом файле, тысячей строк, и
## спавн комнаты ходил в те же поля, что и запись сейва.

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)
## Загружен новый слой (все его комнаты уже в дереве). depth == -1 — слой снят.
signal layer_changed(depth: int)
## Игрок сбежал на поверхность — забег (и пока вся игра) окончен победой.
signal run_finished
## БФЖ распался: запас жизни иссяк, пока душа была развоплощена (проигрыш).
signal died

## Заглушка «игра окончена»: экрана концовки пока нет — уходим в меню, как и
## «выход в меню» из паузы.
const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"
## Экран ИТОГОВ ЗАБЕГА: показывается после распада БФЖ (см. die). Имя константы
## и путь сцены остались от экрана смерти, которым он был раньше.
const DEATH_SCENE := "res://src/ui/death_screen/death_screen.tscn"
## Сцена души-БФЖ. Спавним её скриптом при входе в забег, а не кладём в world.tscn:
## игрок должен появляться в уже сгенерированном мире, у входного узла графа.
const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"

## "Слой не загружен" — см. LayerStreamer.NO_DEPTH.
const NO_DEPTH := LayerStreamer.NO_DEPTH

## Что сейчас в дереве: слой, его комнаты и тайлы, планы слоёв.
var layer := LayerStreamer.new()

## Граф забега. Сеттер отдаёт его стримеру вместе с ручками — планы прошлого графа
## к новому не относятся и сбрасываются там же.
var current_graph: RS_LevelGraph:
	set(value):
		current_graph = value
		layer.set_graph(value, _gen_config)
var current_node_id: StringName = &""
## Глубина загруженного слоя (NO_DEPTH — ничего не загружено).
var current_depth: int:
	get:
		return layer.depth
## Наибольшая глубина, достигнутая ЗА ЭТОТ забег — награда очков навыка при
## finish_run/die считается от неё, а не от layer_changed: тот шлётся и при
## возврате на уже пройденный слой (портал проходим в обе стороны), и дробить
## награду по нему значило бы фармить очки шатанием туда-обратно.
var _max_depth_reached: int = 0
## Идёт ли уже завершение забега по смерти. См. die(): экран гаснет почти
## секунду по ЖИВОМУ миру — ни паузы, ни блокировки ввода, — и всё, что игрок
## успеет в это окно, обязано упереться в этот флаг. Иначе второй распад сменил бы
## сцену дважды, портал пересобрал бы слой и записал на диск ещё живой забег, а
## дверь выхода засчитала бы побег поверх смерти — с двойной наградой. Все входы
## извне (переход, дверь, побег, точки сохранения) проверяют его через _in_run().
var _ending: bool = false
## Снимок ручек, по которым построен current_graph (см. _run_gen_config). Нужен
## и раскладке: шаг решётки комнат — тоже ручка, и план обязан строиться по тем
## же числам, что и граф.
var _gen_config: RS_WorldGenConfig


## Точка входа в забег: генерирует комплекс и ставит игрока в стартовый узел.
## Комплекс НЕ читается из сейва покомнатно — он выводится из сида, а сейв даёт
## только точку, где игрок остановился (см. _start_node_id).
func enter_complex(run_seed: int = -1) -> void:
	if run_seed == -1:
		run_seed = WorldSave.save.run_seed()  # детерминированно из (world_seed, death_count)

	# Сносим состояние прошлой сессии ДО всего остального. RunManager — autoload и
	# переживает смену сцены, а «Выход в меню» из паузы забег не заканчивает: в
	# layer.rooms остаются комнаты, УЖЕ УБИТЫЕ вместе со старой сценой мира, и
	# current_depth от них же. Если сохранённый узел оказывался той же глубины,
	# _enter_node считал слой уже загруженным и лез в мёртвую комнату —
	# «Trying to cast a freed object» при загрузке сейва.
	_despawn_layer()
	current_node_id = &""
	_max_depth_reached = 0  # _enter_node ниже сам поднимет её до глубины входа

	# Игрок появляется в уже сгенерированном мире: сперва спавним душу, затем граф,
	# затем входной слой — _enter_node → PlayerPlacement.in_room поставит её на место.
	_spawn_player()
	_gen_config = _run_gen_config()
	current_graph = RS_LevelGraph.new().generate_run(
		run_seed, GameConfig.config.room_preset_library, _gen_config
	)
	complex_entered.emit(current_graph)
	_restore_player_progress()
	_enter_node(_start_node_id())


## Ручки генерации ЭТОГО забега. Начатый забег продолжается по снимку из сейва,
## новый снимает текущий конфиг и кладёт снимок в сейв — на диск он уйдёт с
## первой же контрольной точкой, вместе с run_in_progress, так что забег без
## единой точки на диске и снимка не оставит, и начнётся заново по свежим ручкам.
##
## Сюда же лягут улучшения Архитектора: снимок — это база ПЛЮС его модификаторы
## на момент старта, а не голый data/world_gen_config.tres.
func _run_gen_config() -> RS_WorldGenConfig:
	var saved := WorldSave.save
	if saved.run_in_progress and saved.gen_config != null:
		return saved.gen_config
	if saved.run_in_progress:
		# Забег начат до коридоров: снимка у него нет, а комплекс, по которому он
		# шёл, больше не строится. Решено сбрасывать его на вход (22.09): узлы
		# нового графа названы так же (L3_F0_room_0…), и старые посещённые и
		# съеденные тела молча легли бы на чужие комнаты. Запас и тело остаются —
		# их восстановит _restore_player_progress.
		saved.current_node_id = &""
		saved.visited_node_ids.clear()
		saved.consumed_body_ids.clear()
	var base := GameConfig.config.world_gen
	if base == null:
		return null
	# Мелкая копия намеренно: записи уникальных комнат — данные, их не правят,
	# а глубокая копия утащила бы в сейв ещё и пресеты со сценами.
	saved.gen_config = base.duplicate() as RS_WorldGenConfig
	return saved.gen_config


## Узел, с которого начинается сессия: сохранённый (продолжение забега) или
## входной. Сейв мог быть сделан на другом сиде/версии графа — если узла в графе
## нет, молча откатываемся на вход, а не роняем забег.
func _start_node_id() -> StringName:
	var saved := WorldSave.save
	if saved.run_in_progress and current_graph.get_node_data(saved.current_node_id) != null:
		return saved.current_node_id
	# Пустой узел — не рассинхрон, а сброс забега без снимка ручек (см.
	# _run_gen_config): предупреждать не о чем.
	if saved.run_in_progress and saved.current_node_id != &"":
		push_warning(
			"RunManager: сохранённый узел '%s' отсутствует в графе — старт с входного"
			% saved.current_node_id
		)
	return current_graph.entry_node_id


## Возвращает БФЖ то, что не выводится из сида: воплощение и остаток распада.
## Иначе загрузка работала бы как бесплатное восстановление (свежая E_Player
## несёт полный C_Lifespan) и как принудительное развоплощение.
##
## Запас распада НЕ обрезается по максимуму: с моделью «распад как ресурс» он
## законно бывает больше — излишек, вынесенный из тела при добровольном выходе,
## и утекает он быстрее обычного (S_Lifespan). Обрезка здесь молча съедала бы
## именно то, что игрок заработал, выйдя из тела вовремя.
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

	# Карман тела — тоже состояние: он убывает всё время, пока игрок в теле.
	# Компонент к этому моменту уже надет (_restore_embodiment), on_worn открыл
	# его ПОЛНЫМ — числами из сейва поправляем на то, что было на самом деле.
	# Потолок пишем из сейва, а не берём из сцены, чтобы правка пресета между
	# сессиями не растянула молча уже начатый карман.
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	if decay:
		decay.maximum = saved.body_lifespan_max
		decay.remaining = saved.body_lifespan_remaining


## Возвращает душу в тело, в котором её сохранили. Свежая E_Player всегда
## призрак: её идентичность — только C_BodySnatch + C_Lifespan
## (define_components), а C_Embodied/C_Health/C_BodyVisual навешивает захват.
##
## Облик и характеристики читаются из сцены тела, а не из сейва: и меш, и числа
## пресета — часть сцены, писать их в .tres значило бы завести второй источник
## правды (см. E_Body.visual_of / traits_of_scene). Из сейва берётся только
## состояние: сколько HP и сколько запаса осталось — вместе с их потолками,
## чтобы правка пресета между сессиями не поехала по уже начатому телу.
## Прибавки скиллов в сейв не идут вовсе: они пересобираются из SkillManager
## (O_ApplySkillEffects) и лежат слоем поверх этих чисел.
func _restore_embodiment(player: Entity, saved: RS_WorldSave) -> void:
	if saved.body_scene_path.is_empty():
		return  # сохранились призраком — восстанавливать нечего

	var embodied := C_Embodied.new()
	embodied.body_scene_path = saved.body_scene_path
	player.add_component(embodied)

	# Характеристики надетого тела — из СЦЕНЫ, тем же общим механизмом, что и при
	# захвате: перечислять их здесь по именам значило бы завести вторую копию
	# правила переноса, которая молча отстанет от первой при добавлении стата.
	for worn in E_Body.traits_of_scene(saved.body_scene_path):
		if worn is C_BodyTrait:
			(worn as C_BodyTrait).on_worn(player)
		player.add_component(worn)

	# HP, наоборот, чистое состояние — числами из сейва поверх свежего компонента
	# (вместе с потолком: см. выше про правку пресета между сессиями).
	var health := player.get_component(C_Health) as C_Health
	if health:
		health.maximum = saved.body_health_max
		health.current = saved.body_health

	# Габарит и уровень глаз — тоже из сцены, а не из сейва: это часть модели, и
	# писать их в .tres значило бы завести второй источник правды, ровно как с
	# обликом.
	var form := E_Body.form_of_scene(saved.body_scene_path)
	if form:
		player.add_component(form)

	var visual := E_Body.visual_of_scene(saved.body_scene_path)
	if visual:
		player.add_component(visual)
	else:
		# Тело восстановлено по механике, но выглядит игрок призраком. Молчать
		# нельзя: обычно это значит, что сцену тела переименовали или удалили.
		push_warning(
			"RunManager: не удалось прочитать облик тела из «%s» — БФЖ во плоти, но без вида"
			% saved.body_scene_path
		)


## Инстанцирует душу-БФЖ и регистрирует её в мире, если её там ещё нет.
## Позиционирование — на совести PlayerPlacement.in_room (при входе в первый узел).
##
## Учёт WorldSave/новой игры: сид забега уже выведен в enter_complex из
## (world_seed, death_count); свежая E_Player несёт полный запас жизни — её
## идентичность (C_BodySnatch, C_Lifespan) навешивает define_components(), а не
## сцена, так что каждый новый забег стартует с непочатым C_Lifespan.
func _spawn_player() -> void:
	if _get_player() != null:
		return  # уже в мире (напр. повторный enter_complex в той же сцене)
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	ECS.world.add_entity(player)

	# Дерево перков прокачано между забегами, а душа только что создана: без
	# этого вызова модификаторы появились бы лишь в момент следующей покупки
	# навыка, и новый забег стартовал бы без всей прокачки.
	SkillManager.reapply_all()

	# Полный запас считаем ПОСЛЕ модификаторов: перк на длительность жизни
	# поднимает потолок, и стартовать с авторских 60 при потолке 100 значило бы
	# выдать прокачку, которой не видно. Сохранённый забег это число перезапишет
	# своим (_restore_player_progress).
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life:
		life.current = life.effective_max(player)


## Побег на поверхность = ОКОНЧАНИЕ ИГРЫ (победа). Это НЕ возврат в хаб — тот
## происходит только при смерти (пока не реализовано, нужен death_count/состояния).
## Зовётся A_FinishRun из комнаты-выхода (тег level_exit).
func finish_run() -> void:
	if not _in_run():
		return  # не в забеге (или он уже кончается смертью) — выходить неоткуда

	# Награда за побег больше, чем за гибель на той же глубине (die() ниже) —
	# правильная концовка забега обязана быть выгоднее, тем же принципом, что и
	# доля запаса, которую даёт добровольный выход из тела против его гибели.
	var reward := _max_depth_reached + 1
	# Снимок статистики — ДО clear_run(): тот сносит прогресс забега вместе с
	# посещёнными комнатами. Своего экрана у победы пока нет (уходим в меню, как
	# было), но снимок ей понадобится тем же, каким пользуется смерть, — и
	# копиться он обязан уже сейчас, иначе первый же победный забег окажется
	# незаписанным.
	RunStats.finish(RS_RunStats.OUTCOME_ESCAPE, reward)

	WorldSave.clear_run()  # забег завершён: «Загрузить» начнёт этот мир заново
	SkillManager.add_skill_points(reward)
	_end_run()
	run_finished.emit()

	# TODO: экран концовки/победы. Пока — в меню, как «выход в меню» из паузы.
	get_tree().change_scene_to_file(MENU_SCENE)


## Сколько прошло с последней контрольной точки — счётчик автосохранения (см.
## _process).
var _since_autosave: float = 0.0


## Автосохранение по ВРЕМЕНИ. Смена комнаты — не единственное, что стоит
## сохранять: внутри одной комнаты утекает распад, копится урон и статистика, и
## вылет откатывал бы игрока к состоянию на момент входа в неё.
##
## Узел оставлен pausable (в отличие от UIManager), поэтому на паузе счётчик
## стоит — там всё равно ничего не меняется, а кнопка «Сохранить» рядом.
func _process(delta: float) -> void:
	if current_graph == null:
		return
	_since_autosave += delta
	if _since_autosave < GameConfig.config.autosave_interval:
		return
	save_progress()


## Ручное сохранение (кнопка «Сохранить» в паузе) и общая точка входа для всех
## автосохранений. Контрольные точки ставятся на смене комнаты, по времени
## (_process) и при смене воплощения — распад тикает НЕПРЕРЫВНО, и без этого в
## сейве остаётся запас на момент входа в комнату, а не на сейчас.
## false — сохранять нечего (не в забеге).
##
## Пока идёт смерть (_ending) точку не ставим ниоткуда: die() уже снял снимок
## статистики и вот-вот снесёт забег, а запись воскресила бы в сейве только что
## законченный забег. Окно это не теоретическое — экран гаснет почти секунду по
## живому миру, и за это время успевает случиться и удар, и развоплощение.
func save_progress() -> bool:
	if not _in_run() or current_node_id == &"":
		return false
	_checkpoint(current_node_id)
	return true


## Выход в меню из паузы. Забег НЕ заканчивается: в сейве остаётся
## run_in_progress, «Загрузить» вернёт игрока сюда же. Здесь только фиксируем
## контрольную точку на текущий момент и отпускаем мир — сцена всё равно уходит,
## а держать ссылки на её комнаты нельзя (см. про мёртвые комнаты в enter_complex).
func leave_to_menu() -> void:
	if current_graph == null:
		return
	save_progress()
	_end_run()


## Настоящая смерть БФЖ: запас распада иссяк, пока душа была РАЗВОПЛОЩЕНА
## (событие "run_ended" от S_Lifespan). В отличие от finish_run (побег = победа),
## смерть фиксируется в сейве — death_count++ меняет будущую генерацию — и уводит
## на экран итогов забега. Зовётся отложенно из O_RunEnded (нельзя сносить забег
## в середине прохода ECS по сущностям).
##
## Порядок шагов внутри не произволен, см. комментарии по месту: снимок
## статистики → затемнение по живому миру → фиксация смерти и снос забега.
func die() -> void:
	if not _in_run():
		return  # не в забеге — умирать некому; уже умираем — второй раз не нужно

	# Гасим экран ДО сноса забега, поэтому между началом смерти и сменой сцены
	# проходит почти секунда живого мира — а в нём есть кому ударить ещё раз.
	# Без этого флага второй распад успел бы пройти сквозь проверку на граф
	# (он обнуляется уже после ожидания) и сменить сцену дважды.
	_ending = true

	var reward := _max_depth_reached  # см. finish_run — без бонуса за побег
	# Снимок ДО всего остального: record_death() ниже сносит прогресс забега
	# вместе с посещёнными комнатами, а _end_run() — граф и комнаты. После них
	# сводке забега неоткуда взяться.
	RunStats.finish(RS_RunStats.OUTCOME_DEATH, reward)

	# Затемнение по ЖИВОМУ миру: сначала гаснет то, в чём игрок только что был, и
	# лишь потом мир сносится. Гасить уже после _end_run() значило бы затемнять
	# пустоту, а обрыв остался бы таким же резким, каким был со смены сцены в лоб.
	await UIManager.fade_to_black(GameConfig.config.death_fade_duration)

	WorldSave.record_death()  # death_count++ → следующий run_seed() иной
	SkillManager.add_skill_points(reward)
	_end_run()
	died.emit()

	_ending = false
	get_tree().change_scene_to_file(DEATH_SCENE)


## Общий снос забега для finish_run/die: убрать загруженный слой и обнулить граф.
## Игрока и системы не трогаем — они уходят вместе со сценой мира при смене сцены.
func _end_run() -> void:
	_despawn_layer()
	current_graph = null
	current_node_id = &""


## Забег идёт и не кончается прямо сейчас — единое условие для всего, что
## приходит извне (см. _ending).
func _in_run() -> bool:
	return current_graph != null and not _ending


## Переход в другой узел графа по порталу (через use_door) и для отладочного
## телепорта по слоям.
##
## Внутри слоя — это портал между этажами: он только ПЕРЕСТАВЛЯЕТ игрока к порталу
## обратно, а текущим узлом комната станет по факту присутствия (note_presence),
## как и после прохода по коридору. Дверь в коридор сюда не доходит вовсе — её
## открывает use_door.
##
## Смена глубины — по-прежнему целиком здесь: слой надо снести и заспавнить, и
## игрока некуда поставить, пока новой комнаты нет в дереве.
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
	var player := _player_node()
	if player:
		PlayerPlacement.in_room(player, room, current_node_id)


## Игрок воспользовался дверью (A_TravelThroughDoor) — она ведёт в [param target].
##
## В коридорной раскладке дверь в коридор своего этажа никуда не переносит: она
## ОТКРЫВАЕТСЯ, и дальше игрок идёт ногами, а текущий узел сменит присутствие.
## Исключение — комната без проёма за дверью (RS_LevelNode.door_teleports, хаб до
## переделки арта): открывать там нечего, и игрока переставляют на тайл перед
## дверью. Порталы идут через travel_to.
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
		travel_to(target)
		return
	var room := layer.room_of_door(door)
	var room_data := current_graph.get_node_data(room.node_id) if room else null
	if room_data != null and room_data.door_teleports:
		var player := _player_node()
		if player:
			PlayerPlacement.in_front_of(player, door, room, plan_for_depth(current_depth))
		return
	_open_door(door)


## Открывает дверь: полотно поднимает S_DoorOpen, а интеракция гаснет — открытую
## дверь больше незачем подсвечивать, и подсказка в проходе мешала бы. Зовётся из
## действия двери, то есть уже вне прохода ECS (interact() идёт через
## call_deferred), поэтому компонент добавляется напрямую.
func _open_door(door: Entity) -> void:
	if door.has_component(C_DoorOpen):
		return
	door.add_component(C_DoorOpen.new())
	var inter := door.get_component(C_Interactable) as C_Interactable
	if inter:
		inter.enabled = false


## Игрок стоит в точке [param world_position] — если это клетка другого узла
## загруженного слоя, он и становится текущим. Зовётся каждый кадр
## (S_RoomPresence), поэтому пустые случаи отсекаются первыми.
##
## Точка вне раскладки (пустота, провал под мир) узел не меняет: «нигде» —
## не узел, и контрольная точка в нём вернула бы игрока в никуда. Во время
## смерти точки не ставятся вовсе — см. save_progress про _ending.
func note_presence(world_position: Vector3) -> void:
	if not _in_run() or current_depth == NO_DEPTH:
		return
	var node_id := plan_for_depth(current_depth).node_at(world_position)
	if node_id == &"" or node_id == current_node_id or not layer.is_spawned(node_id):
		return
	current_node_id = node_id
	_checkpoint(node_id)
	room_changed.emit(node_id)


## Делает [param node_id] текущим узлом: догружает его слой, если игрок сменил
## глубину, и переставляет игрока в нужную комнату.
## [param came_from] узел, из которого пришли — чтобы поставить игрока к двери,
## ведущей обратно, а не в общий SpawnPoint. Пусто = первый вход в забег.
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
	# Смена комнаты — гранула сохранения забега: дальше игрок продолжит отсюда.
	#
	# А вот ВХОД в забег (came_from пуст: старт, загрузка, возрождение) точкой не
	# считается: сохранять там нечего, на диске уже лежит ровно это состояние, —
	# и лишняя запись сразу после загрузки только мигала бы игроку «Сохранено» на
	# ровном месте. Состояние в памяти при этом обновляется всё равно: комната,
	# в которой игрок стоит, обязана попасть в visited_node_ids (см. persist).
	_checkpoint(node_id, came_from != &"")
	room_changed.emit(node_id)
	var player := _player_node()
	if player == null:
		return
	if room:
		PlayerPlacement.in_room(player, room, came_from)
	else:
		PlayerPlacement.in_corridor(player, layer.corridor_tiles.get(node_id, []))


## Загружает слой [param depth]: спавн — у стримера, а максимум глубины и сигнал
## слоя — здесь, это состояние забега.
func _spawn_layer(depth: int) -> void:
	if not layer.spawn(depth):
		return
	_max_depth_reached = maxi(_max_depth_reached, depth)
	layer_changed.emit(depth)


## Снимает загруженный слой; сигнал — только если было что снимать.
func _despawn_layer() -> void:
	if layer.despawn():
		layer_changed.emit(NO_DEPTH)


## План слоя [param depth] — см. LayerStreamer.plan_for_depth. Доступен и для
## незагруженных слоёв: на этом держится карта комплекса.
func plan_for_depth(depth: int) -> RS_LayerPlan:
	return layer.plan_for_depth(depth)


func _get_player() -> E_Player:
	return E_Player.find() as E_Player


## Игрок как узел сцены — для PlayerPlacement. Через Node: Entity наследует Node,
## и прямой каст Entity→Node3D анализатор GDScript не пропускает.
func _player_node() -> Node3D:
	return E_Player.find() as Node as Node3D


## Контрольная точка: снимает с БФЖ всё, что не выводится из сида, и отдаёт
## сейву числами. Разбор компонентов живёт здесь, а не в WorldSave: автолоад
## сохранения про ECS ничего не знает и знать не должен.
## [param persist] false — только обновить состояние в памяти (см.
## WorldSave.record_progress и вход в забег в _enter_node).
func _checkpoint(node_id: StringName, persist: bool = true) -> void:
	# Счётчик автосохранения обнуляет ЛЮБАЯ точка, а не только своя: смена
	# комнаты и кнопка в паузе пишут то же самое, и отсчитывать интервал от
	# предыдущего автосохранения значило бы писать на диск чаще без нужды. Вход
	# в забег счётчик тоже обнуляет — отсчёт до первого автосохранения идёт с
	# момента, когда игрок оказался в мире, а не с прошлой сессии.
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
