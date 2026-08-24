# res://src/systems/gameplay/s_apply_skill_effects.gd
# Наблюдатель: переносит дерево перков в модификаторы души.
#
# Он ПЕРЕСОБИРАЕТ вклад источника &"skills" целиком по текущей таблице рангов, а
# не применяет только что открытый скилл. Так у наблюдателя нет своей памяти:
# один и тот же вызов годится и на разблокировку, и на спавн игрока, и на
# загрузку сейва, и повторное применение ничего не удваивает. Раньше он лез в
# конкретные поля конкретных компонентов (capture_range = 2.0 + rank * 0.5) —
# каждый новый скилл требовал новой ветки здесь, два скилла на один стат затирали
# друг друга, а снять эффект было нечем: база уже была потеряна.
class_name O_ApplySkillEffects
extends Observer

## Имя источника в C_StatModifiers. Улучшения за забег лягут отдельным именем и
## снимутся в конце забега, не трогая перки.
const SOURCE := &"skills"


func setup() -> void:
	SkillManager.skills_changed.connect(_notify_souls)


## Событие шлём ПО СУЩНОСТЯМ, а не один раз с null. emit_event(name, null, ...) в
## GECS — широковещалка: фильтр сущности не применяется вовсе (его не по чему
## вычислять), и each получает entity == null. Прошлая версия наблюдателя делала
## именно так и молча падала на entity.get_component() — из-за чего перки не
## применялись НИКОГДА, ни один.
func _notify_souls() -> void:
	if ECS.world == null:
		return
	for soul in ECS.world.query.with_all([C_StatModifiers]).execute():
		ECS.world.emit_event(&"skills_changed", soul, null)


## Полезной нагрузки у события нет намеренно: что именно открыли, наблюдателю
## неинтересно — он всё равно читает всю таблицу рангов.
func query() -> QueryBuilder:
	return q.with_all([C_StatModifiers]).on_event(&"skills_changed")


func each(_event, entity: Entity, _payload = null) -> void:
	var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
	if mods == null:
		return

	var flat := {}
	var mult := {}
	for definition in SkillManager.SKILL_TREE.skills:
		var rank := SkillManager.get_rank(definition.id)
		if rank <= 0:
			continue
		RS_StatModifier.fold(definition.modifiers, rank, flat, mult)

	mods.set_source(SOURCE, flat, mult)
