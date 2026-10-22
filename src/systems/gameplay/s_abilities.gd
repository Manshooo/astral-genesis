# res://src/systems/gameplay/s_abilities.gd
# Группа "gameplay". Нажатие клавиши слота (защёлка C_PlayerInput.ability_pressed) и откаты всех способностей: решает, ЧТО в слоте и можно ли применить, и ставит
# C_Ability.requested. Что способность делает — её система (S_Regeneration); здесь ни одной ветки по виду способности. Вики: [[Захват тела]] §«Способности и слоты».
class_name S_Abilities
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_AbilityLoadout])


## После сверки слотов: нажатие видит способности, проснувшиеся в этом кадре.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_AbilityLoadout]}


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		for component in entity.components.values():
			var ability := component as C_Ability
			if ability:
				ability.cooldown_left = maxf(0.0, ability.cooldown_left - delta)

		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		var number := inp.ability_pressed
		if number == 0:
			continue
		inp.ability_pressed = 0
		# Открытый экран применения не получает; защёлку съели, чтобы не дожила до закрытия.
		if entity.has_component(C_UIBlocked):
			continue
		_use(entity, (entity.get_component(C_AbilityLoadout) as C_AbilityLoadout).view(entity, number))


func _use(entity: Entity, view: C_AbilityLoadout.SlotView) -> void:
	if view.locked:
		C_ScreenMessage.show_on(entity, "HUD_MSG_SLOT_LOCKED", cmd)
		return
	var ability := view.shown()
	if ability == null:
		C_ScreenMessage.show_on(entity, "HUD_MSG_SLOT_EMPTY", cmd)
		return
	if ability.graft_left > 0.0:
		C_ScreenMessage.show_on(entity, "HUD_MSG_ABILITY_GRAFTING", cmd)
		return
	# Поглощённая проснётся кадром позже (S_AbilityLoadout через буфер): до того она не компонент.
	if entity.get_component(ability.get_script()) != ability:
		return
	if ability.cooldown_left > 0.0:
		return  # откат виден на ячейке; нажатие пропадает, а не встаёт в очередь
	var refusal := ability.refusal(entity)
	if refusal != "":
		C_ScreenMessage.show_on(entity, refusal, cmd)
		return
	ability.requested = true
	ability.cooldown_left = ability.cooldown
	ECS.world.emit_event(&"ability_used", entity, ability)
