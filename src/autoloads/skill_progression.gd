# res://src/autoloads/skill_progression.gd
# Машинерия прокачки (ранги, цена, требования, валюта и её сейв) на любое дерево: SkillManager
# качает БФЖ, ArchitectManager — мир. Валюта дерева лежит в PlayerSkillSave.skill_points;
# как её назвать игроку, решают данные дерева. Вики: [[Захват тела]] (дерево навыков).
class_name SkillProgression
extends Node

signal skill_unlocked(id: StringName, new_rank: int)
## Таблица рангов изменилась — пересчитайте всё (читает O_ApplySkillEffects). Не skill_unlocked:
## тот — событие для UI, и слать его по разу на каждый открытый навык значило бы врать.
signal skills_changed
## Условие ранга выполнено — значение ранга усилено бонусом. Не skills_changed: он не говорит, ЧТО выполнено.
signal condition_completed(id: StringName, rank: int)

## Не preload: падает в debug/export на кастомном ресурсе (godotengine/godot#100100) — load() в _init.
var DEFAULT_SAVE: PlayerSkillSave
var SKILL_TREE: RS_SkillTree

var save: PlayerSkillSave

var _save_path: String
## Есть прогресс условий, не записанный на диск: он идёт кадрами, flush() зовут контрольные точки.
var _dirty := false


func _init(save_path: String, default_save_path: String, tree_path: String) -> void:
	_save_path = save_path
	DEFAULT_SAVE = load(default_save_path)
	SKILL_TREE = load(tree_path)


func _ready() -> void:
	save = _load()


## Текущий ранг навыка (0, если ещё не прокачан).
func get_rank(id: StringName) -> int:
	return save.ranks.get(id, 0)


## Выполнены ли ВСЕ требования. Отдельно от can_unlock: «дошёл до ветки» (показывать ли карточку)
## и «может купить сейчас» (кнопка) — иначе доступный навык прятался бы, когда кончились очки.
func requirements_met(id: StringName) -> bool:
	var def := SKILL_TREE.get_definition(id)
	if def == null:
		return false
	for req in def.requires:
		if not _requirement_met(req):
			return false
	return true


## Можно ли навык вообще брать: видно изученное и следующее доступное, на шаг дальше — серая
## карточка (is_previewed), остальное не существует. Изученный виден всегда, даже если требования
## задним числом перестали выполняться.
func is_revealed(id: StringName) -> bool:
	if get_rank(id) > 0:
		return true
	return requirements_met(id)


## Показать как «следующий шаг»: ровно ОДИН шаг за границу открытого. Требование «почти выполнено»,
## только если его цель уже показана — иначе условие «ранг >= 1 - 1» засветило бы всю ветку.
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
		push_warning("%s: неизвестный навык '%s'" % [name, id])
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


## «Новая игра» — чистый лист. Смерть этого не делает: прокачанное дерево игрок уносит из забега.
func reset() -> void:
	save = _fresh_save()
	_save()
	skills_changed.emit()


## Встреча с владельцем дерева состоялась (PlayerSkillSave.met).
func mark_met() -> void:
	if save.met:
		return
	save.met = true
	_save()


## Встречал ли игрок владельца дерева; старый сейв без поля помнит встречу по следам (ранги, очки).
func is_met() -> bool:
	if save.met or save.skill_points > 0:
		return true
	for rank in save.ranks.values():
		if int(rank) > 0:
			return true
	return false


func add_skill_points(amount: int) -> void:
	save.skill_points += amount
	_save()


## Применяет все разблокированные навыки — при спавне игрока, чтобы свежая душа получила модификаторы.
func reapply_all() -> void:
	skills_changed.emit()


## Модификаторы открытых рангов, свёрнутые по RS_StatModifier.fold — для O_ApplySkillEffects и stat().
func fold_modifiers(flat: Dictionary, mult: Dictionary) -> void:
	for definition in SKILL_TREE.skills:
		var rank := get_rank(definition.id)
		if rank > 0:
			# Бонус условия — значению ранга, только если условие именно этого ранга выполнено.
			var bonus := definition.bonus_for_rank(rank) if is_condition_met(definition.id, rank) else 0.0
			RS_StatModifier.fold(definition.modifiers, rank, flat, mult, bonus)


