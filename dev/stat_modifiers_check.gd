extends Node
## Проверка паттерна «база + модификаторы» (C_StatModifiers / RS_StatModifier):
## свёртка, независимость от порядка, идемпотентность источника, снятие эффекта
## и то, что реальные точки чтения действительно ходят через слой.
## Запускать: godot --headless dev/stat_modifiers_check.tscn
##
## Сейв навыков НЕ трогаем: SkillManager.save подменяется в памяти, а unlock() и
## add_skill_points() — единственные, кто пишет в user://, — не зовутся вовсе.

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
	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_ApplySkillEffects.new())

	await _run(world)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


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
	# Числа те же, что раньше были захардкожены в наблюдателе: 2.0 + rank * 0.5 и
	# 60.0 + rank * 20.0. Перевод скиллов в данные баланс менять не должен.
	var stub := PlayerSkillSave.new()
	stub.ranks = {&"body_snatch": 2, &"lifespan": 1}
	SkillManager.save = stub

	var soul := _make_soul()
	world.add_entity(soul)
	SkillManager.reapply_all()

	var bs := soul.get_component(C_BodySnatch) as C_BodySnatch
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	var reach := C_StatModifiers.of(soul, C_StatModifiers.CAPTURE_RANGE, bs.capture_range)
	_check("перк дальности: 2.0 + 2 * 0.5 = 3.0", is_equal_approx(reach, 3.0), str(reach))
	_check(
		"перк запаса: 60.0 + 1 * 20.0 = 80.0",
		is_equal_approx(life.effective_max(soul), 80.0),
		str(life.effective_max(soul))
	)
	_check(
		"база в компоненте не переписана",
		is_equal_approx(bs.capture_range, 2.0) and is_equal_approx(life.max_duration, 60.0),
		"%.1f / %.1f" % [bs.capture_range, life.max_duration]
	)

	# Снять прокачку — и всё вернулось к авторским числам. Ровно то, чего не мог
	# старый наблюдатель: он затирал базу присваиванием.
	stub.ranks = {}
	SkillManager.reapply_all()
	_check(
		"обнуление рангов возвращает базу",
		is_equal_approx(C_StatModifiers.of(soul, C_StatModifiers.CAPTURE_RANGE, bs.capture_range), 2.0)
			and is_equal_approx(life.effective_max(soul), 60.0),
		str(life.effective_max(soul))
	)

	# --- 5. Реальные точки чтения -------------------------------------------
	var soul_mods := soul.get_component(C_StatModifiers) as C_StatModifiers
	# +50% к объёму кармана: карман обязан ОТКРЫТЬСЯ большим, а не быть урезанным
	# авторским числом пресета в момент надевания.
	soul_mods.set_source(&"test", {}, {C_StatModifiers.BODY_DECAY: 1.5})

	var body := BODY_SCENE.instantiate()
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	ECS.process(0.016, "physics")

	var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
	_check(
		"карман открылся по эффективному объёму: 60 * 1.5 = 90",
		decay != null and is_equal_approx(decay.remaining, 90.0),
		str(decay.remaining if decay else -1.0)
	)
	_check(
		"авторское число пресета не переписано",
		decay != null and is_equal_approx(decay.maximum, 60.0),
		str(decay.maximum if decay else -1.0)
	)

	# +10% к времени, забираемому при добровольном выходе.
	soul_mods.set_source(&"test", {}, {C_StatModifiers.LEAVE_BODY_GAIN: 1.1})
	life.current = 0.0
	O_ExpelFromBody.expel(soul, true)
	_check("добровольный выход: 90 * 1.1 = 99", is_equal_approx(life.current, 99.0), str(life.current))

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
	# База 0.1, множитель 2 — остаётся 20% от эффективного максимума души (60).
	_check(
		"гибель тела: доля остатка — стат, 60 * 0.2 = 12",
		is_equal_approx(life.current, 12.0),
		str(life.current)
	)


func _make_soul() -> Entity:
	var soul := Entity.new()
	soul.name = "Soul"
	soul.component_resources = [
		C_PlayerInput.new(), C_BodySnatch.new(), C_Lifespan.new(), C_StatModifiers.new()
	]
	return soul


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
