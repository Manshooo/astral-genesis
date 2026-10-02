extends "res://dev/check_harness.gd"
## Проверка graph-UI дерева навыков (карточка Задачи/Карточки/Skill Tree.md):
## раскладка нейросетью SkillGraphLayout и правило видимости
## SkillManager.is_revealed.
## Запускать: godot --headless dev/skill_graph_check.tscn
##
## Ни одного Control здесь не создаётся, и это не экономия: раскладка считается
## в координатах полотна без единого узла именно затем, чтобы её можно было
## проверить без экрана. Всё, что осталось за проверкой (панорама, зум, излом
## синапсов), — отрисовка, и ей место в ручном плейтесте.
##
## SkillManager.save и SkillManager.SKILL_TREE НА ВРЕМЯ проверки подменяются
## заглушками (как в stat_modifiers_check.gd) и возвращаются на место в конце:
## правило видимости читает и то, и другое, а прогонять его на реальном
## сохранении игрока значило бы проверять его прогресс, а не код.

var _original_save: PlayerSkillSave
var _original_tree: RS_SkillTree


func _ready() -> void:
	_original_save = SkillManager.save
	_original_tree = SkillManager.SKILL_TREE

	_run()

	SkillManager.save = _original_save
	SkillManager.SKILL_TREE = _original_tree

	_finish()


func _run() -> void:
	_check_real_tree_layout()
	_check_manual_row()
	_check_unknown_branch()
	_check_branch_requirement_column()
	_check_requirement_cycle()
	_check_visibility()
	_check_preview()


# --- 1. Раскладка боевого дерева ---------------------------------------------


## Наименьшее расстояние между центрами нейронов: два ореола Ø44 не касаются, и
## между ними остаётся место под синапс.
const MIN_NEURON_GAP := 60.0


## Инварианты, без которых сеть нельзя нарисовать: у каждого навыка есть место,
## нейроны не налезают друг на друга, требование ближе к ядру, чем зависимый
## навык (иначе синапс пойдёт к центру и пересечёт всё по дороге), и нейрон
## лежит в секторе своей ветки.
func _check_real_tree_layout() -> void:
	var tree: RS_SkillTree = load("res://data/skill_tree.tres")
	var layout := SkillGraphLayout.build(tree)

	_check("раскладка: место есть у каждого навыка", layout.positions.size() == tree.skills.size())

	var closest := INF
	var ids := layout.positions.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			closest = minf(closest, (layout.positions[ids[i]] as Vector2).distance_to(layout.positions[ids[j]]))
	_check("раскладка: нейроны не налезают друг на друга", closest >= MIN_NEURON_GAP,
			"ближайшие два — в %.0f px" % closest)

	var inward := 0
	for def in tree.skills:
		for req in def.requires:
			if req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			var source: Vector2 = layout.positions[req.target_skill]
			var target: Vector2 = layout.positions[def.id]
			if target.length() <= source.length():
				inward += 1
	_check("раскладка: требование ближе к ядру, чем зависимый навык", inward == 0)

	var sector_branches: Array[StringName] = []
	for branch in layout.branches:
		sector_branches.append(branch["branch"])
	_check(
		"секторы: по одному на каждую ветку и в порядке ordered_branch_ids",
		sector_branches == tree.ordered_branch_ids()
	)

	var outside := 0
	for branch in layout.branches:
		for def in tree.get_branch_skills(branch["branch"]):
			var angle := (layout.positions[def.id] as Vector2).angle()
			if absf(wrapf(angle - float(branch["angle"]), -PI, PI)) > float(branch["half_width"]):
				outside += 1
	_check("секторы: нейрон лежит в секторе своей ветки", outside == 0)


# --- 2. Ручное закрепление слота ---------------------------------------------


## graph_row — аварийный выход для автора дерева, и проверяются обе его стороны:
## закрепление работает (слот 0 — крайний против часовой стрелки, то есть с
## наименьшим углом), а закрепление ДВУХ навыков на один слот не кладёт их друг
## на друга, а откатывает второго к автоматическому.
func _check_manual_row() -> void:
	var pinned := _definition(&"pinned", &"b", 2)
	var collided := _definition(&"collided", &"b", 2)
	var plain := _definition(&"plain", &"b", -1)
	var layout := SkillGraphLayout.build(_tree([pinned, collided, plain], []))

	var angles := []
	for id in [&"pinned", &"collided", &"plain"]:
		angles.append((layout.positions[id] as Vector2).angle())
	_check("graph_row: закреплённый слот соблюдён", angles[0] > angles[1] and angles[0] > angles[2])
	_check(
		"graph_row: спор за слот не кладёт нейроны друг на друга",
		not is_equal_approx(angles[0], angles[1]) and not is_equal_approx(angles[1], angles[2])
	)


