# res://src/systems/physics/s_jump.gd
# Группа "physics". Прыжок — по одной возможности одна система: тело без C_Jump в выборку не попадает. Вторая выборка — те, у кого прыжка НЕТ: jump_pressed — защёлка (взводит E_Player._input,
# гасит тот, кто её съел); обе половины в одном файле, иначе нажатие призрака сработало бы при вселении в прыгучее тело, а «кто гасит» стало бы вопросом порядка.
class_name S_Jump
extends System


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Velocity, C_Jump]), _jump],
		[q.with_all([C_PlayerInput]).with_none([C_Jump]), _swallow],
	]


## Прыгаем, если стоим на полу. Высота — из C_Jump через модификаторы души (C_StatModifiers.of): база принадлежит телу, «+20%» — перку.
func _jump(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.jump_pressed:
			continue
		inp.jump_pressed = false

		var body := entity as Node as CharacterBody3D
		if body == null or not body.is_on_floor():
			continue
		var jump := entity.get_component(C_Jump) as C_Jump
		var vel := entity.get_component(C_Velocity) as C_Velocity
		vel.velocity.y = C_StatModifiers.of(entity, C_StatModifiers.JUMP_VELOCITY, jump.velocity)


## Прыгать нечем — гасим защёлку. Сообщаем только игроку ВО ПЛОТИ (причина отказа, как «Нужно тело»); развоплощённому — нет: подниматься взглядом ЗАДУМАНО.
func _swallow(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		if not inp.jump_pressed:
			continue
		inp.jump_pressed = false

		if entity.has_component(C_Embodied):
			C_ScreenMessage.show_on(entity, "HUD_MSG_NO_JUMP", cmd)
