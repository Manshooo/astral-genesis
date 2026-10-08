extends "res://dev/check_harness.gd"
## ВРЕМЕННАЯ проверка модели характеристик тела (C_BodyTrait): захват переносит
## всё, что тело объявило, развоплощение снимает, карман распада живёт отдельным
## компонентом. Запускать: godot --headless dev/body_traits_check.tscn

const BODY_SCENE := preload("res://src/entities/body/e_body.tscn")


func _ready() -> void:
	var world := _new_world()

	_add_systems(world, "physics", [S_BodySnatch.new()])
	_add_systems(world, "gameplay", [S_Lifespan.new()])
	world.add_observer(O_ExpelFromBody.new())

	await _run(world)

	_finish()


func _run(world: World) -> void:
	# --- 0. Посадка рига измеряется, а не берётся нулём -------------------
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
	# собой. Шесть надеваемых в e_body.tscn — C_Health, C_BodyDecay, C_Walk,
	# C_Jump, C_Sprint, C_Footsteps (C_BodySnatchable надеваемой не считается).
	# Число двигать вместе со сценой: тело обзавелось характеристикой — правь
	# здесь, и это осознанный шаг, а не помеха.
	var from_scene := E_Body.traits_of_scene(BODY_SCENE.resource_path)
	_check("из сцены прочитано 6 характеристик", from_scene.size() == 6, str(from_scene.size()))

	# --- 2. Захват ----------------------------------------------------------
	var soul := _make_soul()
	world.add_entity(soul)
	var body := BODY_SCENE.instantiate()
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	# Числа — у самого тела, а не литералами: их тюнят в сцене, и проверка
	# сверяет перенос, а не баланс.
	var authored := [
		(body.get_component(C_Walk) as C_Walk).speed,
		(body.get_component(C_Jump) as C_Jump).velocity,
		(body.get_component(C_Health) as C_Health).maximum,
		(body.get_component(C_BodyDecay) as C_BodyDecay).maximum,
	]

	var bs := soul.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	ECS.process(0.016, "physics")

	var walk := soul.get_component(C_Walk) as C_Walk
	var jump := soul.get_component(C_Jump) as C_Jump
	var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
	var health := soul.get_component(C_Health) as C_Health
	var on_soul := [
		walk.speed if walk else NAN,
		jump.velocity if jump else NAN,
		health.maximum if health else NAN,
		decay.maximum if decay else NAN,
	]
	_check("ходьба, прыжок, здоровье и карман перенесены с числами тела", on_soul == authored,
		"на душе %s, у тела %s" % [on_soul, authored])
	_check(
		"карман открыт полным",
		decay != null and is_equal_approx(decay.remaining, decay.maximum),
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
	_check("тикает карман тела", is_equal_approx(decay.remaining, decay.maximum - 1.0), str(decay.remaining))
	_check("запас души не тронут", is_equal_approx(life.current, soul_before), str(life.current))

	# --- 4. Добровольный выход: остаток прибавляется -------------------------
	var leftover := decay.remaining
	bs.leave_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame  # expel идёт через call_deferred

	var still_worn: Array[String] = []
	for trait_type in [C_Walk, C_Jump, C_Health, C_BodyDecay, C_Embodied]:
		if soul.get_component(trait_type) != null:
			still_worn.append(trait_type.get_global_name())
	_check("выход снял всё, что тело надело", still_worn.is_empty(), ", ".join(still_worn))
	_check(
		"остаток тела перетёк душе", is_equal_approx(life.current, soul_before + leftover),
		"%.2f, ожидалось %.2f + %.2f" % [life.current, soul_before, leftover]
	)

	# --- 5. Без тела тикает собственный запас (и излишек — быстрее) ----------
	var before := life.current
	ECS.process(0.5, "gameplay")
	var burned := before - life.current
	var leak: float = GameConfig.config.lifespan_overflow_leak
	_check(
		"излишек утекает быстрее (×%.1f из конфига)" % leak,
		is_equal_approx(burned, 0.5 * leak),
		"сгорело %.2f" % burned
	)

	# --- 5а. Темп утечки не опускается ниже обычного -------------------------
	# Перк, загнавший множитель утечки в ноль, давал бы бессмертие (излишек не
	# убывает), в минус — растущий запас. Снизу темп держит единица: излишек
	# сгорает хотя бы как обычное время.
	soul.add_component(C_StatModifiers.new())
	(soul.get_component(C_StatModifiers) as C_StatModifiers).set_source(
		&"check", {}, {C_StatModifiers.OVERFLOW_LEAK: 0.0}
	)
	before = life.current
	ECS.process(0.5, "gameplay")
	burned = before - life.current
	_check(
		"обнулённый темп утечки не останавливает излишек",
		is_equal_approx(burned, 0.5),
		"сгорело %.2f" % burned
	)
	soul.remove_component(C_StatModifiers)

	# --- 6. Гибель тела: остаётся доля -------------------------------------
	var body2 := BODY_SCENE.instantiate()
	world.add_entity(body2)
	body2.add_component(C_SnatchTargeted.new())
	bs.capture_requested = true
	ECS.process(0.016, "physics")
	_check("повторный захват", soul.get_component(C_Embodied) != null, "")

	# --- 6а. Кадр смертельного удара -----------------------------------------
	# Удар проходит в "physics", а смерть объявит S_Health только в "gameplay".
	# В это окно захват снял бы смертельный C_Health вместе с трейтами, а выход
	# успел бы раньше выброса по смерти — оба обошли бы штраф за гибель.
	var worn := soul.get_component(C_Health) as C_Health
	worn.current = 0.0
	var body3 := BODY_SCENE.instantiate()
	world.add_entity(body3)
	body3.add_component(C_SnatchTargeted.new())
	var life_at_death := life.current
	bs.capture_requested = true
	bs.leave_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame  # дать отложенному выходу шанс сработать
	_check(
		"добитое тело не пересаживает в новое",
		soul.get_component(C_Health) == worn and body3.has_component(C_BodySnatchable),
		"C_Health подменён или тело поглощено"
	)
	_check(
		"добитое тело не отпускает добровольно",
		soul.get_component(C_Embodied) != null and is_equal_approx(life.current, life_at_death),
		"запас %.2f → %.2f" % [life_at_death, life.current]
	)
	_check(
		"оба нажатия погашены, а не отложены",
		not bs.capture_requested and not bs.leave_requested,
		"capture=%s leave=%s" % [bs.capture_requested, bs.leave_requested]
	)
	world.remove_entity(body3)
	worn.current = worn.maximum

	O_ExpelFromBody.expel(soul, false)
	var keep: float = life.effective_max(soul) * GameConfig.config.lifespan_death_fraction
	_check(
		"гибель тела оставляет долю lifespan_death_fraction от максимума",
		is_equal_approx(life.current, keep),
		"%.2f, ожидалось %.2f" % [life.current, keep]
	)
	_check("после гибели карман снят", soul.get_component(C_BodyDecay) == null, "")


func _make_soul() -> Entity:
	var soul := Entity.new()
	soul.name = "Soul"
	soul.component_resources = [C_PlayerInput.new(), C_BodySnatch.new(), C_Lifespan.new()]
	return soul
