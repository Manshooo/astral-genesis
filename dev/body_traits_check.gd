extends Node
## ВРЕМЕННАЯ проверка модели характеристик тела (C_BodyTrait): захват переносит
## всё, что тело объявило, развоплощение снимает, карман распада живёт отдельным
## компонентом. Запускать: godot --headless dev/body_traits_check.tscn

const BODY_SCENE := preload("res://src/entities/body/e_body.tscn")

var _ok := 0
var _fail := 0


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	var snatch := S_BodySnatch.new()
	snatch.group = "physics"
	world.add_system(snatch)
	var lifespan := S_Lifespan.new()
	lifespan.group = "gameplay"
	world.add_system(lifespan)
	world.add_observer(O_ExpelFromBody.new())

	await _run(world)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World) -> void:
	# --- 0. Все сцены тел и шаблон грузятся ---------------------------------
	# Дешёвая страховка от битой ссылки на компонент: сцена с ext_resource на
	# удалённый скрипт грузится «молча-сломанной» ровно до первого запуска.
	for path in _body_scenes():
		_check("грузится %s" % path.get_file(), load(path) != null, path)
	_check(
		"грузится шаблон «Тело»", load("res://data/entity_templates/body.tres") != null, ""
	)

	# --- 0.1. Посадка рига измеряется, а не берётся нулём -------------------
	# Форму коллайдера игрока меняли (капсула → сфера), и неизмеренная форма даёт
	# ноль — надетое тело утапливается в пол на полроста. Конкретное число не
	# проверяем: его тюнят в сцене.
	var player_probe := load("res://src/entities/player/e_player.tscn").instantiate() as E_Player
	var lift := player_probe.foot_offset() if player_probe else Vector3.ZERO
	_check("foot_offset измерил коллайдер игрока", lift.y > 0.0, "%.3f" % lift.y)
	if player_probe:
		player_probe.free()

	# --- 1. Чтение характеристик из сцены -----------------------------------
	# Ожидание намеренно ЯВНОЕ, а не пересчитанное из той же сцены: считать её
	# тем же способом, что и E_Body._wearable(), значило бы сверять функцию с
	# собой. Пять надеваемых в e_body.tscn — C_Health, C_BodyDecay, C_Walk,
	# C_Jump, C_Footsteps (C_BodySnatchable надеваемой не считается).
	# Число двигать вместе со сценой: тело обзавелось характеристикой — правь
	# здесь, и это осознанный шаг, а не помеха.
	var from_scene := E_Body.traits_of_scene(BODY_SCENE.resource_path)
	_check("из сцены прочитано 5 характеристик", from_scene.size() == 5, str(from_scene.size()))

	# --- 2. Захват ----------------------------------------------------------
	var soul := _make_soul()
	world.add_entity(soul)
	var body := BODY_SCENE.instantiate()
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())

	var bs := soul.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	ECS.process(0.016, "physics")

	var walk := soul.get_component(C_Walk) as C_Walk
	var jump := soul.get_component(C_Jump) as C_Jump
	var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
	var health := soul.get_component(C_Health) as C_Health
	_check("перенесён C_Walk", walk != null and is_equal_approx(walk.speed, 4.5), str(walk))
	_check("перенесён C_Jump", jump != null and is_equal_approx(jump.velocity, 6.0), str(jump))
	_check("перенесён C_Health", health != null and is_equal_approx(health.maximum, 100.0), str(health))
	_check(
		"карман открыт полным",
		decay != null and is_equal_approx(decay.remaining, 60.0) and is_equal_approx(decay.maximum, 60.0),
		"%s" % [decay.remaining if decay else -1]
	)
	_check(
		"тело убрано из мира",
		ECS.world.query.with_all([C_BodySnatchable]).execute_one() == null,
		"осталось в мире"
	)

	# --- 3. Тик распада: платит тело, не душа --------------------------------
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	var soul_before := life.current
	ECS.process(1.0, "gameplay")
	_check("тикает карман тела", is_equal_approx(decay.remaining, 59.0), str(decay.remaining))
	_check("запас души не тронут", is_equal_approx(life.current, soul_before), str(life.current))

	# --- 4. Добровольный выход: остаток прибавляется -------------------------
	bs.leave_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame  # expel идёт через call_deferred

	_check("снят C_Walk", soul.get_component(C_Walk) == null, "")
	_check("снят C_Jump", soul.get_component(C_Jump) == null, "")
	_check("снят C_Health", soul.get_component(C_Health) == null, "")
	_check("снят карман", soul.get_component(C_BodyDecay) == null, "")
	_check("снят C_Embodied", soul.get_component(C_Embodied) == null, "")
	_check(
		"остаток тела перетёк душе (60+59=119)", is_equal_approx(life.current, 119.0), str(life.current)
	)

	# --- 5. Без тела тикает собственный запас (и излишек — быстрее) ----------
	var before := life.current
	ECS.process(0.5, "gameplay")
	var burned := before - life.current
	_check(
		"излишек утекает быстрее (×3)",
		is_equal_approx(burned, 1.5),
		"сгорело %.2f" % burned
	)

	# --- 6. Гибель тела: остаётся доля -------------------------------------
	var body2 := BODY_SCENE.instantiate()
	world.add_entity(body2)
	body2.add_component(C_SnatchTargeted.new())
	bs.capture_requested = true
	ECS.process(0.016, "physics")
	_check("повторный захват", soul.get_component(C_Embodied) != null, "")

	O_ExpelFromBody.expel(soul, false)
	_check(
		"гибель тела оставляет 10% от максимума",
		is_equal_approx(life.current, 6.0),
		str(life.current)
	)
	_check("после гибели карман снят", soul.get_component(C_BodyDecay) == null, "")


func _body_scenes() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://src/entities/body")
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			out.append("res://src/entities/body/" + file)
	return out


func _make_soul() -> Entity:
	var soul := Entity.new()
	soul.name = "Soul"
	soul.component_resources = [C_PlayerInput.new(), C_BodySnatch.new(), C_Lifespan.new()]
	return soul


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
