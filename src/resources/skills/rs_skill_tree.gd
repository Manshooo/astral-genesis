class_name RS_SkillTree
extends Resource
## Всё дерево навыков ресурсом: навыки и ветки. Граф не хранится рёбрами — выводится из требований (RS_SkillDefinition.requires), раскладка — SkillGraphLayout.

const DEFAULT_POINTS_FORMAT := "Очки: %d"
const DEFAULT_CURRENCY_FORMS: Array[String] = ["очко", "очка", "очков"]

@export var skills: Array[RS_SkillDefinition] = []
## Порядок веток = порядок ДОРОЖЕК сверху вниз.
@export var branches: Array[RS_SkillBranch] = []

## Валюта называется по-разному, а экран один — название в данных дерева.
@export_group("Валюта")
## Подпись счётчика: ключ перевода или строка с одним %d; пусто — «Очки: %d».
@export var points_format: String = ""
## Формы слова для цены ранга (на 1, 2–4, 5+); не ровно три — очки.
@export var currency_forms: Array[String] = []


## Проверка данных дерева — всё, что ломается тихо: цена на каждый ранг, уникальные id, существующие цели требований, циклы.
## Для dev-проверок и инструментов. Пусто — всё сходится.
func validate() -> Array[String]:
	var problems: Array[String] = []
	var ids := {}
	for skill in skills:
		if skill == null:
			problems.append("null-навык в списке")
			continue
		if ids.has(skill.id):
			problems.append("навык «%s» объявлен дважды" % skill.id)
		ids[skill.id] = skill
		if skill.cost_per_rank.size() < skill.max_rank:
			problems.append(
				"«%s»: max_rank=%d, а цен в cost_per_rank %d"
				% [skill.id, skill.max_rank, skill.cost_per_rank.size()]
			)

	for skill in skills:
		if skill != null:
			problems.append_array(_validate_ranks(skill))

	for skill in skills:
		if skill == null:
			continue
		for req in skill.requires:
			if req == null:
				problems.append("«%s»: null-требование" % skill.id)
			elif req.type == RS_SkillRequirement.Type.SKILL_RANK and not ids.has(req.target_skill):
				problems.append("«%s» требует несуществующий навык «%s»" % [skill.id, req.target_skill])
			elif req.type == RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS and get_branch(req.target_branch) == null:
				problems.append("«%s» требует несуществующую ветку «%s»" % [skill.id, req.target_branch])

	for skill_id: StringName in _cyclic_skills(ids):
		problems.append("«%s» замкнут в цикл требований — не откроется никогда" % skill_id)
	return problems


## Расхождения рангов: значения и условия, не доходящие до max_rank или выходящие за него (ломается тихо).
func _validate_ranks(skill: RS_SkillDefinition) -> Array[String]:
	var problems: Array[String] = []
	for modifier in skill.modifiers:
		if modifier != null and not modifier.values.is_empty() and modifier.values.size() < skill.max_rank:
			problems.append(
				"«%s»: значений по рангам %d, а max_rank=%d" % [skill.id, modifier.values.size(), skill.max_rank]
			)
	if skill.rank_conditions.size() > skill.max_rank:
		problems.append("«%s»: условий %d, а max_rank=%d" % [skill.id, skill.rank_conditions.size(), skill.max_rank])
	if skill.condition_bonus > 0.0 and skill.rank_conditions.is_empty():
		problems.append("«%s»: бонус за условие без единого условия" % skill.id)
	for condition in skill.rank_conditions:
		if condition != null and condition.target <= 0.0:
			problems.append("«%s»: цель условия должна быть больше нуля" % skill.id)
	if skill.ability != &"" and skill.ability_component() == null:
		problems.append("«%s»: неизвестная способность «%s»" % [skill.id, skill.ability])
	return problems


## Навыки на цикле требований SKILL_RANK (обход в глубину с тремя цветами).
func _cyclic_skills(ids: Dictionary) -> Array[StringName]:
	var state := {}  # id -> 1 (в обходе) / 2 (готов)
	var cyclic: Array[StringName] = []
	for skill_id: StringName in ids:
		_visit(skill_id, ids, state, [], cyclic)
	return cyclic


func _visit(
	skill_id: StringName, ids: Dictionary, state: Dictionary, path: Array, cyclic: Array[StringName]
) -> void:
	if state.get(skill_id, 0) == 2:
		return
	if state.get(skill_id, 0) == 1:
		for on_cycle: StringName in path.slice(path.find(skill_id)):
			if not cyclic.has(on_cycle):
				cyclic.append(on_cycle)
		return
	state[skill_id] = 1
	path.append(skill_id)
	var skill: RS_SkillDefinition = ids[skill_id]
	for req in skill.requires:
		if req and req.type == RS_SkillRequirement.Type.SKILL_RANK and ids.has(req.target_skill):
			_visit(req.target_skill, ids, state, path, cyclic)
	path.pop_back()
	state[skill_id] = 2


func get_definition(id: StringName) -> RS_SkillDefinition:
	for skill in skills:
		if skill.id == id:
			return skill
	return null


func get_branch_skills(branch: StringName) -> Array[RS_SkillDefinition]:
	return skills.filter(func(s): return s.branch == branch)


func get_branch(id: StringName) -> RS_SkillBranch:
	for branch in branches:
		if branch != null and branch.id == id:
			return branch
	return null


## Подпись ветки; без описания — из id, чтобы новая ветка была видна сразу.
func branch_display_name(id: StringName) -> String:
	var branch := get_branch(id)
	if branch != null and not branch.display_name.is_empty():
		return branch.display_name
	return String(id).capitalize()


func branch_color(id: StringName) -> Color:
	var branch := get_branch(id)
	if branch != null:
		return branch.color
	return RS_SkillBranch.DEFAULT_COLOR


func points_text(amount: int) -> String:
	if points_format.is_empty():
		return DEFAULT_POINTS_FORMAT % amount
	return String(TranslationServer.translate(points_format)) % amount


## Цена ранга словами: «1 очко», «3 эссенции».
func cost_text(amount: int) -> String:
	return format_cost(amount, currency_forms if currency_forms.size() == 3 else DEFAULT_CURRENCY_FORMS)


## Русское правило числа: 1, 21 — первая форма; 2–4, 22–24 — вторая; остальное, включая 11–14, — третья.
static func format_cost(amount: int, forms: Array[String]) -> String:
	var index := 2
	var tail := amount % 100
	if tail < 11 or tail > 14:
		match amount % 10:
			1:
				index = 0
			2, 3, 4:
				index = 1
	return "%d %s" % [amount, TranslationServer.translate(forms[index])]


## Ветки в порядке дорожек: описанные, затем встретившиеся только у навыков (иначе навык забытой ветки пропал бы).
func ordered_branch_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for branch in branches:
		if branch != null and not ids.has(branch.id):
			ids.append(branch.id)
	for skill in skills:
		if skill != null and not ids.has(skill.branch):
			ids.append(skill.branch)
	return ids
