# res://src/systems/physics/s_gravity.gd
# Группа: "physics". Тянет вниз всё, что не летит.
#
# Запрос сформулирован ОТ ОТСУТСТВИЯ возможности: падает всё с C_Velocity, у чего
# нет C_Flight. Отдельного компонента «невесомость» нет намеренно — он был бы
# вторым способом сказать то же самое, и первый же случай, когда их забыли
# согласовать, дал бы летающего и одновременно падающего игрока.
#
# Поэтому же тут нет ни C_Embodied, ни C_PlayerInput: правило «не летишь —
# падаешь» одинаково для души, надетого тела и будущих врагов, и ни одному из них
# не нужно объявлять себя игроком, чтобы упасть.
class_name S_Gravity
extends System


func query() -> QueryBuilder:
	return q.with_all([C_Velocity]).iterate([C_Velocity]).with_none([C_Flight])


## Строго ДО прыжка: прыжок ПЕРЕЗАПИСЫВАЕТ вертикальную скорость, и порядок
## наоборот съедал бы у прыжка один кадр гравитации на старте.
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
			# Срезаем накопленное падение, но НЕ обнуляем: на полу может лежать
			# положительная скорость прыжка прошлого кадра, ещё не успевшего
			# оторвать от земли, и обнулить её значило бы съесть прыжок.
			vel.velocity.y = maxf(vel.velocity.y, 0.0)
