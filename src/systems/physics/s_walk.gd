# res://src/systems/physics/s_walk.gd
# Группа "physics". Ход по земле — по одной возможности одна система. Направление у врага — в базисе самой сущности, у игрока — в базисе взгляда камеры; старт и остановка мгновенные (инерция — признак полёта).
# Две выборки: C_PlayerInput и C_EnemyInput (S_EnemyAI) — РАЗНЫЕ компоненты намеренно (враг с C_PlayerInput ломал поиск «игрока»); арифметика общая — _walk().
class_name S_Walk
extends System


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput, C_Velocity, C_Walk]), _walk_player],
		[q.with_all([C_EnemyInput, C_Velocity, C_Walk]), _walk_enemy],
	]


## Игрок ходит в базисе взгляда камеры, а не тела: тело само поворачивается по направлению передвижения (S_BodyTurn),
## и «вперёд» по своему базису гнало бы его по кругу.
func _walk_player(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		var view := entity.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera
		var basis := (entity as Node as Node3D).global_basis
		if view != null and view.yaw != INF:
			basis = Basis(Vector3.UP, view.yaw)
		_walk(entity, inp.move_direction, basis)


func _walk_enemy(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var inp := entity.get_component(C_EnemyInput) as C_EnemyInput
		_walk(entity, inp.move_direction, (entity as Node as Node3D).global_basis)


## [param basis] МИРОВОЙ: velocity мировая, transform — относительно родителя; враг в комнате, повёрнутой на четверть,
## шёл бы мимо цели (ловит dev/enemy_ai_check).
func _walk(entity: Entity, move_direction: Vector3, basis: Basis) -> void:
	var vel := entity.get_component(C_Velocity) as C_Velocity
	# Entity наследует Node — до Node3D двойной каст.
	var node := entity as Node as Node3D
	if node == null:
		return

	if move_direction == Vector3.ZERO:
		vel.velocity.x = 0.0
		vel.velocity.z = 0.0
		return

	# Скорость тела — база, поверх модификаторы души.
	var walk := entity.get_component(C_Walk) as C_Walk
	var speed := C_StatModifiers.of(entity, C_StatModifiers.WALK_SPEED, walk.speed)
	var wish := (basis * move_direction).normalized()
	vel.velocity.x = wish.x * speed
	vel.velocity.z = wish.z * speed
