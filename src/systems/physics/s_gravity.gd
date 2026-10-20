# res://src/systems/physics/s_gravity.gd
# Группа "physics". Тянет вниз всё с C_Velocity без C_Flight. Запрос от ОТСУТСТВИЯ возможности: отдельного «невесомого» компонента нет намеренно; C_Embodied и C_PlayerInput
# не нужны — правило одинаково для души, тела и врагов.
class_name S_Gravity
extends System


func query() -> QueryBuilder:
	return q.with_all([C_Velocity]).iterate([C_Velocity]).with_none([C_Flight])


## Строго ДО прыжка: прыжок ПЕРЕЗАПИСЫВАЕТ вертикальную скорость.
func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_Jump]}


func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var velocity_comps: Array = components[0]

	for i in entities.size():
		var vel := velocity_comps[i] as C_Velocity
		var body := entities[i] as Node as CharacterBody3D
		if body == null:
			continue

		if not body.is_on_floor():
			vel.velocity.y -= GameConfig.config.gravity * delta
		else:
			# Срезаем накопленное падение, но НЕ обнуляем: на полу может лежать скорость прыжка прошлого кадра.
			vel.velocity.y = maxf(vel.velocity.y, 0.0)
