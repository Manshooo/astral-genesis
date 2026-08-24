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
#
# ДВЕ ВЫБОРКИ, а не одна: желаемое движение приходит либо от игрока
# (C_PlayerInput), либо от простого ИИ (C_EnemyInput, см. S_EnemyAI) — это
# сознательно РАЗНЫЕ компоненты, не один на двоих. Враг с C_PlayerInput уже
# один раз сломал добрый десяток мест, ищущих «игрока» просто по наличию этого
# компонента (RunManager.travel_to, S_InteractionDetector, HUD): с двумя
# такими сущностями `execute_one()` мог вернуть врага, и переход через дверь
# молча промахивался мимо настоящего игрока. Арифметика хода одна на обе
# выборки — она вынесена в _walk().
class_name S_Walk
extends System


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Velocity, C_Walk]), _walk_player],
		[q.with_all([C_EnemyInput, C_Velocity, C_Walk]), _walk_enemy],
	]


func _walk_player(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		_walk(entity, inp.move_direction)


func _walk_enemy(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_EnemyInput) as C_EnemyInput
		_walk(entity, inp.move_direction)


func _walk(entity: Entity, move_direction: Vector3) -> void:
	var vel := entity.get_component(C_Velocity) as C_Velocity
	# Entity наследует Node, поэтому до Node3D — через двойной каст.
	var node := entity as Node as Node3D
	if node == null:
		return

	if move_direction == Vector3.ZERO:
		vel.velocity.x = 0.0
		vel.velocity.z = 0.0
		return

	# Скорость тела — база, поверх которой ложатся модификаторы души: «бегать
	# быстрее в любом теле» обязано выражаться перком, а не правкой тел.
	var walk := entity.get_component(C_Walk) as C_Walk
	var speed := C_StatModifiers.of(entity, C_StatModifiers.WALK_SPEED, walk.speed)
	var wish := (node.transform.basis * move_direction).normalized()
	vel.velocity.x = wish.x * speed
	vel.velocity.z = wish.z * speed
