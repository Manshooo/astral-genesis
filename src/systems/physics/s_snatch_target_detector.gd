# res://src/systems/physics/s_snatch_target_detector.gd
# Группа: "physics" — кастует луч, а Jolt крутится на отдельном потоке, поэтому
# space-state запросы безопасны только из _physics_process (как и
# S_InteractionDetector, S_BodySnatch).
#
# Непрерывная детекция цели захвата: каждый физкадр смотрит, есть ли под
# крестиком тело с C_BodySnatchable в пределах capture_range, и держит на нём
# C_SnatchTargeted. Прицел по этой метке превращается в крестик, а S_BodySnatch
# берёт из неё готовую цель вместо собственного луча — один каст на кадр и один
# источник правды о том, «во что мы celим».
class_name S_SnatchTargetDetector
extends System

## Тела-кандидаты живут на слое enemies (layer_3, бит 2) — тот же слой, по
## которому раньше стрелял сам S_BodySnatch.
const ENEMIES_MASK := 1 << 2

var _current_target: Entity = null


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])


## Строго ДО S_BodySnatch: тот читает нашу метку, а не кастует луч сам.
## Буфер команд применяется сразу после process() каждой системы
## (FlushMode.PER_SYSTEM), так что к моменту захвата метка уже проставлена.
func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_BodySnatch]}


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		_clear_target()
		return

	var player := entities[0] as E_Player
	if player == null or player.camera == null:
		_clear_target()
		return

	var snatch := player.get_component(C_BodySnatch) as C_BodySnatch
	# Дальность — стат, а не поле: перк «дотянуться дальше» прибавляет к базе, а
	# не переписывает её (C_StatModifiers).
	var reach := C_StatModifiers.of(player, C_StatModifiers.CAPTURE_RANGE, snatch.capture_range)
	var target := _raycast_body(player.camera, reach)

	if target == _current_target:
		return
	if _current_target and is_instance_valid(_current_target):
		cmd.remove_component(_current_target, C_SnatchTargeted)
	if target:
		cmd.add_component(target, C_SnatchTargeted.new())
	_current_target = target


## Луч из камеры вперёд (−Z) по маске enemies. Возвращает захватываемую Entity
## или null.
func _raycast_body(cam: Camera3D, capture_range: float) -> Entity:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * capture_range
	var space := cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to, ENEMIES_MASK)
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return null
	return _resolve_snatchable(hit.collider)


## Поднимается от коллайдера вверх по дереву до Entity с C_BodySnatchable
## (коллайдер обычно — дочерний CollisionShape3D, а не сама сущность-тело).
func _resolve_snatchable(collider: Object) -> Entity:
	var node := collider as Node
	while node:
		if node is Entity and node.has_component(C_BodySnatchable):
			return node
		node = node.get_parent()
	return null


func _clear_target() -> void:
	if _current_target and is_instance_valid(_current_target):
		cmd.remove_component(_current_target, C_SnatchTargeted)
	_current_target = null
