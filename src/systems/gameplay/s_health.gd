# res://src/systems/gameplay/s_health.gd
# Группа "gameplay". Базовая система здоровья (C_Health у всех): держит current в [0, maximum] и ОДИН раз объявляет смерть — C_Dead и событие "entity_died"
# (несёт сущность — наблюдатели фильтруют). Не решает, кому и за что урон (боевые системы; удар проводит deal_damage), и не решает, что смерть значит — подписчики.
class_name S_Health
extends System


## Одно нанесение урона: кто, кому, сколько и чем. «Чем» — заготовка под способности (сводка раскладывает урон по источникам).
class Damage:
	extends RefCounted

	var source: Entity  ## кто ударил; null — мир (падение, среда)
	var target: Entity
	var amount: float
	var means: StringName  ## чем — id способности/оружия; &"" пока нечем


## Только живые со здоровьем; C_Dead исключает обработанные трупы — смерть объявляется единожды.
func query() -> QueryBuilder:
	return q.with_all([C_Health]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var health := entity.get_component(C_Health) as C_Health
		health.current = clampf(health.current, 0.0, health.effective_maximum(entity))

		if health.current <= 0.0:
			cmd.add_component(entity, C_Dead.new())
			ECS.world.emit_event(&"entity_died", entity)


## ЕДИНСТВЕННЫЙ способ нанести урон: кто, кого и чем остаётся следом (сводка забега из прямой записи в C_Health не собирается). Место для брони, сопротивлений.
## Статическая: бьют из "physics" (S_EnemyAI), ждать такта S_Health значило бы отложить удар; клэмп и смерть делает process().
static func deal_damage(
	target: Entity, amount: float, source: Entity = null, means: StringName = &""
) -> void:
	if target == null or amount <= 0.0:
		return
	var health := target.get_component(C_Health) as C_Health
	if health == null:
		return  # бить нечего: у сущности нет прочности (напр. развоплощённая душа)

	health.current -= amount

	var damage := Damage.new()
	damage.source = source
	damage.target = target
	damage.amount = amount
	damage.means = means
	# Событие, а не прямой вызов статистики: на удар подписываются HUD, звук, ИИ.
	ECS.world.emit_event(&"damage_dealt", target, damage)
