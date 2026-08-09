# res://src/autoloads/skill_manager.gd
extends Node

signal skill_unlocked(id: StringName, new_rank: int)

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


## Может ли игрок прокачать navyk дальше прямо сейчас.
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

	for req in def.requires:
		if not _requirement_met(req):
			return false

	return true


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
	return true


func add_skill_points(amount: int) -> void:
	save.skill_points += amount
	_save()


## Применяет ВСЕ уже разблокированные навыки — вызывай при спавне игрока,
## чтобы O_ApplySkillEffects получил актуальные ранги для только что созданной entity.
func reapply_all() -> void:
	for id in save.ranks.keys():
		skill_unlocked.emit(id, save.ranks[id])


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
	return DEFAULT_SAVE.duplicate()
