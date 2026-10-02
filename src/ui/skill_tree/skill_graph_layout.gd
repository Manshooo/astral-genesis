# res://src/ui/skill_tree/skill_graph_layout.gd
## Раскладка дерева навыков нейросетью: где чей нейрон стоит вокруг ядра души.
##
## Считается ОДИН раз по всему дереву — не по видимой его части. В этом весь
## смысл: нейрон навыка стоит на своём месте всегда, и открытие соседа не
## перетасовывает сеть под курсором. Появление узла игрок читает как появление,
## а не как «всё поехало».
##
## Координаты выводятся из данных, а не задаются в них: ветка — сектор вокруг
## ядра, глубина по требованиям — расстояние от ядра. Автору навыка остаётся
## объявить требования, то есть ровно то, что он и так обязан объявить, чтобы
## навык открывался. Прототип расставлял нейроны руками; здесь тот же рисунок
## (ветви лучами от души) получается из данных, и новый навык встаёт на место
## сам (решение 02.10, «UI — переверстка меню»).
##
## Единица — пиксель полотна графа при масштабе 1, центр — ядро (0, 0). Сколько
## это на экране, решает зум UI_SkillGraph; раскладку можно проверить headless,
## не создавая ни одного Control.
class_name SkillGraphLayout
extends RefCounted

## Радиус первого кольца — корней веток — и шаг между кольцами.
const FIRST_RING := 130.0
const RING_STEP := 150.0
## Наименьшая дуга между соседними нейронами одного кольца одной ветки: под
## подпись навыка сбоку от нейрона нужно место.
const MIN_ARC := 96.0
## Доля сектора, которую ветка занимает нейронами: остаток — зазор между
## ветками, чтобы соседние ветки не сливались в одну.
const SECTOR_FILL := 0.8
## Насколько подпись ветки отстоит от её дальнего нейрона.
const LABEL_GAP := 96.0

## StringName (id навыка) -> Vector2 — центр нейрона относительно ядра.
var positions: Dictionary = {}
## StringName (id навыка) -> int — глубина по требованиям (номер кольца).
var tiers: Dictionary = {}
## [{ "branch", "angle", "half_width", "label" }] — секторы веток по часовой
## стрелке от верха; label — где стоит подпись ветки.
var branches: Array[Dictionary] = []


static func build(tree: RS_SkillTree) -> SkillGraphLayout:
	var layout := SkillGraphLayout.new()
	if tree == null:
		return layout

	layout.tiers = _compute_tiers(tree)
	var branch_ids: Array[StringName] = []
	for branch_id in tree.ordered_branch_ids():
		if not tree.get_branch_skills(branch_id).is_empty():
			branch_ids.append(branch_id)
	if branch_ids.is_empty():
		return layout

	var sector := TAU / branch_ids.size()
	for i in branch_ids.size():
		# Первая ветка — вверх: читается первой, как заголовок.
		var center := -PI / 2.0 + i * sector
		var outer := layout._place_branch(tree, branch_ids[i], center, sector * SECTOR_FILL)
		layout.branches.append({
			"branch": branch_ids[i],
			"angle": center,
			"half_width": sector / 2.0,
			"label": Vector2.from_angle(center) * (outer + LABEL_GAP),
		})
	return layout


## Ставит нейроны одной ветки кольцами и возвращает радиус дальнего кольца.
func _place_branch(tree: RS_SkillTree, branch_id: StringName, center: float, spread: float) -> float:
	var by_tier: Dictionary = {}  # int -> Array[RS_SkillDefinition]
	for def in tree.get_branch_skills(branch_id):
		var tier := int(tiers.get(def.id, 0))
		if not by_tier.has(tier):
			by_tier[tier] = []
		by_tier[tier].append(def)

	var keys := by_tier.keys()
	keys.sort()
	var radius := 0.0
	for tier: int in keys:
		var defs: Array = _order_in_tier(by_tier[tier], center)
		var count := defs.size()
		# Кольцо не ближе положенного по глубине и не ближе предыдущего плюс шаг —
		# а если нейронов на нём больше, чем помещается в сектор с дугой MIN_ARC,
		# кольцо отодвигается: на большем радиусе та же дуга занимает меньший угол.
		var wanted := FIRST_RING + tier * RING_STEP
		if radius > 0.0:
			wanted = maxf(wanted, radius + RING_STEP)
		if count > 1:
			wanted = maxf(wanted, MIN_ARC * (count - 1) / spread)
		radius = wanted
		var step := MIN_ARC / radius if count > 1 else 0.0
		for k in count:
			var angle := center + (k - (count - 1) / 2.0) * step
			positions[(defs[k] as RS_SkillDefinition).id] = Vector2.from_angle(angle) * radius
	return radius


## Порядок нейронов по дуге кольца. Закреплённые (graph_row) встают в свой слот,
## остальные — по углу своих требований: навык ложится напротив того, из чего
## растёт, и синапсы не перекрещиваются. Закрепление на занятый слот не
## выигрывает спор, а откатывается к автоматическому — как было и у дорожек.
func _order_in_tier(defs: Array, center: float) -> Array:
	var count := defs.size()
	var slots: Array = []
	slots.resize(count)
	var free: Array = []
	for entry in defs:
		var def := entry as RS_SkillDefinition
		if def.graph_row >= 0 and def.graph_row < count and slots[def.graph_row] == null:
			slots[def.graph_row] = def
		else:
			free.append(def)
	# Стабильная сортировка по углу родителей: при равенстве — порядок в данных.
	var keyed: Array = []
	for i in free.size():
		keyed.append([_parent_angle(free[i], center), i, free[i]])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var cursor := 0
	for k in count:
		if slots[k] == null:
			slots[k] = keyed[cursor][2]
			cursor += 1
	return slots


## Средний угол уже расставленных требований навыка относительно центра
## сектора; без требований — сам центр.
func _parent_angle(def: RS_SkillDefinition, center: float) -> float:
	var sum := 0.0
	var count := 0
	for req in def.requires:
		if req == null or req.type != RS_SkillRequirement.Type.SKILL_RANK:
			continue
		if positions.has(req.target_skill):
			sum += wrapf((positions[req.target_skill] as Vector2).angle() - center, -PI, PI)
			count += 1
	return sum / count if count > 0 else 0.0


## Глубина = длина самой длинной цепочки требований до навыка.
##
## Считается итеративной релаксацией, а не обходом в глубину: требование
## BRANCH_TOTAL_RANKS ссылается на ветку целиком, в том числе на ту, в которой
## навык сам и лежит, — рекурсия на таком требовании ушла бы в цикл. Проходов не
## больше числа навыков: длиннее простой цепочки требований быть не может, а на
## циклической ссылке в данных счётчик просто упрётся в потолок вместо зависания.
static func _compute_tiers(tree: RS_SkillTree) -> Dictionary:
	var result: Dictionary = {}
	for def in tree.skills:
		if def != null:
			result[def.id] = 0

	for _pass in maxi(1, tree.skills.size()):
		var changed := false
		for def in tree.skills:
			if def == null:
				continue
			var tier := 0
			for req in def.requires:
				if req == null:
					continue
				match req.type:
					RS_SkillRequirement.Type.SKILL_RANK:
						if result.has(req.target_skill):
							tier = maxi(tier, int(result[req.target_skill]) + 1)
					RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS:
						for other in tree.get_branch_skills(req.target_branch):
							if other == null or other.id == def.id:
								continue
							tier = maxi(tier, int(result.get(other.id, 0)) + 1)
			if tier != int(result[def.id]):
				result[def.id] = tier
				changed = true
		if not changed:
			break

	return result