# --- 3. Ветка без описания ---------------------------------------------------


## Опечатка в имени ветки не должна прятать навык от игрока: сектор заводится
## по факту существования навыка, а подпись берётся из id.
func _check_unknown_branch() -> void:
	var lonely := _definition(&"lonely", &"forgotten_branch")
	var tree := _tree([lonely], [])
	var layout := SkillGraphLayout.build(tree)

	_check("неизвестная ветка: навык всё равно получил место", layout.positions.has(&"lonely"))
	_check("неизвестная ветка: сектор заведён", layout.branches.size() == 1)
	_check(
		"неизвестная ветка: подпись собрана из id",
		tree.branch_display_name(&"forgotten_branch") == "Forgotten Branch"
	)


# --- 4. Требование по сумме рангов в ветке -----------------------------------


## Ветка, открывающаяся по сумме рангов чужой ветки, обязана встать ДАЛЬШЕ от
## ядра, чем вся эта ветка: она растёт из достижений, а не рядом с ними.
func _check_branch_requirement_column() -> void:
	var root := _definition(&"root", &"core")
	var leaf := _definition(&"leaf", &"core")
	leaf.requires = _requires([_requirement_skill(&"root", 1)])
	var gated := _definition(&"gated", &"secret")
	gated.requires = _requires([_requirement_branch(&"core", 4)])

	var layout := SkillGraphLayout.build(_tree([root, leaf, gated], []))
	_check(
		"сумма рангов: навык встал дальше от ядра, чем вся ветка-требование",
		(layout.positions[&"gated"] as Vector2).length() > (layout.positions[&"leaf"] as Vector2).length()
	)


# --- 5. Циклическая ссылка в данных ------------------------------------------


## Требование, замкнутое в кольцо, — ошибка данных, но она не должна вешать игру
## на открытии дерева. Проверяем именно то, ради чего глубина считается
## релаксацией с потолком проходов: build() возвращается и расставляет всех.
func _check_requirement_cycle() -> void:
	var first := _definition(&"first", &"loop")
	var second := _definition(&"second", &"loop")
	first.requires = _requires([_requirement_skill(&"second", 1)])
	second.requires = _requires([_requirement_skill(&"first", 1)])

	var layout := SkillGraphLayout.build(_tree([first, second], []))
	_check("цикл требований: раскладка досчиталась и не зациклилась", layout.positions.size() == 2)


# --- 6. Правило видимости ----------------------------------------------------


## Правило карточки: видно изученное и следующее доступное. Проверяется на
## синтетическом дереве, потому что здесь важны не конкретные навыки игры, а
## четыре развилки правила — и все четыре ломались бы незаметно.
func _check_visibility() -> void:
	var root := _definition(&"root", &"core", -1, 1)
	var next := _definition(&"next", &"core")
	next.requires = _requires([_requirement_skill(&"root", 1)])
	var deep := _definition(&"deep", &"core")
	deep.requires = _requires([_requirement_skill(&"next", 2)])
	var gated := _definition(&"gated", &"secret")
	gated.requires = _requires([_requirement_branch(&"core", 3)])

	SkillManager.SKILL_TREE = _tree([root, next, deep, gated], [])
	SkillManager.save = PlayerSkillSave.new()
	SkillManager.save.ranks = {}
	SkillManager.save.skill_points = 0

	_check("видимость: корень без требований виден сразу", SkillManager.is_revealed(&"root"))
	_check("видимость: навык за невыполненным требованием скрыт", not SkillManager.is_revealed(&"next"))
	_check(
		"видимость: доступный навык виден и когда очков на него не хватает",
		SkillManager.is_revealed(&"root") and not SkillManager.can_unlock(&"root")
	)

	SkillManager.save.ranks[&"root"] = 1
	_check("видимость: покупка требования открывает следующий навык", SkillManager.is_revealed(&"next"))
	_check(
		"видимость: изученный навык виден на максимальном ранге",
		SkillManager.is_revealed(&"root") and SkillManager.get_rank(&"root") >= 1
	)
	_check("видимость: скрытая ветка ещё не открылась", not SkillManager.is_revealed(&"gated"))

	SkillManager.save.ranks[&"next"] = 2
	_check("видимость: ранг 2 открывает навык, требующий ранг 2", SkillManager.is_revealed(&"deep"))
	_check(
		"видимость: сумма рангов в ветке открывает отдельную ветку целиком",
		SkillManager.is_revealed(&"gated")
	)

	# Изученное не отбирается: требование могло перестать выполняться (респек,
	# правка данных), но карточка, за которую игрок заплатил, остаётся на месте.
	SkillManager.save.ranks[&"deep"] = 1
	SkillManager.save.ranks[&"next"] = 0
	_check(
		"видимость: изученный навык виден, даже если требования уже не выполнены",
		not SkillManager.requirements_met(&"deep") and SkillManager.is_revealed(&"deep")
	)


