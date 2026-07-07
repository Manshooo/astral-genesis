# res://src/systems/physics/s_movement.gd
# Группа: "physics" — должна идти ПОСЛЕ s_playerMovement и s_aiMovement в сцене
# Применяет C_Velocity к CharacterBody3D через move_and_slide().
# Работает для ВСЕХ entity с C_Velocity: игрок, NPC, враги — всем одинаково.
# Ничего не знает об игроке или AI — только физика.
class_name S_Movement
extends System

func query() -> QueryBuilder:
	return q.with_all([C_Velocity]).iterate([C_Velocity])

func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var velocity_comps: Array = components[0]

	for i in entities.size():
		var vel := velocity_comps[i] as C_Velocity

		# Ищем CharacterBody3D — либо entity сам является им (игрок),
		# либо через upcast к Node и downcast (для гетерогенных entity)
		var node: Node = entities[i]
		var body := node as CharacterBody3D
		if not body:
			continue

		body.velocity = vel.velocity
		body.move_and_slide()

		# move_and_slide может скорректировать velocity (стена, потолок) —
		# пишем обратно чтобы следующий кадр знал реальную скорость
		vel.velocity = body.velocity
