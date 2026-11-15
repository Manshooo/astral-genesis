# res://src/systems/physics/s_camera_aim.gd
# Группа "physics": луч из камеры от третьего лица через центр кадра — точка под прицелом (C_ThirdPersonCamera.aim_point),
# первый из двух лучей прицела. Заодно смена плеча у стены: лучи вбок от опоры. Space-state — только из физкадра.
# Вики: [[Камера от третьего лица]].
class_name S_CameraAim
extends System


func query() -> QueryBuilder:
	return q.with_all([C_ThirdPersonCamera])


## После перемещения: луч из того места, где риг оказался в этом тике.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Movement]}


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var player := entity as E_Player
		if player == null or player.view_camera == null:
			continue
		var view := entity.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera
		var space := player.view_camera.get_world_3d().direct_space_state
		var exclude: Array[RID] = [(player as Node as CollisionObject3D).get_rid()]
		var direction := -player.view_camera.global_basis.z
		var from := player.view_camera.global_position
		# Начинаем напротив глаз, а не от камеры: то, что между камерой и телом, — не цель (камера за плечом видит это
		# лишь потому, что стоит позади).
		from += direction * maxf(0.0, (player.eye_point() - from).dot(direction))
		var to := from + direction * view.aim_range
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
		view.aim_point = hit["position"] if not hit.is_empty() else to
		if view.auto_side:
			_pick_side(player, view, space, exclude)


## Своё плечо упёрлось вдвое, а с другой стороны свободнее — меняем сторону.
func _pick_side(player: E_Player, view: C_ThirdPersonCamera, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> void:
	if view.reach <= 0.0:
		return
	var here := _free_reach(player, view, space, exclude, view.side)
	if here >= view.reach * 0.5:
		return
	if _free_reach(player, view, space, exclude, -view.side) > here + 0.1:
		view.side = -view.side


func _free_reach(player: E_Player, view: C_ThirdPersonCamera, space: PhysicsDirectSpaceState3D, exclude: Array[RID],
		towards: float) -> float:
	var from := player.camera_rig.global_position
	var to := from + player.camera_rig.global_basis.x * towards * view.reach
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, player.shoulder.collision_mask, exclude))
	return from.distance_to(hit["position"]) if not hit.is_empty() else view.reach
