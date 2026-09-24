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
## Нужна отдельно от карточки: по второму экземпляру проверяется, что материал
## частиц у каждых искр свой, а не общий на все карточки.
const SPARKS_SCENE := preload("res://src/ui/skill_tree/skill_sparks.tscn")

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

	SkillManager.SKILL_TREE = tree
	await _check_unlock_effect()


## Эффект покупки: золотая рамка по кромке, искры с этой же кромки и звук.
## Проверяется то, что ломается молча — рамка, забытая зажжённой или погашенной,
## и нормали точек вылета: перепутанный знак не уронит ничего, искры просто
## посыплются ВНУТРЬ карточки, и заметить это можно только глазами и только в
## момент покупки.
##
## С переездом эффекта в AnimationPlayer добавился ещё один тихий способ сломать:
## искры и звук зовутся ДОРОЖКОЙ МЕТОДОВ, а её связь с методом — строка в сцене.
## Переименованный метод не даёт ни ошибки парсера, ни предупреждения — карточка
## просто перестаёт искрить и звучать.
##
## Звук наблюдается запросом (`AudioManager.event_requested`), как в
## footsteps_check: сигнал шлётся до проверки на загруженный проект byProd, так
## что проверка не зависит ни от рантайма, ни от контента. Есть ли просимое
## событие в собранном проекте — вопрос отдельный, и он в byprod_check.
func _check_unlock_effect() -> void:
	SkillManager.save = SkillManager._fresh_save()
	SkillManager.save.skill_points = 5

	var graph: UI_SkillGraph = GRAPH_SCENE.instantiate()
	add_child(graph)
	graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	graph.setup(SkillManager, SkillManager.SKILL_TREE)
	await get_tree().process_frame
	await get_tree().process_frame

	var card: UI_SkillNode = graph._nodes[&"body_snatch"]
	var glow: Control = card.get_node("%Glow")
	_check(
		"эффект: рамка погашена, пока ничего не куплено",
		is_zero_approx(glow.modulate.a),
		"alpha=%.2f" % glow.modulate.a
	)

	# Появление тоже дорожка, и путь свойства в ней — строка: промах по нему не
	# ошибка, а «карточка не доехала». Хуже всего последний кадр — карточка,
	# оставшаяся полупрозрачной и уменьшенной, выглядит как выключенная.
	var effects: AnimationPlayer = card.get_node("%Effects")
	# Заведомо «недоехавшее» состояние: карточка в дереве уже видима и своего
	# размера, и без этого проверка зеленела бы вхолостую — сломанная дорожка
	# просто не трогала бы то, что и так верно.
	card.modulate.a = 0.0
	card.scale = Vector2(0.5, 0.5)
	card.play_reveal()
	effects.advance(effects.get_animation(&"reveal").length + 0.01)
	_check(
		"появление: карточка доезжает до полной видимости и своего размера",
		is_equal_approx(card.modulate.a, 1.0) and card.scale.is_equal_approx(Vector2.ONE),
		"alpha=%.2f, scale=%s" % [card.modulate.a, card.scale]
	)

	var requested: Array[String] = []
	var collect := func(event_path: String, _position: Vector3) -> void:
		requested.append(event_path)
	AudioManager.event_requested.connect(collect)

	card.play_unlock_effect()
	# Кадр: AnimationPlayer накладывает дорожки в своём процессе, а не в play().
	# За него рамка уже чуть погасла — поэтому «зажглась», а не «ровно единица».
	await get_tree().process_frame
	_check(
		"эффект: покупка зажигает рамку",
		glow.modulate.a > 0.5,
		"alpha=%.2f" % glow.modulate.a
	)
	_check(
		"эффект: покупка просит звук",
		requested.has(card.unlock_event),
		"запрошено: %s" % ", ".join(requested)
	)

	var anchor: Control = card.get_node("%SparksAnchor")
	_check(
		"эффект: покупка порождает искры",
		anchor.get_child_count() > 0,
		"дорожка методов никого не позвала"
	)

	# Второй ранг куплен, пока эффект от первого ещё играет — обычное дело, если
	# очки есть и по карточке щёлкают подряд. Дорожки методов бьют по ОДНОМУ разу
	# за проход, и AnimationPlayer.play() на уже играющей анимации её не
	# перезапускает, а продолжает с текущего места: вторая покупка прошла бы
	# молча и без искр. Ошибка тихая вдвойне — на медленных кликах всё правильно.
	var sound_after_first := requested.size()
	var sparks_after_first := anchor.get_child_count()
	card.play_unlock_effect()
	await get_tree().process_frame
	_check(
		"эффект: покупка подряд звучит каждая, а не только первая",
		requested.size() > sound_after_first,
		"звук просили %d раз на две покупки" % requested.size()
	)
	_check(
		"эффект: покупка подряд сыплет искрами каждая",
		anchor.get_child_count() > sparks_after_first,
		"искр после двух покупок: %d" % anchor.get_child_count()
	)
	AudioManager.event_requested.disconnect(collect)
	if anchor.get_child_count() == 0:
		graph.queue_free()
		return

	var sparks: GPUParticles2D = anchor.get_child(0)
	var material: ParticleProcessMaterial = sparks.process_material

	# Материал правится под размер конкретной карточки, поэтому у каждых искр он
	# обязан быть СВОЙ (resource_local_to_scene). Общий не падает и даже не
	# мигает: карточки одного размера, и периметр совпадает — до первой карточки
	# другого размера. Та же ловушка, что со стилбоксом полоски ветки.
	var other: GPUParticles2D = SPARKS_SCENE.instantiate()
	_check(
		"эффект: у каждых искр свой материал, а не общий на все карточки",
		other.process_material != material,
		"resource_local_to_scene снят с ParticleProcessMaterial"
	)
	other.free()

	# Искры обязаны быть приклеены к карточке. По умолчанию у частиц (и CPU, и
	# GPU — это не разница узлов) local_coords выключен: они живут в ГЛОБАЛЬНЫХ
	# координатах и остаются висеть на месте, когда граф после покупки подводит
	# камеру к новым узлам, — карточка уезжает из-под собственной вспышки.
	# Одна булева, вид ломается целиком, ошибки нет.
	_check(
		"эффект: искры приклеены к карточке, а не к экрану",
		sparks.local_coords,
		"local_coords выключен — искры отстанут при подводке камеры"
	)

	# Точки вылета у GPU-частиц лежат ТЕКСТУРОЙ, а не массивом: считает их
	# видеокарта. Читаем обратно тем же способом, каким карточка их кладёт.
	var points := _texture_points(material.emission_point_texture)
	var normals := _texture_points(material.emission_normal_texture)
	_check(
		"эффект: точки вылета доехали до материала",
		not points.is_empty() and points.size() == normals.size(),
		"точек %d, нормалей %d" % [points.size(), normals.size()]
	)
	if points.is_empty() or points.size() != normals.size():
		graph.queue_free()
		return

	var perimeter := Rect2(-card.size * 0.5, card.size)
	var covered := Rect2(points[0], Vector2.ZERO)
	for point in points:
		covered = covered.expand(point)
	_check(
		"эффект: искры вылетают с кромки карточки, а не из центра",
		material.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_DIRECTED_POINTS
			and covered.position.is_equal_approx(perimeter.position)
			and covered.size.is_equal_approx(perimeter.size),
		"форма=%d, точки в %s при карточке %s" % [material.emission_shape, covered, perimeter]
	)

	var inward := PackedStringArray()
	for i in points.size():
		# Нормаль наружу — та, что смотрит ОТ центра: скалярное произведение с
		# самой точкой (она же вектор из центра) положительно.
		if points[i].dot(normals[i]) <= 0.0:
			inward.append("%s→%s" % [points[i], normals[i]])
	_check(
		"эффект: искра отталкивается от своей стороны, а не летит внутрь",
		inward.is_empty(),
		", ".join(inward)
	)

	graph.queue_free()


