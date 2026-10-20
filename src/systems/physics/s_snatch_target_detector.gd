# res://src/systems/physics/s_snatch_target_detector.gd
# Группа "physics": луч (space-state только из _physics_process). Каждый физкадр держит C_SnatchTargeted на теле с C_BodySnatchable под крестиком в пределах capture_range;
# прицел и S_BodySnatch читают метку — один каст и один источник правды о цели.
class_name S_SnatchTargetDetector
extends System

## Тела-кандидаты на слое enemies (layer_3, бит 2).
const ENEMIES_MASK := 1 << 2

## Сколько не-целей на enemies луч проходит насквозь — предел против ошибки в данных.
const MAX_PIERCED := 8

var _current_target: Entity = null


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])


## Строго ДО S_BodySnatch (буфер применяется после process() каждой системы, метка уже стоит) и ПОСЛЕ S_Movement — луч из точки тела после тика.
func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_BodySnatch], Runs.After: [S_Movement]}


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		_clear_target()
		return

	var player := entities[0] as E_Player
	if player == null or player.camera == null:
		_clear_target()
		return

	var snatch := player.get_component(C_BodySnatch) as C_BodySnatch
	# Дальность — стат: перк прибавляет к базе (C_StatModifiers).
	var reach := C_StatModifiers.of(player, C_StatModifiers.CAPTURE_RANGE, snatch.capture_range)
	var target := _raycast_body(player.camera, reach)

	if target == _current_target:
		return
	if _current_target and is_instance_valid(_current_target):
		cmd.remove_component(_current_target, C_SnatchTargeted)
	if target:
		cmd.add_component(target, C_SnatchTargeted.new())
	_current_target = target


## Луч из камеры вперёд (−Z) по маске enemies: захватываемая Entity или null. На enemies стоят и живые враги (без C_BodySnatchable) — такой хит луч проходит насквозь,
## иначе враг заслонял бы цели за собой (на moving_colliders его видела бы стеной всякая маска).
func _raycast_body(cam: Camera3D, capture_range: float) -> Entity:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * capture_range
	var space := cam.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(from, to, ENEMIES_MASK)
	var skip: Array[RID] = []
	for _i in MAX_PIERCED:
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			return null
		var target := _resolve_snatchable(hit.collider)
		if target != null:
			return target
		skip.append(hit.rid)
		params.exclude = skip
	return null


## Вверх от коллайдера до Entity с C_BodySnatchable.
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
