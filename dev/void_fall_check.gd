extends Node
## Проверка дна мира (S_VoidFall): что происходит с тем, кто провалился сквозь
## щель в геометрии ниже GameConfig.void_fall_depth.
## Запускать: godot --headless dev/void_fall_check.tscn
##
## Проверять headless тут можно ВСЁ, потому что система смотрит на координату, а
## не на коллизию: ни пола, ни дырки в нём для проверки не нужно — достаточно
## поставить сущность в нужную точку. Ровно это и было доводом за координату
## против death box'а (см. шапку S_VoidFall), и проверка живёт с того же довода.
##
## Берём НАСТОЯЩИЕ сцены игрока и врага: разница исходов («игроку — конец
## забега, врагу — снос из мира») выражена НАЛИЧИЕМ C_Lifespan, и на
## заглушках-Entity это проверялось бы мимо реальных наборов компонентов.

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const ENEMY_SCENE := "res://src/entities/enemy/e_enemy.tscn"
## Тело в комнате — StaticBody3D без C_Velocity. Падать не умеет вовсе, и в
## выборку дна попадать не должно.
const BODY_SCENE := "res://src/entities/body/e_body_walker.tscn"

var _ok := 0
var _fail := 0


## Соглядатай за концом забега. Настоящий O_RunEnded звать нельзя: он ведёт в
## RunManager.die(), а тот меняет сцену — headless-прогон оборвался бы на
## середине. Запрос повторяет боевой дословно, чтобы проверялось в том числе
## «событие долетает до наблюдателя ИМЕННО С ТАКИМ фильтром».
class _RunEndedSpy:
	extends Observer

	var count := 0
	var last: Entity = null

	func query() -> QueryBuilder:
		return q.with_all([C_Lifespan]).on_event(&"run_ended")

	func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
		count += 1
		last = entity


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	var void_fall := S_VoidFall.new()
	void_fall.group = "gameplay"
	world.add_system(void_fall)

	var spy := _RunEndedSpy.new()
	world.add_observer(spy)

	await _run(world, spy)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World, spy: _RunEndedSpy) -> void:
	var depth: float = GameConfig.config.void_fall_depth
	_check(
		"порог лежит ниже любого пола, а не рядом с ним",
		depth <= -50.0,
		"%.1f — на такой глубине можно оказаться и штатно" % depth
	)

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame

	# --- 1. Над порогом ничего не происходит --------------------------------
	# Проверка не формальная: система смотрит на ОДНО число, и знак сравнения в
	# ней — единственное, что отделяет «дно мира» от «мгновенной смерти на
	# старте забега».
	(player as Node as Node3D).global_position = Vector3(0.0, depth + 1.0, 0.0)
	await _tick()
	_check("над порогом душа жива", not player.has_component(C_Dead), "")
	_check("над порогом забег не кончался", spy.count == 0, str(spy.count))

	# --- 2. Провалился игрок — это СМЕРТЬ, а не развоплощение ---------------
	(player as Node as Node3D).global_position = Vector3(0.0, depth - 10.0, 0.0)
	await _tick()

	_check("провалившаяся душа помечена мёртвой", player.has_component(C_Dead), "")
	_check("забег объявлен законченным", spy.count == 1, str(spy.count))
	_check("объявлен именно про игрока", spy.last == player, str(spy.last))
	var life := player.get_component(C_Lifespan) as C_Lifespan
	_check(
		"остаток распада обнулён, как и у догоревшей души",
		is_zero_approx(life.current),
		str(life.current)
	)

	# --- 3. Объявляется ОДИН раз -------------------------------------------
	# Между падением и экраном смерти проходит несколько кадров (RunManager.die
	# зовётся отложенно и меняет сцену), и всё это время тело остаётся ниже
	# порога. Без C_Dead в выборке "run_ended" улетало бы каждый кадр — а на нём
	# висит запись смерти в сейв (death_count++ меняет будущую генерацию).
	await _tick()
	await _tick()
	_check("конец забега объявлен ровно один раз", spy.count == 1, str(spy.count))

	# --- 4. Провалился враг — просто убрать из мира -------------------------
	# Не «убить»: смерть через C_Health объявила бы entity_died со всеми
	# наблюдателями (лут, реакции), хотя врага никто не убивал — он выпал из
	# мира. Поэтому и проверяем именно исчезновение сущности.
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Entity
	world.add_entity(enemy)
	await get_tree().process_frame
	(enemy as Node as Node3D).global_position = Vector3(0.0, depth - 10.0, 0.0)
	await _tick()
	await get_tree().process_frame  # queue_free отрабатывает к концу кадра

	_check("провалившийся враг убран из мира", not is_instance_valid(enemy), "")
	_check("смерть врага не выдана за конец забега", spy.count == 1, str(spy.count))

	# --- 5. Враг над порогом остаётся -------------------------------------
	var survivor := (load(ENEMY_SCENE) as PackedScene).instantiate() as Entity
	world.add_entity(survivor)
	await get_tree().process_frame
	(survivor as Node as Node3D).global_position = Vector3(0.0, depth + 5.0, 0.0)
	await _tick()
	await get_tree().process_frame
	_check("враг над порогом цел", is_instance_valid(survivor), "")

	# --- 6. Порог читается из конфига, а не зашит в систему ----------------
	# Число обязано жить в data/game_config.tres: миру когда-нибудь понадобится
	# другое дно, и правиться оно должно в инспекторе, а не в коде.
	var original: float = GameConfig.config.void_fall_depth
	GameConfig.config.void_fall_depth = original + 20.0  # порог поднялся ВЫШЕ выжившего
	await _tick()
	await get_tree().process_frame
	_check(
		"подняли порог в конфиге — тот же враг провалился",
		not is_instance_valid(survivor),
		"система читает своё число, а не конфиг"
	)
	GameConfig.config.void_fall_depth = original

	# --- 7. Тело в комнате падать не умеет и в выборку не входит -----------
	# E_Body — StaticBody3D без C_Velocity: генератор ставит его туда, где
	# нарисовал, и «упасть» оно не может по устройству. Выборка сужена до
	# C_Velocity намеренно, и эта проверка — про то, что сужение осознанное:
	# тело, оказавшееся под порогом (кривая комната, ошибка расстановки), сносить
	# молча нельзя — оно единственный ресурс забега.
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as Entity
	world.add_entity(body)
	await get_tree().process_frame
	(body as Node as Node3D).global_position = Vector3(0.0, depth - 10.0, 0.0)
	await _tick()
	await get_tree().process_frame
	_check("тело под порогом не снесено — падать оно всё равно не может", is_instance_valid(body), "")


## Один кадр группы "gameplay" — так же, как это делает main.gd в игре.
## Командный буфер системы применяется сразу после её process(), поэтому
## отдельного ожидания на C_Dead не нужно; кадр дерева ждём ради queue_free.
func _tick() -> void:
	ECS.process(1.0 / 60.0, "gameplay")
	await get_tree().process_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
