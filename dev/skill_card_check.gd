extends Control
## Проверка карточки навыка (карточка Задачи/Карточки/Skill Tree.md): начинка
## узла не выходит за его границы ни на одном навыке боевого дерева.
## Запускать: godot --headless dev/skill_card_check.tscn
##
## Это единственная проверка дерева навыков, которая создаёт Control'ы, и
## намеренно: она про ПИКСЕЛИ — как тема, шрифт и длина названия складываются в
## высоту карточки. Раскладка в клетках проверяется без экрана в
## skill_graph_check.tscn, ей отрисовка не нужна.
##
## Повод: «Длительность жизни» переносилась на две строки, столбец не мог ужать
## подпись (у переносящегося Label минимум равен всему тексту), и ряд с ценой
## уезжал НИЖЕ карточки. Глазами это видно только на одном навыке из десяти, а
## headless видит на всех сразу — и на тех, что появятся позже.
##
## SkillManager.save на время проверки подменяется заглушкой и возвращается на
## место: прогресс игрока к геометрии карточки отношения не имеет.

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
	var tree: RS_SkillTree = SkillManager.SKILL_TREE

	# Все ранги по единице: показаны ВСЕ карточки разом, и у каждой в статусе
	# стоит цена следующего ранга — самая длинная из обычных подписей.
	var all_ranks: Dictionary = {}
	for def in tree.skills:
		all_ranks[def.id] = 1
	await _check_cards("куплено", all_ranks)

	# Чистое дерево: корень плюс серые карточки-предпросмотры со «Недоступно».
	await _check_cards("предпросмотр", {})

	# Название, которое не влезет никогда: карточка обязана обрезать подпись
	# ПО СЕБЕ, а не выпустить ряд с ценой наружу. Высоту под две строки держит
	# node_size, но она конечна, и на третьей строке спасает только это.
	SkillManager.SKILL_TREE = _tree_with_long_name()
	await _check_cards("длинное название", {}, false)


func _check_cards(state: String, ranks: Dictionary, check_lines: bool = true) -> void:
	SkillManager.save = SkillManager._fresh_save()
	SkillManager.save.ranks = ranks
	SkillManager.save.skill_points = 5

	# Именно сцена, а не UI_SkillGraph.new(): полотно и слой связей живут в ней,
	# и голый скрипт остался бы без них — проверка при этом позеленела бы вхолостую
	# (карточек нет — нечему и вылезать), поэтому ниже отдельно считаются узлы.
	var graph: UI_SkillGraph = GRAPH_SCENE.instantiate()
	add_child(graph)
	graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph.setup(SkillManager, SkillManager.SKILL_TREE)
	# Два кадра: первый выдаёт карточкам размер, второй — раскладывает начинку
	# контейнерами внутри них.
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		"%s: карточки построены" % state,
		not graph._nodes.is_empty(),
		"граф не создал ни одного узла"
	)

	var spilled := PackedStringArray()
	var clipped := PackedStringArray()
	for id in graph._nodes:
		var card: UI_SkillNode = graph._nodes[id]
		var bounds := card.get_global_rect()
		for child in _descendants(card):
			if not child.visible:
				continue
			# grow(1) — допуск на округление позиций контейнерами: спор идёт о
			# строке, уехавшей на десяток пикселей, а не о субпиксельном крае.
			if not bounds.grow(1.0).encloses(child.get_global_rect()):
				spilled.append("%s → %s" % [id, child.name])
			if child is Label and child.get_line_count() != child.get_visible_line_count():
				clipped.append("%s → %s" % [id, child.text])

	_check(
		"%s: начинка карточки не выходит за её границы" % state,
		spilled.is_empty(),
		", ".join(spilled)
	)
	if check_lines:
		_check(
			"%s: название навыка видно целиком" % state,
			clipped.is_empty(),
			", ".join(clipped)
		)

	graph.queue_free()


func _tree_with_long_name() -> RS_SkillTree:
	var def := RS_SkillDefinition.new()
	def.id = &"very_long"
	def.display_name = "Совершенно невероятно длинное название навыка в несколько строк"
	def.branch = &"possession"
	def.max_rank = 3
	def.cost_per_rank = [1, 2, 3]

	var tree := RS_SkillTree.new()
	var skills: Array[RS_SkillDefinition] = [def]
	tree.skills = skills
	return tree


func _descendants(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	for child in node.get_children():
		if child is Control:
			found.append(child)
		found.append_array(_descendants(child))
	return found


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  ПРОВАЛ %s  (%s)" % [what, detail])
