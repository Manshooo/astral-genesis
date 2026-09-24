class_name RS_SkillTree
extends Resource
## Всё дерево навыков одним ресурсом: навыки и ветки, по которым они разложены.
##
## Граф не хранится отдельным списком рёбер — он ВЫВОДИТСЯ из требований
## навыков (RS_SkillDefinition.requires). Это и есть ответ на «граф должен
## собираться гибко»: связь существует ровно там, где есть требование, и
## нарисовать ребро, которого не проверяет SkillManager, физически нечем.
## Раскладка по колонкам и дорожкам тоже считается — см. SkillGraphLayout.

const DEFAULT_POINTS_FORMAT := "Очки: %d"
const DEFAULT_CURRENCY_FORMS: Array[String] = ["очко", "очка", "очков"]

@export var skills: Array[RS_SkillDefinition] = []
## Порядок веток здесь задаёт порядок ДОРОЖЕК в графе сверху вниз: отдельного
## поля order нет, перетащить строку в инспекторе проще, чем расставлять числа.
@export var branches: Array[RS_SkillBranch] = []

## Валюта дерева называется по-разному (очки навыков, эссенция Архитектора), а
## экран у деревьев один — поэтому название лежит в данных дерева, а не в экране.
@export_group("Валюта")
## Подпись счётчика на экране: ключ перевода или строка с одним %d. Пусто —
## «Очки: %d», как до второго дерева.
@export var points_format: String = ""
## Формы слова для цены ранга — на 1, на 2–4 и на 5+ («очко/очка/очков»): ключи
## перевода или готовые слова. Не ровно три — очки.
@export var currency_forms: Array[String] = []


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


func points_text(amount: int) -> String:
	if points_format.is_empty():
		return DEFAULT_POINTS_FORMAT % amount
	return String(TranslationServer.translate(points_format)) % amount


## Цена ранга словами: «1 очко», «3 эссенции».
func cost_text(amount: int) -> String:
	return format_cost(amount, currency_forms if currency_forms.size() == 3 else DEFAULT_CURRENCY_FORMS)


## Русское правило числа: 1, 21 — первая форма; 2–4, 22–24 — вторая; всё
## остальное, включая 11–14, — третья.
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
