# res://src/systems/gameplay/s_third_person_camera.gd
# Группа "gameplay": ставит камеру от третьего лица каждый ОТРИСОВАННЫЙ кадр — опору за интерполированным трансформом
# рига, плечи от габарита надетой формы. Плечи (SpringArm3D) кастуют сами в своём физкадре; маска у них — маска рига,
# урезанная до геометрии: камера упирается ровно в то, во что упирается форма. Вики: [[Вид от третьего лица]].
class_name S_ThirdPersonCamera
extends System

## Геометрия, в которую камера может упереться: static_colliders, moving_colliders, permeable. Акторы (enemies,
## solid_actors) сюда не входят — их камера проходит и растворяет.
const GEOMETRY_MASK := 1 | 1 << 4 | 1 << 5


func query() -> QueryBuilder:
	return q.with_all([C_ThirdPersonCamera, C_Eyes])


## После взгляда: рыскание и тангаж этого кадра.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_CameraLook]}


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var player := entity as E_Player
		if player == null or player.camera_rig == null:
			continue
		var view := entity.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera
		var look := entity.get_component(C_Eyes) as C_Eyes
		place(player, view, look, delta)
		# Экран со своей камерой (облёт полигона) кадр забирает, а закрывшись, оставляет движку выбирать.
		var current := player.get_viewport().get_camera_3d()
		if current == null:
			player.view_camera.make_current()


## Опора, плечи и сторона; [param delta] ноль — сразу на место, без доезда сдвига (вход в мир, перенос).
static func place(player: E_Player, view: C_ThirdPersonCamera, look: C_Eyes, delta: float) -> void:
	var rig := player as Node as Node3D
	var size := player.form_size()
	var eyes := player.eyes.position.y
	if look.eye_position != Vector3.INF:
		eyes = look.eye_position.y  # база глаз формы (O_BodyForm)
	var lift := maxf(eyes + view.pivot_lift * size.x, view.min_pivot - player.foot_offset().y)
	player.camera_rig.global_position = rig.get_global_transform_interpolated().origin + Vector3.UP * lift
	if view.yaw == INF:
		view.yaw = rig.global_rotation.y  # в первый кадр камера смотрит туда же, куда тело
	player.camera_rig.global_rotation = Vector3(view.pitch, view.yaw, 0.0)

	var mask := (player as Node as CollisionObject3D).collision_mask & GEOMETRY_MASK
	player.shoulder.collision_mask = mask
	player.arm.collision_mask = mask
	player.arm.spring_length = maxf(view.min_arm, size.x * view.arm_scale)
	view.reach = view.shoulder_scale * (size.y + view.shoulder_pad)
	var wanted := view.side * view.reach
	view.offset = wanted if delta <= 0.0 else lerpf(view.offset, wanted, 1.0 - exp(-view.side_speed * delta))
	player.shoulder.spring_length = absf(view.offset)
	# Плечо вбок кастует по своей +Z: четверть оборота наводит её вправо или влево. SpringArm3D переставляет детей
	# только по положению, поворот у них свой, поэтому заднее плечо поворачивается обратно и кастует назад от опоры.
	var turn := PI * 0.5 if view.offset >= 0.0 else -PI * 0.5
	player.shoulder.rotation.y = turn
	player.arm.rotation.y = -turn
