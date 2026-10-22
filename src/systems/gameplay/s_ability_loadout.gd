# res://src/systems/gameplay/s_ability_loadout.gd
# Группа "gameplay". Будит поглощённые способности душе и усыпляет их: работает компонентом только та, чей слот открыт, не занят способностью тела и уже приросла.
# Здесь же тикают прирастание слотов и окно «в бою» (C_AbilityLoadout.combat_left).
# Сверка каждый кадр, а не наблюдатель на захват и выход: воплощают три пути (захват, загрузка, выход), правило в каждом разъехалось бы. Вики: [[Захват тела]] §«Способности и слоты».
class_name S_AbilityLoadout
extends System


func query() -> QueryBuilder:
	return q.with_all([C_AbilityLoadout])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var loadout := entity.get_component(C_AbilityLoadout) as C_AbilityLoadout
		loadout.combat_left = maxf(0.0, loadout.combat_left - delta)
		for held in loadout.slots:
			if held:
				held.graft_left = maxf(0.0, held.graft_left - delta)
		var awake := awake_abilities(entity, loadout)
		for component in entity.components.values():
			var ability := component as C_Ability
			if ability and ability.absorbed and not awake.has(ability):
				cmd.remove_component(entity, ability.get_script())
		for ability in awake:
			if entity.get_component(ability.get_script()) != ability:
				cmd.add_component(entity, ability)


## Поглощённые, которым положено работать сейчас. Класс уже занят телом — спит: компонент одного класса на сущности один.
static func awake_abilities(entity: Entity, loadout: C_AbilityLoadout) -> Array[C_Ability]:
	var awake: Array[C_Ability] = []
	for number in range(1, C_AbilityLoadout.open_slots(entity) + 1):
		var view := loadout.view(entity, number)
		if view.soul == null or view.body != null or view.soul.graft_left > 0.0:
			continue
		var holder := entity.get_component(view.soul.get_script()) as C_Ability
		if holder != null and not holder.absorbed:
			continue
		awake.append(view.soul)
	return awake
