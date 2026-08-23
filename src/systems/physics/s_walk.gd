# res://src/systems/physics/s_walk.gd
# Группа: "physics". Ход по земле — по одной возможности одна система.
#
# Направление берётся в базисе САМОЙ сущности (куда развёрнут риг), а не камеры:
# ходят ногами, а не взглядом. Тем и отличается от полёта (S_Flight), где базис
# камеры и есть смысл механики.
#
# Старт и остановка мгновенные — инерции у шага нет намеренно: шутерный ход
# читается как «управляемый», и инерция здесь ощущалась бы как лёд. Инерция —
# признак полёта, и она живёт там.
class_name S_Walk
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Velocity, C_Walk]).iterate([C_PlayerInput, C_Velocity, C_Walk])


func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var input_comps: Array = components[0]
	var velocity_comps: Array = components[1]
	var walk_comps: Array = components[2]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		var vel := velocity_comps[i] as C_Velocity
		# Entity наследует Node, поэтому до Node3D — через двойной каст.
		var node := entities[i] as Node as Node3D
		if node == null:
			continue

		if inp.move_direction == Vector3.ZERO:
			vel.velocity.x = 0.0
			vel.velocity.z = 0.0
			continue

		# Скорость тела — база, поверх которой ложатся модификаторы души: «бегать
		# быстрее в любом теле» обязано выражаться перком, а не правкой тел.
		var walk := walk_comps[i] as C_Walk
		var speed := C_StatModifiers.of(entities[i], C_StatModifiers.WALK_SPEED, walk.speed)
		var wish := (node.transform.basis * inp.move_direction).normalized()
		vel.velocity.x = wish.x * speed
		vel.velocity.z = wish.z * speed
