extends "res://dev/check_harness.gd"
## Проверка паттерна «база + модификаторы» (C_StatModifiers / RS_StatModifier):
## свёртка, независимость от порядка, идемпотентность источника, снятие эффекта
## и то, что реальные точки чтения действительно ходят через слой.
## Запускать: godot --headless dev/stat_modifiers_check.tscn
##
## Сейв навыков НЕ трогаем: SkillManager.save подменяется в памяти, а unlock() и
## add_skill_points() — единственные, кто пишет в user://, — не зовутся вовсе.

const BODY_SCENE := preload("res://src/entities/body/e_body.tscn")

func _ready() -> void:
	var world := _new_world()

	_add_systems(world, "physics", [S_BodySnatch.new()])
	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_ApplySkillEffects.new())

	await _run(world)

	_finish()


func _run(world: World) -> void:
	# --- 1. Свёртка ---------------------------------------------------------
	var mods := C_StatModifiers.new()
	_check("без модификаторов возвращается база", is_equal_approx(mods.value(&"x", 7.0), 7.0), "")

	mods.set_source(&"a", {&"x": 3.0}, {})
	_check("плоская прибавка", is_equal_approx(mods.value(&"x", 7.0), 10.0), str(mods.value(&"x", 7.0)))

	mods.set_source(&"b", {&"x": 1.0}, {&"x": 2.0})
	_check(
		"свёртка (7 + 3 + 1) * 2",
		is_equal_approx(mods.value(&"x", 7.0), 22.0),
		str(mods.value(&"x", 7.0))
	)

	# Порядок выдачи не должен влиять: тот же набор, поданный наоборот, — тот же
	# ответ. Это главное обещание паттерна, ради него и считаем свёрткой.
	var backwards := C_StatModifiers.new()
	backwards.set_source(&"b", {&"x": 1.0}, {&"x": 2.0})
	backwards.set_source(&"a", {&"x": 3.0}, {})
	_check(
		"порядок источников не влияет",
		is_equal_approx(backwards.value(&"x", 7.0), mods.value(&"x", 7.0)),
		str(backwards.value(&"x", 7.0))
	)

	# Повторная выдача того же источника не удваивает эффект — на этом стоит
	# пересчёт «с нуля» в O_ApplySkillEffects.
	mods.set_source(&"a", {&"x": 3.0}, {})
	_check(
		"источник идемпотентен",
		is_equal_approx(mods.value(&"x", 7.0), 22.0),
		str(mods.value(&"x", 7.0))
	)

	mods.clear_source(&"b")
	_check("источник снимается", is_equal_approx(mods.value(&"x", 7.0), 10.0), str(mods.value(&"x", 7.0)))
	mods.clear_source(&"a")
	_check("база не потеряна", is_equal_approx(mods.value(&"x", 7.0), 7.0), str(mods.value(&"x", 7.0)))

	# --- 2. Модификаторы разных душ не общие --------------------------------
	# GECS делает компонентам shallow duplicate(), а Dictionary — ссылочный тип:
	# правка на месте разошлась бы по всем копиям разом (см. C_StatModifiers._refold).
	var one := _make_soul()
	var two := _make_soul()
	world.add_entity(one)
	world.add_entity(two)
	var mods_one := one.get_component(C_StatModifiers) as C_StatModifiers
	mods_one.set_source(&"t", {C_StatModifiers.WALK_SPEED: 100.0}, {})
	_check(
		"модификаторы не протекают между душами",
		is_equal_approx(C_StatModifiers.of(two, C_StatModifiers.WALK_SPEED, 4.5), 4.5),
		str(C_StatModifiers.of(two, C_StatModifiers.WALK_SPEED, 4.5))
	)

	# --- 3. Ранг: flat и mult трактуются по-разному -------------------------
	var flat_mod := RS_StatModifier.new()
	flat_mod.stat = C_StatModifiers.WALK_SPEED
	flat_mod.op = RS_StatModifier.Op.FLAT
	flat_mod.per_rank = 0.5
	var mult_mod := RS_StatModifier.new()
	mult_mod.stat = C_StatModifiers.WALK_SPEED
	mult_mod.op = RS_StatModifier.Op.MULT
	mult_mod.per_rank = 0.1

	var flat := {}
	var mult := {}
	RS_StatModifier.fold([flat_mod, mult_mod], 3, flat, mult)
	_check("flat линеен по рангу", is_equal_approx(flat[C_StatModifiers.WALK_SPEED], 1.5), str(flat))
	_check(
		"mult — доля от ранга, 0.1 на ранге 3 даёт 1.3",
		is_equal_approx(mult[C_StatModifiers.WALK_SPEED], 1.3),
		str(mult)
	)

	# --- 4. Дерево перков доезжает до души ----------------------------------
	# Сколько даёт ранг — баланс в data/skill_tree.tres, и его тюнят; проверка
	# сверяет путь «ранг → модификатор → прочитанный стат», а не число.
	var stub := PlayerSkillSave.new()
	stub.ranks = {&"body_snatch": 2, &"lifespan": 1}
	SkillManager.save = stub

	var soul := _make_soul()
	world.add_entity(soul)
	var bs := soul.get_component(C_BodySnatch) as C_BodySnatch
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	var base_reach := bs.capture_range
	var base_max := life.max_duration
	SkillManager.reapply_all()

	var reach := C_StatModifiers.of(soul, C_StatModifiers.CAPTURE_RANGE, bs.capture_range)
	_check("ранги перка дальности увеличивают дальность захвата", reach > base_reach,
		"%.2f при базе %.2f" % [reach, base_reach])
	_check("ранг перка запаса увеличивает максимум", life.effective_max(soul) > base_max,
		"%.2f при базе %.2f" % [life.effective_max(soul), base_max])
	_check(
		"база в компоненте не переписана",
		is_equal_approx(bs.capture_range, base_reach) and is_equal_approx(life.max_duration, base_max),
		"%.1f / %.1f" % [bs.capture_range, life.max_duration]
	)

	# Снять прокачку — и всё вернулось к авторским числам. Ровно то, чего не мог
	# старый наблюдатель: он затирал базу присваиванием.
	stub.ranks = {}
	SkillManager.reapply_all()
	_check(
		"обнуление рангов возвращает базу",
		is_equal_approx(C_StatModifiers.of(soul, C_StatModifiers.CAPTURE_RANGE, bs.capture_range), base_reach)
			and is_equal_approx(life.effective_max(soul), base_max),
		str(life.effective_max(soul))
	)

	# --- 5. Реальные точки чтения -------------------------------------------
	var soul_mods := soul.get_component(C_StatModifiers) as C_StatModifiers
	# +50% к объёму кармана: карман обязан ОТКРЫТЬСЯ большим, а не быть урезанным
	# авторским числом пресета в момент надевания.
	soul_mods.set_source(&"test", {}, {C_StatModifiers.BODY_DECAY: 1.5})

	var body := BODY_SCENE.instantiate()
	world.add_entity(body)
	var pocket := (body.get_component(C_BodyDecay) as C_BodyDecay).maximum
	body.add_component(C_SnatchTargeted.new())
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	ECS.process(0.016, "physics")

	var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
	_check(
		"карман открылся по эффективному объёму: объём тела × 1.5",
		decay != null and is_equal_approx(decay.remaining, pocket * 1.5),
		"%.2f при объёме тела %.2f" % [decay.remaining if decay else -1.0, pocket]
	)
	_check(
		"авторское число пресета не переписано",
		decay != null and is_equal_approx(decay.maximum, pocket),
		str(decay.maximum if decay else -1.0)
	)

	# +10% к времени, забираемому при добровольном выходе.
	soul_mods.set_source(&"test", {}, {C_StatModifiers.LEAVE_BODY_GAIN: 1.1})
	var taken := decay.remaining
	life.current = 0.0
	O_ExpelFromBody.expel(soul, true)
	_check("добровольный выход забирает остаток × 1.1", is_equal_approx(life.current, taken * 1.1),
		"%.2f при остатке %.2f" % [life.current, taken])

	# Доля, остающаяся при гибели тела, — тоже стат.
	var body2 := BODY_SCENE.instantiate()
	world.add_entity(body2)
	body2.add_component(C_SnatchTargeted.new())
	bs.capture_requested = true
	ECS.process(0.016, "physics")
	_check("повторный захват", soul.get_component(C_Embodied) != null, "")

	soul_mods.set_source(&"test", {}, {C_StatModifiers.DEATH_KEEP: 2.0})
	life.current = 100.0
	O_ExpelFromBody.expel(soul, false)
	var keep: float = life.effective_max(soul) * GameConfig.config.lifespan_death_fraction * 2.0
	_check(
		"гибель тела: доля остатка — стат (база из конфига × 2)",
		is_equal_approx(life.current, keep),
		"%.2f, ожидалось %.2f" % [life.current, keep]
	)


func _make_soul() -> Entity:
	var soul := Entity.new()
	soul.name = "Soul"
	soul.component_resources = [
		C_PlayerInput.new(), C_BodySnatch.new(), C_Lifespan.new(), C_StatModifiers.new()
	]
	return soul
