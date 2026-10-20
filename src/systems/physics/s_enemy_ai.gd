# res://src/systems/physics/s_enemy_ai.gd
# ИИ врага: обнаружение, память, путь, удар ([[Захват тела]] → «Угроза», «Обнаружение, память и путь»). "physics": лучи обзора и к дверям — space-state только из физпотока.
# Двигает через C_EnemyInput, НЕ C_PlayerInput: по нему десяток мест ищет игрока.
class_name S_EnemyAI
extends System

## Атрибуция удара для сводки (S_Health.Damage.means).
const MEANS := &"enemy_melee"

## Высота глаз цели над ногами, если у цели нет камеры.
const FALLBACK_TARGET_EYE := 1.5

## Длина луча к двери по ходу, м (с запасом на радиус капсулы).
const DOOR_PROBE := 1.6
## Высота луча поиска полотна над ногами, м.
const DOOR_PROBE_HEIGHT := 1.0
const MOVING_LAYER := 1 << 4


func deps() -> Dictionary[int, Array]:
	return {Runs.Before: [S_Walk]}


func query() -> QueryBuilder:
	# Без C_Dead: труп встаёт на место врага отложенно, мёртвый в это окно не бьёт.
	return q.with_all([C_EnemyAI, C_EnemyInput, C_Velocity, C_Walk]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	var target := _find_target()
	var target_node: Node3D = null
	if target != null:
		target_node = target as Node as Node3D

	for entity in entities:
		var ai := entity.get_component(C_EnemyAI) as C_EnemyAI
		var inp := entity.get_component(C_EnemyInput) as C_EnemyInput
		var node := entity as Node as Node3D
		if node == null:
			continue

		ai.attack_cooldown_left = maxf(0.0, ai.attack_cooldown_left - delta)

		if target_node == null:
			_stand_down(ai, inp)
			continue

		var offset := target_node.global_position - node.global_position
		offset.y = 0.0
		var distance := offset.length()

		var fresh_check := _update_sight(ai, node, target, target_node, offset, distance, delta)
		_update_state(ai, target_node, fresh_check, delta)

		match ai.state:
			C_EnemyAI.State.CHASING:
				if distance <= ai.attack_range:
					if distance > 0.001:
						node.look_at(node.global_position + offset, Vector3.UP)
					inp.move_direction = Vector3.ZERO
					_attack(entity, target, ai)
				else:
					# К месту, где видел, а не к цели: между проверками враг знает о ней лишь увиденное.
					_steer(ai, node, inp, ai.last_seen_position, delta)
			C_EnemyAI.State.SEARCHING:
				_search(ai, node, inp, delta)
			_:
				inp.move_direction = Vector3.ZERO


func _stand_down(ai: C_EnemyAI, inp: C_EnemyInput) -> void:
	ai.state = C_EnemyAI.State.IDLE
	ai.sees_target = false
	ai.path = PackedVector3Array()
	inp.move_direction = Vector3.ZERO


# --- Обнаружение ---


## true — проверка была на ЭТОМ кадре; last_seen_position обновляется только по свежей.
func _update_sight(
	ai: C_EnemyAI,
	node: Node3D,
	target: Entity,
	target_node: Node3D,
	offset: Vector3,
	distance: float,
	delta: float,
) -> bool:
	ai.sight_left -= delta
	if ai.sight_left > 0.0:
		return false
	# Разброс — чтобы заметившие в один кадр не бросали лучи пачкой.
	ai.sight_left = ai.sight_interval * randf_range(0.8, 1.2)
	ai.sees_target = _can_see(ai, node, target, target_node, offset, distance)
	return true


func _can_see(
	ai: C_EnemyAI,
	node: Node3D,
	target: Entity,
	target_node: Node3D,
	offset: Vector3,
	distance: float,
) -> bool:
	if distance > ai.aggro_range:
		return false

	# Конус — только чтобы заметить: встревоженному хватает луча.
	if ai.state == C_EnemyAI.State.IDLE and distance > ai.awareness_range:
		var facing := -node.global_basis.z
		facing.y = 0.0
		if facing.angle_to(offset) > deg_to_rad(ai.view_angle) * 0.5:
			return false

	var from := node.global_position + Vector3.UP * ai.eye_height
	var to := _eye_of(target, target_node)
	var ray := PhysicsRayQueryParameters3D.create(from, to, ai.sight_mask)
	ai.sight_rays += 1
	var hit := node.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty()


func _eye_of(target: Entity, target_node: Node3D) -> Vector3:
	var player := target as E_Player
	if player != null and player.camera != null:
		return player.camera.global_position
	return target_node.global_position + Vector3.UP * FALLBACK_TARGET_EYE


func _update_state(
	ai: C_EnemyAI, target_node: Node3D, fresh_check: bool, delta: float
) -> void:
	if ai.sees_target:
		ai.state = C_EnemyAI.State.CHASING
		if fresh_check:
			ai.last_seen_position = target_node.global_position
		return

	match ai.state:
		C_EnemyAI.State.CHASING:
			ai.state = C_EnemyAI.State.SEARCHING
			ai.search_left = ai.search_timeout
			ai.arrived = false
			ai.repath_left = 0.0
		C_EnemyAI.State.SEARCHING:
			ai.search_left -= delta
			if ai.search_left <= 0.0:
				ai.state = C_EnemyAI.State.IDLE
				ai.path = PackedVector3Array()


# --- Движение ---


func _search(ai: C_EnemyAI, node: Node3D, inp: C_EnemyInput, delta: float) -> void:
	if not ai.arrived:
		var rest := ai.last_seen_position - node.global_position
		rest.y = 0.0
		if rest.length() <= ai.arrive_distance:
			ai.arrived = true
			ai.search_left = minf(ai.search_left, ai.linger_time)
		else:
			_steer(ai, node, inp, ai.last_seen_position, delta)
			return
	inp.move_direction = Vector3.ZERO


## Шаг к goal: по точкам пути навмеша, без пути — по прямой; move_direction уже в мировом базисе.
func _steer(
	ai: C_EnemyAI, node: Node3D, inp: C_EnemyInput, goal: Vector3, delta: float
) -> void:
	ai.repath_left -= delta
	if ai.repath_left <= 0.0:
		ai.repath_left = ai.repath_interval
		var map := LayerNavigation.map_for(node, ai.nav_profile)
		# Карта до первой синхронизации отвечает ошибкой в лог, а не пустым путём.
		if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
			ai.path = PackedVector3Array()
		else:
			ai.path = NavigationServer3D.map_get_path(map, node.global_position, goal, true)
		ai.path_index = 1  # нулевая точка — сам враг

	var aim := goal
	if ai.path.size() > 1:
		while ai.path_index < ai.path.size() - 1 \
				and _flat_distance(node.global_position, ai.path[ai.path_index]) < ai.waypoint_reach:
			ai.path_index += 1
		if ai.path_index < ai.path.size() \
				and _flat_distance(node.global_position, ai.path[ai.path_index]) >= ai.waypoint_reach:
			aim = ai.path[ai.path_index]
		# Иначе путь кончился у ближайшей к цели точки навмеша — остаток по прямой.

	var heading := aim - node.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.0001:
		inp.move_direction = Vector3.ZERO
		return
	node.look_at(node.global_position + heading, Vector3.UP)
	inp.move_direction = Vector3.FORWARD
	if ai.opens_doors:
		_open_door_ahead(node, heading)


## Навмеш запечён сквозь проёмы — путь упирается в закрытое полотно; S_DoorMotion.open, не interact() (тот про игрока).
func _open_door_ahead(node: Node3D, heading: Vector3) -> void:
	var from := node.global_position + Vector3.UP * DOOR_PROBE_HEIGHT
	var ray := PhysicsRayQueryParameters3D.create(from, from + heading.normalized() * DOOR_PROBE, MOVING_LAYER)
	var hit := node.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return
	var door := _door_of(hit.collider as Node)
	if door == null:
		return
	var portal := door.get_component(C_DoorPortal) as C_DoorPortal
	if portal != null and (portal.is_locked() or portal.target_node_id == &""):
		return
	S_DoorMotion.open(door)


func _door_of(leaf: Node) -> Entity:
	var node := leaf
	while node != null:
		if node is Entity and (node as Entity).has_component(C_DoorMotion):
			return node as Entity
		node = node.get_parent()
	return null


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _attack(entity: Entity, target: Entity, ai: C_EnemyAI) -> void:
	if ai.attack_cooldown_left > 0.0:
		return
	ai.attack_cooldown_left = ai.attack_interval
	# Через воронку: на следе удара держится сводка забега.
	S_Health.deal_damage(target, ai.attack_damage, entity, MEANS)


func _find_target() -> Entity:
	return ECS.world.query.with_all([C_BodySnatch, C_Embodied, C_Health]).execute_one()
