# res://src/observers/o_apply_skill_effects.gd
# Наблюдатель: переносит дерево перков в модификаторы души. ПЕРЕСОБИРАЕТ вклад источника &"skills" целиком по таблице
# рангов (своей памяти нет): тот же вызов годится на разблокировку, спавн игрока и загрузку, повтор ничего не удваивает.
class_name O_ApplySkillEffects
extends Observer

## Имя источника в C_StatModifiers; улучшения забега лягут отдельным именем.
const SOURCE := &"skills"


func setup() -> void:
	SkillManager.skills_changed.connect(_notify_souls)


## Событие шлём ПО СУЩНОСТЯМ: emit_event(name, null, ...) в GECS — широковещалка без фильтра, each получает entity == null.
func _notify_souls() -> void:
	if ECS.world == null:
		return
	for soul in ECS.world.query.with_all([C_StatModifiers]).execute():
		ECS.world.emit_event(&"skills_changed", soul, null)


## Нагрузки у события нет: наблюдатель читает всю таблицу рангов.
func query() -> QueryBuilder:
	return q.with_all([C_StatModifiers]).on_event(&"skills_changed")


func each(_event, entity: Entity, _payload = null) -> void:
	var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
	if mods == null:
		return

	var flat := {}
	var mult := {}
	SkillManager.fold_modifiers(flat, mult)
	mods.set_source(SOURCE, flat, mult)