## Значение стата мира (уровень карты, ручки генерации): души может не быть, поэтому читается
## из дерева по правилу «база плюс модификаторы».
func stat(stat_id: StringName, base: float) -> float:
	var flat := {}
	var mult := {}
	fold_modifiers(flat, mult)
	return RS_StatModifier.resolve(stat_id, base, flat, mult)


## Накопленный прогресс условия ранга [param rank] навыка [param id].
func get_condition_progress(id: StringName, rank: int) -> float:
	return float(save.condition_progress.get(condition_key(id, rank), 0.0))


## Выполнено ли условие ранга; у ранга без условия — false (бонус без условия не за что давать).
func is_condition_met(id: StringName, rank: int) -> bool:
	var def := SKILL_TREE.get_definition(id)
	if def == null:
		return false
	var condition := def.condition_for_rank(rank)
	return condition != null and condition.is_met(get_condition_progress(id, rank))


static func condition_key(id: StringName, rank: int) -> String:
	return "%s:%d" % [id, rank]


## Душа прошла meters по новым клеткам: зачитывается условиям ТЕКУЩИХ рангов (считается с покупки ранга).
func add_distance(meters: float) -> void:
	if meters <= 0.0:
		return
	for definition in SKILL_TREE.skills:
		var rank := get_rank(definition.id)
		var condition := definition.condition_for_rank(rank) if rank > 0 else null
		if condition == null or condition.type != RS_SkillCondition.Type.DISTANCE_NEW_CELLS:
			continue
		var key := condition_key(definition.id, rank)
		var before := float(save.condition_progress.get(key, 0.0))
		if condition.is_met(before):
			continue
		_set_progress(definition, rank, condition, minf(before + meters, condition.target))


## Захвачено тело вида scene_path: каждому условию CAPTURE_KINDS вид засчитывается раз; слабые не считаются.
func note_capture(scene_path: String, body_class: int) -> void:
	if scene_path.is_empty():
		return
	for definition in SKILL_TREE.skills:
		var rank := get_rank(definition.id)
		var condition := definition.condition_for_rank(rank) if rank > 0 else null
		if condition == null or condition.type != RS_SkillCondition.Type.CAPTURE_KINDS:
			continue
		if not condition.accepts_body_class(body_class):
			continue
		var key := condition_key(definition.id, rank)
		var seen: Array = save.condition_seen.get(key, [])
		if seen.has(scene_path) or condition.is_met(float(seen.size())):
			continue
		seen.append(scene_path)
		save.condition_seen[key] = seen
		_set_progress(definition, rank, condition, float(seen.size()))


## Дописать на диск прогресс, накопленный кадрами.
func flush() -> void:
	if _dirty:
		_save()


func _set_progress(
	definition: RS_SkillDefinition, rank: int, condition: RS_SkillCondition, value: float
) -> void:
	save.condition_progress[condition_key(definition.id, rank)] = value
	if not condition.is_met(value):
		_dirty = true
		return
	# Выполнение — событие: пишем сразу (иначе вылет теряет подвиг) и пересчитываем модификаторы.
	_save()
	condition_completed.emit(definition.id, rank)
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


## Требованию не хватает одного шага — для is_previewed.
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
	_dirty = false
	UserResourceFile.write(save, _save_path, name)


func _load() -> PlayerSkillSave:
	var loaded := UserResourceFile.read(_save_path, PlayerSkillSave, name) as PlayerSkillSave
	return loaded if loaded else _fresh_save()


## Чистый сейв из дефолтного ресурса. Словари копируются ОТДЕЛЬНО: duplicate() отдаёт тот же
## Dictionary, и первая покупка писала бы ранги в общий дефолт.
func _fresh_save() -> PlayerSkillSave:
	var fresh := DEFAULT_SAVE.duplicate()
	fresh.ranks = DEFAULT_SAVE.ranks.duplicate()
	# Прогресс условий — тот же Dictionary по ссылке.
	fresh.condition_progress = DEFAULT_SAVE.condition_progress.duplicate(true)
	fresh.condition_seen = DEFAULT_SAVE.condition_seen.duplicate(true)
	return fresh