# --- 7. Предпросмотр «на один шаг» -------------------------------------------


## Серая карточка показывается ровно на ОДИН шаг за границу открытого. Ломается
## это в обе стороны незаметно: без проверки на показанность цели предпросмотр
## расползается по дереву на всю глубину (условие «ранг >= 1 - 1» верно и для
## нуля), а без запаса в один ранг он не появляется вообще.
func _check_preview() -> void:
	var root := _definition(&"root", &"core")
	var next := _definition(&"next", &"core")
	next.requires = _requires([_requirement_skill(&"root", 1)])
	var deep := _definition(&"deep", &"core")
	deep.requires = _requires([_requirement_skill(&"next", 2)])
	var gated := _definition(&"gated", &"secret")
	gated.requires = _requires([_requirement_branch(&"core", 3)])

	SkillManager.SKILL_TREE = _tree([root, next, deep, gated], [])
	SkillManager.save = PlayerSkillSave.new()
	SkillManager.save.ranks = {}
	SkillManager.save.skill_points = 0

	_check("предпросмотр: следующий за открытым навык показан", SkillManager.is_previewed(&"next"))
	_check(
		"предпросмотр: дальше одного шага дерево не видно",
		not SkillManager.is_previewed(&"deep") and not SkillManager.is_revealed(&"deep")
	)
	_check("предпросмотр: открытый навык предпросмотром не считается", not SkillManager.is_previewed(&"root"))

	SkillManager.save.ranks[&"root"] = 1
	_check(
		"предпросмотр: купленное требование убирает серую карточку",
		SkillManager.is_revealed(&"next") and not SkillManager.is_previewed(&"next")
	)
	_check(
		"предпросмотр: до требования ещё два ранга — навык не показан",
		not SkillManager.is_previewed(&"deep")
	)

	SkillManager.save.ranks[&"next"] = 1
	_check(
		"предпросмотр: остался один ранг — навык показан серым",
		SkillManager.is_previewed(&"deep") and not SkillManager.is_revealed(&"deep")
	)
	_check(
		"предпросмотр: ветка за суммой рангов показывается за ранг до открытия",
		SkillManager.is_previewed(&"gated")
	)


# --- Строительство синтетических деревьев ------------------------------------


func _definition(
	id: StringName, branch: StringName, graph_row: int = -1, max_rank: int = 3
) -> RS_SkillDefinition:
	var def := RS_SkillDefinition.new()
	def.id = id
	def.display_name = String(id)
	def.branch = branch
	def.graph_row = graph_row
	def.max_rank = max_rank
	def.cost_per_rank = [1, 2, 3]
	return def


func _requirement_skill(target: StringName, min_value: int) -> RS_SkillRequirement:
	var req := RS_SkillRequirement.new()
	req.type = RS_SkillRequirement.Type.SKILL_RANK
	req.target_skill = target
	req.min_value = min_value
	return req


func _requirement_branch(target: StringName, min_value: int) -> RS_SkillRequirement:
	var req := RS_SkillRequirement.new()
	req.type = RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS
	req.target_branch = target
	req.min_value = min_value
	return req


func _requires(items: Array) -> Array[RS_SkillRequirement]:
	var typed: Array[RS_SkillRequirement] = []
	for item in items:
		typed.append(item)
	return typed


func _tree(definitions: Array, branches: Array) -> RS_SkillTree:
	var tree := RS_SkillTree.new()
	var typed_skills: Array[RS_SkillDefinition] = []
	for def in definitions:
		typed_skills.append(def)
	tree.skills = typed_skills
	var typed_branches: Array[RS_SkillBranch] = []
	for branch in branches:
		typed_branches.append(branch)
	tree.branches = typed_branches
	return tree
