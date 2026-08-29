class_name RS_SkillTree
extends Resource
## Всё дерево навыков одним ресурсом: навыки и ветки, по которым они разложены.
##
## Граф не хранится отдельным списком рёбер — он ВЫВОДИТСЯ из требований
## навыков (RS_SkillDefinition.requires). Это и есть ответ на «граф должен
## собираться гибко»: связь существует ровно там, где есть требование, и
## нарисовать ребро, которого не проверяет SkillManager, физически нечем.
## Раскладка по колонкам и дорожкам тоже считается — см. SkillGraphLayout.

@export var skills: Array[RS_SkillDefinition] = []
## Порядок веток здесь задаёт порядок ДОРОЖЕК в графе сверху вниз: отдельного
## поля order нет, перетащить строку в инспекторе проще, чем расставлять числа.
@export var branches: Array[RS_SkillBranch] = []


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


## Подпись ветки. Без описания ветки — из id, чтобы новая ветка была видна в
## графе сразу, ещё до того как ей придумали русское имя.
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


## Ветки в порядке дорожек: сначала описанные в branches, затем те, что
## встретились только у навыков. Второй хвост важнее, чем кажется: без него
## навык из ветки, которую забыли описать, не получил бы дорожки и пропал бы.
func ordered_branch_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for branch in branches:
		if branch != null and not ids.has(branch.id):
			ids.append(branch.id)
	for skill in skills:
		if skill != null and not ids.has(skill.branch):
			ids.append(skill.branch)
	return ids
