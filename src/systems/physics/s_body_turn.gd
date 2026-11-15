# res://src/systems/physics/s_body_turn.gd
# Группа "physics": тело игрока поворачивается по направлению передвижения, со скоростью разворота своей способности
# (C_Walk у тела, C_Flight у души), а на ударе и захвате — сразу к точке под прицелом. Камера свободна: взгляд крутит её,
# а не тело (S_CameraLook). Поворот — в физкадре, чтобы его сглаживала интерполяция физики. Вики: [[Камера от третьего лица]].
class_name S_BodyTurn
extends System

## Медленнее этого (м/с по горизонтали) тело стоит и не разворачивается: иначе его крутило бы от остатков скорости.
const MIN_SPEED := 0.1
## Скорость разворота формы без способности передвижения, градусов в секунду.
const FALLBACK_TURN := 540.0


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Velocity, C_ThirdPersonCamera])


## После передвижения — к скорости этого тика; до удара и захвата — они сбрасывают свои флаги, а доворот к прицелу
## должен успеть их увидеть. Точка под прицелом — S_CameraAim.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Movement, S_CameraAim], Runs.Before: [S_Attack, S_BodySnatch]}


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var node := entity as Node as Node3D
		if node == null:
			continue
		var view := entity.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera
		if _wants_aim(entity) and view.aim_point != Vector3.INF:
			var to_aim := view.aim_point - node.global_position
			if Vector2(to_aim.x, to_aim.z).length() > 0.01:
				node.global_rotation.y = yaw_of(to_aim)
				continue
		var velocity := (entity.get_component(C_Velocity) as C_Velocity).velocity
		if Vector2(velocity.x, velocity.z).length() < MIN_SPEED:
			continue
		var step := deg_to_rad(turn_speed(entity)) * delta
		var turn := wrapf(yaw_of(velocity) - node.global_rotation.y, -PI, PI)
		node.global_rotation.y += clampf(turn, -step, step)


## Рыскание, при котором −Z (перёд тела) смотрит вдоль [param direction] в плане.
static func yaw_of(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


static func turn_speed(entity: Entity) -> float:
	var walk := entity.get_component(C_Walk) as C_Walk
	if walk != null:
		return walk.turn_speed
	var flight := entity.get_component(C_Flight) as C_Flight
	if flight != null:
		return flight.turn_speed
	return FALLBACK_TURN


## Удар (есть чем бить) или захват в этом тике — тело встаёт лицом к прицелу.
static func _wants_aim(entity: Entity) -> bool:
	var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
	if inp.attack_pressed and entity.has_component(C_Attack):
		return true
	var snatch := entity.get_component(C_BodySnatch) as C_BodySnatch
	return snatch != null and snatch.capture_requested
