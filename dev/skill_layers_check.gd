extends Control
## Проверка фоновых слоёв графа навыков — дорожек-категорий и связей-требований
## (карточка Задачи/Карточки/Skill Tree.md): подложка ветки накрывает свои
## карточки и не лезет на чужие, подпись берётся из данных ветки, ребро есть
## ровно на каждое показанное требование и упирается в края карточек, а слои
## лежат ПОД карточками.
## Запускать: godot --headless dev/skill_layers_check.tscn
##
## Как и skill_card_check, эта проверка создаёт узлы намеренно: и дорожка, и
## связь — это геометрия в пикселях, посчитанная по показанным карточкам, и
## ошибка в ней не падает, а тихо рисует полосу или линию не там. Раскладка в
## клетках проверяется без экрана в skill_graph_check.tscn.
##
## SkillManager.save и SKILL_TREE на время проверки подменяются и возвращаются
## на место: к геометрии дорожек прогресс игрока отношения не имеет.

const GRAPH_SCENE := preload("res://src/ui/skill_tree/skill_graph_view.tscn")

var _ok := 0
var _fail := 0
var _original_save: PlayerSkillSave
var _original_tree: RS_SkillTree


func _ready() -> void:
	_original_save = SkillManager.save
	_original_tree = SkillManager.SKILL_TREE

	await _run()

	SkillManager.save = _original_save
	SkillManager.SKILL_TREE = _original_tree

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	# Боевое дерево: три ветки, все с показанными карточками.
	await _check_layers("боевое дерево", _original_tree, {&"body_snatch": 1, &"lifespan": 1})

	# Синтетическое: у ветки «Бета» показать нечего — её навык за требованием
	# ранга 5, то есть не открыт и даже не в предпросмотре. Дорожка обязана
	# спрятаться целиком: пустая полоса с подписью читается как «здесь что-то
	# есть», хотя ветки для игрока ещё не существует.
	await _check_layers("ветка без карточек", _tree_with_empty_branch(), {})


func _check_layers(state: String, tree: RS_SkillTree, ranks: Dictionary) -> void:
	SkillManager.SKILL_TREE = tree
	SkillManager.save = SkillManager._fresh_save()
	SkillManager.save.ranks = ranks
	SkillManager.save.skill_points = 5

	var graph: UI_SkillGraph = GRAPH_SCENE.instantiate()
	add_child(graph)
	graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph.setup(SkillManager, tree)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		"%s: дорожка заведена на каждую ветку раскладки" % state,
		graph._lanes.size() == graph._layout.lanes.size(),
		"дорожек %d при %d ветках" % [graph._lanes.size(), graph._layout.lanes.size()]
	)

	var missed := PackedStringArray()
	var trespassed := PackedStringArray()
	var wrong_label := PackedStringArray()
	var shown_branches: Dictionary = {}
	for id in graph._nodes:
		shown_branches[tree.get_definition(id).branch] = true

	for branch in graph._lanes:
		var lane: UI_SkillLane = graph._lanes[branch]
		if lane.visible != shown_branches.has(branch):
			missed.append(
				"%s → видна=%s при показанных карточках=%s"
				% [branch, lane.visible, shown_branches.has(branch)]
			)
			continue
		if not lane.visible:
			continue

		var label: Label = lane.get_node("%Name")
		if label.text != tree.branch_display_name(branch):
			wrong_label.append("%s → «%s»" % [branch, label.text])

		var band := lane.get_global_rect()
		for id in graph._nodes:
			var card: UI_SkillNode = graph._nodes[id]
			var card_rect := card.get_global_rect()
			if tree.get_definition(id).branch == branch:
				if not band.grow(1.0).encloses(card_rect):
					trespassed.append("%s → своя карточка %s снаружи" % [branch, id])
			elif band.intersects(card_rect):
				trespassed.append("%s → накрыла чужую карточку %s" % [branch, id])

	_check(
		"%s: дорожка видна ровно там, где есть карточки" % state,
		missed.is_empty(),
		", ".join(missed)
	)
	_check(
		"%s: подложка держит свои карточки и не лезет на чужие" % state,
		trespassed.is_empty(),
		", ".join(trespassed)
	)
	_check(
		"%s: подпись дорожки — имя ветки из данных" % state,
		wrong_label.is_empty(),
		", ".join(wrong_label)
	)

	_check_links(state, tree, graph)

	# Дорожки и связи — фон, и порядок в полотне это единственное, что держит их
	# позади карточек: своего z_index у них нет.
	var canvas := graph.get_node("%Canvas")
	var lanes_index := canvas.get_children().find(graph._lanes_host)
	var links_index := canvas.get_children().find(graph._links_host)
	var first_card_index := canvas.get_child_count()
	for id in graph._nodes:
		first_card_index = mini(first_card_index, canvas.get_children().find(graph._nodes[id]))
	_check(
		"%s: дорожки под связями, связи под карточками" % state,
		lanes_index < links_index and links_index < first_card_index,
		"дорожки %d, связи %d, первая карточка %d" % [lanes_index, links_index, first_card_index]
	)

	graph.queue_free()


