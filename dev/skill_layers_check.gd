extends "res://dev/check_harness.gd"
## Проверка слоёв нейросети навыков (§9 «Меню — спека»): подпись ветки видна
## ровно там, где у ветки есть показанные нейроны, и берётся из данных; синапс
## есть на каждое показанное требование и на каждый корень (от ядра), упирается
## в края нейронов, а не в центры; синапсы лежат ПОД нейронами, подписи веток
## не накрывают нейроны.
## Запускать: godot --headless dev/skill_layers_check.tscn
##
## Как и skill_card_check, эта проверка создаёт узлы намеренно: синапс и подпись
## — геометрия на полотне, посчитанная по показанным нейронам, и ошибка в ней не
## падает, а тихо рисует линию или подпись не там. Раскладка без экрана
## проверяется в skill_graph_check.tscn.
##
## SkillManager.save и SKILL_TREE на время проверки подменяются и возвращаются
## на место: к геометрии сети прогресс игрока отношения не имеет.

const GRAPH_SCENE := preload("res://src/ui/skill_tree/skill_graph_view.tscn")

var _original_save: PlayerSkillSave
var _original_tree: RS_SkillTree


func _ready() -> void:
	_original_save = SkillManager.save
	_original_tree = SkillManager.SKILL_TREE

	await _run()

	SkillManager.save = _original_save
	SkillManager.SKILL_TREE = _original_tree

	_finish()


func _run() -> void:
	# Боевое дерево: три ветки, все с показанными нейронами.
	await _check_layers("боевое дерево", _original_tree, {&"body_snatch": 1, &"lifespan": 1})

	# Синтетическое: у ветки «Бета» показать нечего — её навык за требованием
	# ранга 5, то есть не открыт и даже не в предпросмотре. Подпись ветки обязана
	# спрятаться: подпись над пустотой читается как «здесь что-то есть», хотя
	# ветки для игрока ещё не существует.
	await _check_layers("ветка без нейронов", _tree_with_empty_branch(), {})


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

	var shown_branches: Dictionary = {}
	for id in graph._nodes:
		shown_branches[tree.get_definition(id).branch] = true

	var wrong_visibility := PackedStringArray()
	var wrong_label := PackedStringArray()
	var covering := PackedStringArray()
	for label: Label in graph._labels_host.get_children():
		var branch: StringName = label.get_meta(&"branch")
		if label.visible != shown_branches.has(branch):
			wrong_visibility.append("%s → видна=%s" % [branch, label.visible])
		if label.text != tr(tree.branch_display_name(branch)):
			wrong_label.append("%s → «%s»" % [branch, label.text])
		if not label.visible:
			continue
		for id in graph._nodes:
			var neuron: UI_SkillNeuron = graph._nodes[id]
			if label.get_global_rect().intersects(neuron.get_global_rect()):
				covering.append("%s → накрыла %s" % [branch, id])
	_check("%s: подпись ветки видна ровно там, где есть нейроны" % state,
			wrong_visibility.is_empty(), ", ".join(wrong_visibility))
	_check("%s: подпись ветки — имя из данных" % state, wrong_label.is_empty(), ", ".join(wrong_label))
	_check("%s: подпись ветки не накрывает нейроны" % state, covering.is_empty(), ", ".join(covering))

	_check_links(state, tree, graph)

	var canvas := graph._nodes_host.get_parent()
	_check(
		"%s: синапсы лежат под нейронами" % state,
		graph._links_host.get_index() < graph._nodes_host.get_index() and graph._links_host.get_parent() == canvas,
		"синапсы рисуются поверх узлов"
	)

	graph.queue_free()
	await get_tree().process_frame


## Синапс — на каждое требование SKILL_RANK, у которого показаны оба конца, и
## на каждый показанный корень (от ядра). Лишний синапс — связь, которой не
## проверяет менеджер; недостающий — требование, которого игрок не увидит.
func _check_links(state: String, tree: RS_SkillTree, graph: UI_SkillGraph) -> void:
	var expected: Dictionary = {}
	for def in tree.skills:
		if not graph._nodes.has(def.id):
			continue
		var has_parent := false
		for req in def.requires:
			if req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			has_parent = true
			if graph._nodes.has(req.target_skill):
				expected["%s→%s" % [req.target_skill, def.id]] = true
		if not has_parent:
			expected["→%s" % def.id] = true

	var keys := graph._links.keys()
	keys.sort()
	var wanted := expected.keys()
	wanted.sort()
	_check("%s: синапс ровно на каждое показанное требование и корень" % state, keys == wanted,
			"есть %s, ожидалось %s" % [keys, wanted])

	var off_edge := PackedStringArray()
	for key: String in graph._links:
		var link: UI_SkillSynapse = graph._links[key]
		var line := link.points()
		if line.size() < 2:
			continue
		var ends := key.split("→")
		var from: Vector2 = graph._layout.positions.get(StringName(ends[0]), Vector2.ZERO)
		var to: Vector2 = graph._layout.positions[StringName(ends[1])]
		var start_gap := line[0].distance_to(from)
		var end_gap := line[line.size() - 1].distance_to(to)
		if absf(start_gap - UI_SkillSynapse.NEURON_RADIUS) > 1.0 or absf(end_gap - UI_SkillSynapse.NEURON_RADIUS) > 1.0:
			off_edge.append("%s → %.1f / %.1f" % [key, start_gap, end_gap])
	_check("%s: синапс упирается в края нейронов, а не в центры" % state, off_edge.is_empty(), ", ".join(off_edge))


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
