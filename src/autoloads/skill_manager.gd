# res://src/autoloads/skill_manager.gd
extends Node

signal skill_unlocked(id: StringName, new_rank: int)
## «Таблица рангов изменилась — пересчитайте всё». Отдельный сигнал от
## skill_unlocked, потому что у них разные адресаты: skill_unlocked — про
## событие для UI («что именно открыли»), а этот — про состояние, и на него
## подписан O_ApplySkillEffects, который читает таблицу целиком. Слать вместо
## него skill_unlocked по разу на каждый уже открытый навык (так делал
## reapply_all) значило бы врать UI о событиях, которых не было.
signal skills_changed

const SAVE_PATH := "user://skills.tres"
## Не preload: preload резолвится на компиляции и в debug/export-сборке падает на
## кастомном ресурсе («Cannot get class ''», godotengine/godot#100100). Грузим в
## рантайме через load() в _init — поэтому var, а не const.
const DEFAULT_SAVE_PATH := "res://data/default_skill_save.tres"
const SKILL_TREE_PATH := "res://data/skill_tree.tres"
var DEFAULT_SAVE: PlayerSkillSave
var SKILL_TREE: RS_SkillTree

var save: PlayerSkillSave


func _init() -> void:
	DEFAULT_SAVE = load(DEFAULT_SAVE_PATH)
	SKILL_TREE = load(SKILL_TREE_PATH)


func _ready() -> void:
	save = _load()


## Текущий ранг навыка (0, если ещё не прокачан).
func get_rank(id: StringName) -> int:
	return save.ranks.get(id, 0)


## Выполнены ли ВСЕ требования навыка. Отделено от can_unlock, потому что у
## двух вопросов разные адресаты: «дошёл ли игрок до этой ветки» (граф решает
## этим, показывать ли карточку) и «может ли купить прямо сейчас» (кнопка).
## Слепив их, дерево прятало бы доступный навык всякий раз, когда кончились очки.
func requirements_met(id: StringName) -> bool:
	var def := SKILL_TREE.get_definition(id)
	if def == null:
		return false
	for req in def.requires:
		if not _requirement_met(req):
			return false
	return true


## Доступен ли навык игроку в дереве — то есть можно ли его вообще брать.
## Правило карточки Skill Tree: видно изученное и следующее доступное; на шаг
## дальше карточка показывается серой (см. is_previewed), а всё, что за ним, не
## существует — поэтому ветка, открывающаяся по сумме рангов, и появляется
## целиком и сразу, а не полем «серых заглушек» на всю глубину.
## Изученный навык виден всегда, даже если требования задним числом перестали
## выполняться: отобранная у игрока на глазах карточка выглядела бы багом.
func is_revealed(id: StringName) -> bool:
	if get_rank(id) > 0:
		return true
	return requirements_met(id)


## Показать ли навык как «следующий шаг»: карточка видна, но серая и не
## нажимается — игрок читает, что его ждёт, ещё не имея на это права.
##
## Ровно ОДИН шаг за границу открытого, а не всё дерево: требование считается
## «почти выполненным», только если его цель сама уже показана игроку и до неё
## остался один ранг. Без проверки на показанность условие «ранг >= 1 - 1»
## выполняется для нуля, и серым засветилась бы вся ветка на два шага вперёд.
func is_previewed(id: StringName) -> bool:
	if is_revealed(id):
		return false
	var def := SKILL_TREE.get_definition(id)
	if def == null:
		return false
	for req in def.requires:
		if not _requirement_within_one_step(req):
			return false
	return true


## Может ли игрок прокачать навык дальше прямо сейчас.
func can_unlock(id: StringName) -> bool:
	var def := SKILL_TREE.get_definition(id)
	if def == null:
		push_warning("SkillManager: неизвестный навык '%s'" % id)
		return false

	var current_rank := get_rank(id)
	var cost := def.cost_for_next_rank(current_rank)
	if cost == -1:
		return false  # уже максимальный ранг

	if save.skill_points < cost:
		return false

	return requirements_met(id)


## Пытается прокачать навык на 1 ранг. Возвращает true при успехе.
func unlock(id: StringName) -> bool:
	if not can_unlock(id):
		return false

	var def := SKILL_TREE.get_definition(id)
	var current_rank := get_rank(id)
	var cost := def.cost_for_next_rank(current_rank)

	save.skill_points -= cost
	save.ranks[id] = current_rank + 1
	_save()

	skill_unlocked.emit(id, current_rank + 1)
	skills_changed.emit()
	return true


## «Новая игра» — чистый лист целиком: дерево обнуляется вместе с миром.
## Смерть этого НЕ делает и делать не должна: прокачанное дерево и есть то, что
## игрок уносит из провалившегося забега (см. RunManager.die и экран смерти).
func reset() -> void:
	save = _fresh_save()
	_save()
	skills_changed.emit()


func add_skill_points(amount: int) -> void:
	save.skill_points += amount
	_save()


## Применяет ВСЕ уже разблокированные навыки — зовётся при спавне игрока, чтобы
## свежая душа получила модификаторы от уже прокачанного дерева. До появления
## C_StatModifiers это был бессмысленный вызов (его и не звали ниоткуда): эффекты
## присваивались полям в момент разблокировки, и новый забег стартовал без них.
func reapply_all() -> void:
	skills_changed.emit()


func _requirement_met(req: RS_SkillRequirement) -> bool:
	match req.type:
		RS_SkillRequirement.Type.SKILL_RANK:
			return get_rank(req.target_skill) >= req.min_value
		RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS:
			var total := 0
			for skill_def in SKILL_TREE.get_branch_skills(req.target_branch):
				total += get_rank(skill_def.id)
			return total >= req.min_value
	return false


## «Требованию не хватает одного шага» — для is_previewed.
func _requirement_within_one_step(req: RS_SkillRequirement) -> bool:
	match req.type:
		RS_SkillRequirement.Type.SKILL_RANK:
			if not is_revealed(req.target_skill):
				return false
			return get_rank(req.target_skill) >= req.min_value - 1
		RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS:
			var total := 0
			var any_revealed := false
			for skill_def in SKILL_TREE.get_branch_skills(req.target_branch):
				total += get_rank(skill_def.id)
				any_revealed = any_revealed or is_revealed(skill_def.id)
			return any_revealed and total >= req.min_value - 1
	return false


func _save() -> void:
	var err := ResourceSaver.save(save, SAVE_PATH)
	if err != OK:
		push_error("SkillManager: не удалось сохранить прогресс навыков, код ошибки %d" % err)


func _load() -> PlayerSkillSave:
	if ResourceLoader.exists(SAVE_PATH):
		var loaded := ResourceLoader.load(SAVE_PATH) as PlayerSkillSave
		if loaded:
			return loaded
		push_warning("SkillManager: файл сохранения повреждён, загружаю дефолтные")
	return _fresh_save()


## Чистый сейв из дефолтного ресурса. Словарь рангов копируется ОТДЕЛЬНО:
## Resource.duplicate() не копирует Dictionary, а отдаёт тот же объект, что лежит
## в res://data/default_skill_save.tres, — и первая же покупка навыка писала бы
## ранги прямо в дефолт, общий на весь процесс. Тогда reset() возвращал бы
## «чистый лист» с чужими рангами, то есть ровно не работал.
func _fresh_save() -> PlayerSkillSave:
	var fresh := DEFAULT_SAVE.duplicate()
	fresh.ranks = DEFAULT_SAVE.ranks.duplicate()
	return fresh
