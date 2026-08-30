extends Node
## Проверка экономики очков навыка (карточка Задачи/Карточки/Скиллы.md):
## RunManager._max_depth_reached — монотонный трекер, «Чистый выход»
## (O_ExpelFromBody, порог 50% выжатости тела) и целостность data/skill_tree.tres
## (все 10 статов каталога заняты хотя бы одним навыком).
## Запускать: godot --headless dev/skill_economy_check.tscn
##
## RunManager.finish_run()/die() здесь НЕ зовутся: оба меняют сцену
## (get_tree().change_scene_to_file) и завершают забег по-настоящему — это
## подорвало бы headless-процесс проверки, а не проверило формулу. Вместо этого
## раздел 1 проверяет то самое состояние, которое эти методы читают
## (_max_depth_reached), а формулу («глубина + бонус за побег» против «глубина
## без бонуса») — код-ревью и живой прогон из карточки.
##
## SkillManager.save НА ВРЕМЯ проверки подменяется заглушкой (как и в
## stat_modifiers_check.gd), но, в отличие от него, здесь реально зовётся
## add_skill_points() — единственный путь начисления, и он пишет на диск. Чтобы
## не оставить в user://skills.tres проверочные числа, оригинальный save
## возвращается на место и принудительно пересохраняется в конце (_restore).

const BODY_DECAY_MAX := 60.0

var _ok := 0
var _fail := 0
var _original_skill_save: PlayerSkillSave
var _original_max_depth: int


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	_original_skill_save = SkillManager.save
	_original_max_depth = RunManager._max_depth_reached

	await _run(world)

	SkillManager.save = _original_skill_save
	SkillManager._save()
	RunManager._max_depth_reached = _original_max_depth

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World) -> void:
	# --- 1. Трекер максимальной глубины монотонен -----------------------------
	# _spawn_layer обновляет его строкой `_max_depth_reached = maxi(..., depth)`
	# на КАЖДЫЙ вход в слой, включая возврат на уже пройденный (портал проходим
	# в обе стороны). Награда за забег читает это поле один раз, в конце —
	# так что задвоения при шатании между слоями быть не может ПО ПОСТРОЕНИЮ,
	# при условии, что поле действительно монотонно. Симулируем ровно
	# последовательность обновлений, которую делает _spawn_layer, без самой
	# генерации графа и спавна комнат.
	RunManager._max_depth_reached = 0
	for depth in [0, 1, 2, 1, 2, 0]:
		RunManager._max_depth_reached = maxi(RunManager._max_depth_reached, depth)
	_check(
		"глубина: возврат на пройденные слои не опускает максимум",
		RunManager._max_depth_reached == 2,
		str(RunManager._max_depth_reached)
	)

	# --- 2. Чистый выход из тела: порог 50% выжатости -------------------------
	var stub := PlayerSkillSave.new()
	SkillManager.save = stub

	var soul := _make_soul()
	world.add_entity(soul)

	_wear_body(soul, 40.0)  # 40/60 = 33% выжато — ниже порога
	O_ExpelFromBody.expel(soul, true)
	_check(
		"чистый выход ниже 50% выжатости очка не даёт",
		stub.skill_points == 0,
		"skill_points=%d" % stub.skill_points
	)

	_wear_body(soul, 30.0)  # 30/60 = ровно 50% — порог включительно
	O_ExpelFromBody.expel(soul, true)
	_check(
		"чистый выход РОВНО на 50% выжатости даёт очко",
		stub.skill_points == 1,
		"skill_points=%d" % stub.skill_points
	)

	_wear_body(soul, 10.0)  # 10/60 = 83% выжато — заметно выше порога
	O_ExpelFromBody.expel(soul, true)
	_check(
		"чистый выход сильно выжатого тела даёт очко",
		stub.skill_points == 2,
		"skill_points=%d" % stub.skill_points
	)

	# --- 3. Гибель тела (voluntary=false) очков не даёт вообще -----------------
	_wear_body(soul, 0.0)  # тело выжато полностью — самый "щедрый" случай для порога
	O_ExpelFromBody.expel(soul, false)
	_check(
		"гибель тела очко не даёт, даже полностью выжатого",
		stub.skill_points == 2,
		"skill_points=%d" % stub.skill_points
	)

	# --- 4. Дерево навыков занимает весь каталог статов ------------------------
	var tree := SkillManager.SKILL_TREE
	for stat in C_StatModifiers.ALL:
		var covered := false
		for def in tree.skills:
			for mod in def.modifiers:
				if mod.stat == stat:
					covered = true
					break
			if covered:
				break
		_check("стат каталога занят навыком: %s" % stat, covered, "ни один навык не трогает этот стат")

	var expected_ids: Array[StringName] = [
		&"body_snatch", &"capture_precision", &"lifespan", &"decay_capacity",
		&"graceful_exit", &"overflow_control", &"last_breath",
		&"steady_legs", &"spring_step", &"resilient_flesh",
	]
	for id in expected_ids:
		_check("навык объявлен в дереве: %s" % id, tree.get_definition(id) != null, "get_definition вернул null")

	# --- 5. «Новая игра» обнуляет дерево --------------------------------------
	# Смерть метапрогресс сохраняет, новая игра — снимает. Вторая проверка здесь
	# важнее первой: Resource.duplicate() отдаёт ТОТ ЖЕ Dictionary, что лежит в
	# дефолтном ресурсе, поэтому без отдельного копирования рангов покупка
	# навыка писала бы прямо в дефолт — и «чистый лист» приезжал бы уже с
	# рангами, причём только в живой игре, где сейва на диске ещё нет.
	SkillManager.save = SkillManager._fresh_save()
	SkillManager.save.skill_points = 5
	SkillManager.unlock(&"body_snatch")
	_check(
		"новая игра: покупка навыка не пишет в дефолтный сейв",
		SkillManager.DEFAULT_SAVE.ranks.is_empty(),
		"дефолт унёс ранги: %s" % [SkillManager.DEFAULT_SAVE.ranks]
	)

	SkillManager.reset()
	_check(
		"новая игра: ранги сброшены",
		SkillManager.save.ranks.is_empty(),
		"остались ранги: %s" % [SkillManager.save.ranks]
	)
	_check(
		"новая игра: очки сброшены",
		SkillManager.save.skill_points == SkillManager.DEFAULT_SAVE.skill_points,
		"skill_points=%d" % SkillManager.save.skill_points
	)


## Надеть на душу тело с заданным остатком кармана распада (maximum фиксирован
## BODY_DECAY_MAX, модификаторов на BODY_DECAY нет — эффективный максимум
## совпадает с авторским). C_Embodied обязателен: expel() выходит немедленно
## без него (soul.has_component(C_Embodied) — первая проверка внутри).
func _wear_body(soul: Entity, remaining: float) -> void:
	if not soul.has_component(C_Embodied):
		soul.add_component(C_Embodied.new())
	var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
	if decay == null:
		decay = C_BodyDecay.new()
		decay.maximum = BODY_DECAY_MAX
		soul.add_component(decay)
	decay.remaining = remaining


func _make_soul() -> Entity:
	var soul := Entity.new()
	soul.name = "Soul"
	soul.component_resources = [C_PlayerInput.new(), C_Lifespan.new(), C_StatModifiers.new()]
	return soul


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
