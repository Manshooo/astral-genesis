# res://src/world/aim_ray.gd
# Второй луч прицела: от глаз формы к точке под прицелом камеры (C_ThirdPersonCamera.aim_point, первый луч — S_CameraAim).
# Один на интерактив, захват и удар: дальность считается от тела, а не от камеры, и цель за углом, которую камера видит
# из-за плеча, а тело нет, луч от глаз не достаёт. Запросы к space-state — только из систем группы "physics".
# Вики: [[Камера от третьего лица]].
class_name AimRay
extends RefCounted


## Луч от глаз игрока к точке под прицелом длиной [param reach]: [начало, конец]. Точки ещё нет — по взгляду камеры.
static func segment(player: E_Player, reach: float) -> PackedVector3Array:
	var from := player.eye_point()
	var view := player.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera
	var direction := -player.view_camera.global_basis.z
	if view != null and view.aim_point != Vector3.INF and from.distance_to(view.aim_point) > 0.01:
		direction = (view.aim_point - from).normalized()
	return PackedVector3Array([from, from + direction * reach])


## Запрос луча от глаз к точке под прицелом по [param mask], без собственного коллайдера игрока.
static func query(player: E_Player, reach: float, mask: int) -> PhysicsRayQueryParameters3D:
	var ends := segment(player, reach)
	var params := PhysicsRayQueryParameters3D.create(ends[0], ends[1], mask)
	params.exclude = [(player as Node as CollisionObject3D).get_rid()]
	return params