## Распаковывает текстуру точек вылета обратно в вектора: пиксель RGBF на точку,
## x и y в первых двух каналах.
func _texture_points(texture: Texture2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if texture == null:
		return points
	var image := texture.get_image()
	for i in image.get_width():
		var pixel := image.get_pixel(i, 0)
		points.append(Vector2(pixel.r, pixel.g))
	return points


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
	var wrong_stripe := PackedStringArray()
	var wrong_pips := PackedStringArray()
	var stripe_boxes: Dictionary = {}  # instance_id стилбокса -> id навыка
	for id in graph._nodes:
		var card: UI_SkillNode = graph._nodes[id]
		var bounds := card.get_global_rect()

		# Делений ровно столько, сколько у навыка рангов, и закрашено ровно
		# столько, сколько куплено: число копий образца считает код, и ошибка в
		# нём — это молча навравший игроку счётчик прокачки.
		var pips: Container = card.get_node("%Pips")
		var filled := 0
		for pip in pips.get_children():
			if is_equal_approx(pip.modulate.a, 1.0):
				filled += 1
		if pips.get_child_count() != card.definition.max_rank:
			wrong_pips.append(
				"%s → делений %d при максимуме %d"
				% [id, pips.get_child_count(), card.definition.max_rank]
			)
		elif filled != SkillManager.get_rank(id):
			wrong_pips.append(
				"%s → закрашено %d при ранге %d" % [id, filled, SkillManager.get_rank(id)]
			)

		# Полоска ветки красится через свой StyleBoxFlat. Если он перестанет быть
		# resource_local_to_scene, стилбокс станет ОДНИМ на все карточки: цвет
		# последней покрашенной ветки молча растечётся по всему дереву, и видно
		# это только глазами. Отсюда две проверки разом — свой ли объект у
		# карточки и тот ли на нём цвет.
		var box: StyleBoxFlat = card.get_node("%Stripe").get_theme_stylebox("panel")
		if box == null or not box.bg_color.is_equal_approx(card.accent):
			wrong_stripe.append("%s → цвет не ветки" % id)
		elif stripe_boxes.has(box.get_instance_id()):
			wrong_stripe.append("%s → общий стилбокс с %s" % [id, stripe_boxes[box.get_instance_id()]])
		else:
			stripe_boxes[box.get_instance_id()] = id

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
	_check(
		"%s: полоска ветки своя у каждой карточки" % state,
		wrong_stripe.is_empty(),
		", ".join(wrong_stripe)
	)
	_check(
		"%s: делений по числу рангов, закрашено по купленным" % state,
		wrong_pips.is_empty(),
		", ".join(wrong_pips)
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