## Связи: ребро существует ровно там, где SkillManager проверяет требование
## SKILL_RANK между двумя ПОКАЗАННЫМИ карточками, упирается в края этих карточек
## и бледнеет, если ведёт в предпросмотр. Требование «сумма рангов в ветке»
## рёбер не даёт намеренно — веер линий из всех узлов ветки сообщал бы не
## структуру, а шум, и лишняя связь здесь так же плоха, как потерянная.
func _check_links(state: String, tree: RS_SkillTree, graph: UI_SkillGraph) -> void:
	var expected: Dictionary = {}
	for def in tree.skills:
		if def == null or not graph._nodes.has(def.id):
			continue
		for req in def.requires:
			if req == null or req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			if graph._nodes.has(req.target_skill):
				expected["%s→%s" % [req.target_skill, def.id]] = true

	var missing := PackedStringArray()
	for key in expected:
		if not graph._links.has(key):
			missing.append(key)
	for key in graph._links:
		if not expected.has(key):
			missing.append("лишняя " + key)
	_check(
		"%s: связь на каждое показанное требование, и ни одной лишней" % state,
		missing.is_empty(),
		", ".join(missing)
	)

	var detached := PackedStringArray()
	var not_dimmed := PackedStringArray()
	for key in graph._links:
		var link: UI_SkillLink = graph._links[key]
		var ends: PackedStringArray = key.split("→")
		var source: UI_SkillNode = graph._nodes[StringName(ends[0])]
		var target: UI_SkillNode = graph._nodes[StringName(ends[1])]
		var from := source.position + Vector2(graph.node_size.x, graph.node_size.y * 0.5)
		var to := target.position + Vector2(0.0, graph.node_size.y * 0.5)
		if not link.points[0].is_equal_approx(from) or not link.points[-1].is_equal_approx(to):
			detached.append("%s → %s..%s" % [key, link.points[0], link.points[-1]])

		# Бледность связи в предпросмотр — не украшение: она отличает «путь,
		# которым можно пойти» от «пути, который только показан».
		var dimmed := link.default_color.a < link.line_alpha
		if dimmed != target.previewed:
			not_dimmed.append("%s → бледная=%s при предпросмотре=%s" % [key, dimmed, target.previewed])

	_check(
		"%s: связь упирается в края своих карточек" % state,
		detached.is_empty(),
		", ".join(detached)
	)
	_check(
		"%s: бледная ровно та связь, что ведёт в предпросмотр" % state,
		not_dimmed.is_empty(),
		", ".join(not_dimmed)
	)


## Две ветки, из которых во второй показывать нечего: её единственный навык
## требует пятый ранг корня, то есть недостижим даже для предпросмотра.
func _tree_with_empty_branch() -> RS_SkillTree:
	var root := RS_SkillDefinition.new()
	root.id = &"alpha_root"
	root.display_name = "Корень"
	root.branch = &"alpha"
	root.max_rank = 3
	root.cost_per_rank = [1, 2, 3]

	var requirement := RS_SkillRequirement.new()
	requirement.type = RS_SkillRequirement.Type.SKILL_RANK
	requirement.target_skill = &"alpha_root"
	requirement.min_value = 5

	var far := RS_SkillDefinition.new()
	far.id = &"beta_far"
	far.display_name = "Далёкий"
	far.branch = &"beta"
	far.max_rank = 3
	far.cost_per_rank = [1, 2, 3]
	var requires: Array[RS_SkillRequirement] = [requirement]
	far.requires = requires

	var alpha := RS_SkillBranch.new()
	alpha.id = &"alpha"
	alpha.display_name = "Альфа"
	var beta := RS_SkillBranch.new()
	beta.id = &"beta"
	beta.display_name = "Бета"

	var tree := RS_SkillTree.new()
	var skills: Array[RS_SkillDefinition] = [root, far]
	tree.skills = skills
	var branches: Array[RS_SkillBranch] = [alpha, beta]
	tree.branches = branches
	return tree


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  ПРОВАЛ %s  (%s)" % [what, detail])
