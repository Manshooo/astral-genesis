# res://src/systems/gameplay/s_health.gd
# Группа: "gameplay".
# Базовая система здоровья. Следит за C_Health у ВСЕХ сущностей (игрок, враги,
# захваченные тела) и делает ровно две вещи:
#   1. Держит current в пределах [0, maximum] — защита от переотхила/ухода в минус.
#   2. Когда HP падает до нуля, ОДИН раз объявляет о смерти: вешает тег C_Dead и
#      шлёт событие "entity_died" (GECS emit_event -> Observer.on_event).
#      Событие несёт саму сущность, поэтому наблюдатели могут фильтровать, чью
#      именно смерть обрабатывать (напр. только игрока: with_all([C_PlayerInput])).
#
# Чего система намеренно НЕ делает:
#   - не РЕШАЕТ, кому и за что достаётся урон (это дело боевых систем) — но
#     сам удар проводит через себя, см. deal_damage ниже;
#   - не удаляет тело из мира и не решает, что значит смерть для конкретной
#     сущности. На "entity_died" подписываются те, кому это важно: игрок
#     (конец забега / перенос сознания), враг (дроп лута), и т.д.
class_name S_Health
extends System


## Одно нанесение урона: кто, кому, сколько и чем.
##
## «Чем» — заготовка под способности: боевых умений ещё нет, и сегодня ни один
## вызов это поле не заполняет. Но сводка забега обязана уметь разложить урон по
## источникам, а дописать атрибуцию в готовую боевую систему потом всегда дороже,
## чем завести под неё место сразу.
class Damage:
	extends RefCounted

	var source: Entity  ## кто ударил; null — мир (падение, среда)
	var target: Entity
	var amount: float
	var means: StringName  ## чем — id способности/оружия; &"" пока нечем


## Только живые сущности со здоровьем. C_Dead исключает уже обработанные трупы,
## поэтому смерть гарантированно объявляется единожды.
func query() -> QueryBuilder:
	return q.with_all([C_Health]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var health := entity.get_component(C_Health) as C_Health
		health.current = clampf(health.current, 0.0, health.effective_maximum(entity))

		if health.current <= 0.0:
			cmd.add_component(entity, C_Dead.new())
			ECS.world.emit_event(&"entity_died", entity)


## ЕДИНСТВЕННЫЙ способ нанести урон. Раньше боевые системы писали в
## C_Health.current напрямую, и урон нигде не оставлял следа: кто ударил, кого и
## чем, знал только тот кадр, в котором это случилось. Сводка забега («урона
## получено/нанесено») из прямой записи не собирается вовсе, а по падению HP —
## собирается ВРАНЬЁМ: лечение и смена тела выглядят так же.
##
## Здесь же и место для будущей брони, сопротивлений и вампиризма — их некуда
## было бы вписать, останься урон разбросанным по боевым системам.
##
## Статическая, а не метод системы: бьют из "physics" (S_EnemyAI), а сама
## S_Health живёт в "gameplay" — ждать её такта, чтобы применить удар, значило
## бы отложить его на кадр. Клэмп и объявление смерти всё равно делает process()
## этой же системы, здесь только вычитание и след события.
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
	# Событие, а не прямой вызов статистики: удар интересен не только сводке —
	# на него просятся отклик HUD, звук и агрессия ИИ, и все они подписываются
	# сами, не заставляя правку этой функции.
	ECS.world.emit_event(&"damage_dealt", target, damage)
