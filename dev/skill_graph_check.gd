extends Node
## Проверка graph-UI дерева навыков (карточка Задачи/Карточки/Skill Tree.md):
## раскладка SkillGraphLayout и правило видимости SkillManager.is_revealed.
## Запускать: godot --headless dev/skill_graph_check.tscn
##
## Ни одного Control здесь не создаётся, и это не экономия: раскладка считается
## в КЛЕТКАХ, а не в пикселях, именно затем, чтобы её можно было проверить без
## экрана. Всё, что осталось за проверкой (панорама, зум, кривые связей), —
## отрисовка, и ей место в ручном плейтесте.
##
## SkillManager.save и SkillManager.SKILL_TREE НА ВРЕМЯ проверки подменяются
## заглушками (как в stat_modifiers_check.gd) и возвращаются на место в конце:
## правило видимости читает и то, и другое, а прогонять его на реальном
## сохранении игрока значило бы проверять его прогресс, а не код.

var _ok := 0
var _fail := 0
var _original_save: PlayerSkillSave
var _original_tree: RS_SkillTree


func _ready() -> void:
	_original_save = SkillManager.save
	_original_tree = SkillManager.SKILL_TREE

	_run()

	SkillManager.save = _original_save
	SkillManager.SKILL_TREE = _original_tree

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_check_real_tree_layout()
	_check_manual_row()
	_check_unknown_branch()
	_check_branch_requirement_column()
	_check_requirement_cycle()
	_check_visibility()


# --- 1. Раскладка боевого дерева ---------------------------------------------


## Инварианты, без которых граф нельзя нарисовать: у каждого навыка есть клетка,
## клетки не совпадают (иначе карточки лягут друг на друга), требование всегда
## левее зависимого (иначе связь пойдёт назад и пересечёт всё по дороге), а
## строка навыка лежит внутри дорожки его ветки.
func _check_real_tree_layout() -> void:
	var tree: RS_SkillTree = load("res://data/skill_tree.tres")
	var layout := SkillGraphLayout.build(tree)

	_check("раскладка: клетка есть у каждого навыка", layout.cells.size() == tree.skills.size())

	var occupied: Dictionary = {}
	var overlaps := 0
	for id in layout.cells:
		var cell: Vector2i = layout.cells[id]
		if occupied.has(cell):
			overlaps += 1
		occupied[cell] = id
	_check("раскладка: две карточки не встают в одну клетку", overlaps == 0)

	var backwards := 0
	for def in tree.skills:
		for req in def.requires:
			if req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			var source: Vector2i = layout.cells[req.target_skill]
			var target: Vector2i = layout.cells[def.id]
			if target.x <= source.x:
				backwards += 1
	_check("раскладка: требование всегда левее зависимого навыка", backwards == 0)

	var lane_branches: Array[StringName] = []
	for lane in layout.lanes:
		lane_branches.append(lane["branch"])
	_check(
		"дорожки: по одной на каждую ветку и в порядке ordered_branch_ids",
		lane_branches == tree.ordered_branch_ids()
	)

	var outside := 0
	for lane in layout.lanes:
		for def in tree.get_branch_skills(lane["branch"]):
			var row: int = layout.cells[def.id].y
			if row < int(lane["row"]) or row >= int(lane["row"]) + int(lane["height"]):
				outside += 1
	_check("дорожки: навык лежит в строках дорожки своей ветки", outside == 0)

	_check(
		"дорожки: не перекрываются между собой",
		_lanes_disjoint(layout)
	)


func _lanes_disjoint(layout: SkillGraphLayout) -> bool:
	var previous_end := -1
	for lane in layout.lanes:
		if int(lane["row"]) <= previous_end:
			return false
		previous_end = int(lane["row"]) + int(lane["height"]) - 1
	return true


# --- 2. Ручное закрепление строки --------------------------------------------


## graph_row — аварийный выход для автора дерева, и проверяются обе его стороны:
## закрепление работает, а закрепление ДВУХ навыков на одну строку не кладёт их
## друг на друга, а откатывает второго к автоматической строке.
func _check_manual_row() -> void:
	var pinned := _definition(&"pinned", &"b", 2)
	var collided := _definition(&"collided", &"b", 2)
	var plain := _definition(&"plain", &"b", -1)
	var layout := SkillGraphLayout.build(_tree([pinned, collided, plain], []))

	_check("graph_row: закреплённая строка соблюдена", layout.cells[&"pinned"].y == 2)
	_check(
		"graph_row: спор за строку не кладёт карточки друг на друга",
		layout.cells[&"collided"].y != layout.cells[&"pinned"].y
			and layout.cells[&"plain"].y != layout.cells[&"pinned"].y
			and layout.cells[&"collided"].y != layout.cells[&"plain"].y
	)


# --- 3. Ветка без описания ---------------------------------------------------


## Опечатка в имени ветки не должна прятать навык от игрока: дорожка заводится
## по факту существования навыка, а подпись берётся из id.
func _check_unknown_branch() -> void:
	var lonely := _definition(&"lonely", &"forgotten_branch")
	var tree := _tree([lonely], [])
	var layout := SkillGraphLayout.build(tree)

	_check("неизвестная ветка: навык всё равно получил клетку", layout.cells.has(&"lonely"))
	_check("неизвестная ветка: дорожка заведена", layout.lanes.size() == 1)
	_check(
		"неизвестная ветка: подпись собрана из id",
		tree.branch_display_name(&"forgotten_branch") == "Forgotten Branch"
	)


# --- 4. Требование по сумме рангов в ветке -----------------------------------


## Ветка, открывающаяся по сумме рангов чужой ветки, обязана встать ПРАВЕЕ всей
## этой ветки: иначе «отдельная ветка, которая открывается после достижений»
## нарисуется поперёк того, из чего она растёт.
func _check_branch_requirement_column() -> void:
	var root := _definition(&"root", &"core")
	var leaf := _definition(&"leaf", &"core")
	leaf.requires = _requires([_requirement_skill(&"root", 1)])
	var gated := _definition(&"gated", &"secret")
	gated.requires = _requires([_requirement_branch(&"core", 4)])

	var layout := SkillGraphLayout.build(_tree([root, leaf, gated], []))
	_check(
		"сумма рангов: навык встал правее всей ветки-требования",
		layout.cells[&"gated"].x > layout.cells[&"leaf"].x
	)


# --- 5. Циклическая ссылка в данных ------------------------------------------


## Требование, замкнутое в кольцо, — ошибка данных, но она не должна вешать игру
## на открытии дерева. Проверяем именно то, ради чего колонки считаются
## релаксацией с потолком проходов: build() возвращается и расставляет всех.
func _check_requirement_cycle() -> void:
	var first := _definition(&"first", &"loop")
	var second := _definition(&"second", &"loop")
	first.requires = _requires([_requirement_skill(&"second", 1)])
	second.requires = _requires([_requirement_skill(&"first", 1)])

	var layout := SkillGraphLayout.build(_tree([first, second], []))
	_check("цикл требований: раскладка досчиталась и не зациклилась", layout.cells.size() == 2)


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


func _check(label: String, condition: bool) -> void:
	if condition:
		_ok += 1
		print("  ok   %s" % label)
	else:
		_fail += 1
		print("  ПРОВАЛ %s" % label)
