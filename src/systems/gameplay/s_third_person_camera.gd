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
	return q.with_all([C_ThirdPersonCamera, C_FPSCamera])


## После взгляда (рыскание и тангаж этого кадра) и после качки первого лица: наведение глаз ниже её перекрывает.
func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_FPSLook, S_FirstPersonMotion]}


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var player := entity as E_Player
		if player == null or player.camera_rig == null:
			continue
		var view := entity.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera
		var look := entity.get_component(C_FPSCamera) as C_FPSCamera
		place(player, view, look, delta)
		_aim_eyes(player, view)
		_hide_first_person(player)
		# Экран со своей камерой (облёт полигона) кадр забирает, а закрываясь, может отдать его камере глаз.
		var current := player.get_viewport().get_camera_3d()
		if current == null or current == player.camera:
			player.view_camera.make_current()


## Опора, плечи и сторона; [param delta] ноль — сразу на место, без доезда сдвига (вход в мир, перенос).
static func place(player: E_Player, view: C_ThirdPersonCamera, look: C_FPSCamera, delta: float) -> void:
	var rig := player as Node as Node3D
	var size := player.form_size()
	var eyes := player.camera.position.y
	if look.eye_position != Vector3.INF:
		eyes = look.eye_position.y  # база глаз без качки S_FirstPersonMotion
	var lift := maxf(eyes + view.pivot_lift * size.x, view.min_pivot - player.foot_offset().y)
	player.camera_rig.global_position = rig.get_global_transform_interpolated().origin + Vector3.UP * lift
	# Рыскание — с самого рига, не с интерполированного: его пишет мышь в кадре отрисовки, а не физика.
	player.camera_rig.global_rotation = Vector3(look.pitch, rig.global_rotation.y, 0.0)

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


## Лучи игры пока идут из камеры в глазах формы. Наводим её в точку под прицелом: луч из глаз приходит туда, куда
## показывает прицел, а дальность считается от тела. Уходит, когда лучи сами станут двумя (шаг 4 карточки).
func _aim_eyes(player: E_Player, view: C_ThirdPersonCamera) -> void:
	if view.aim_point == Vector3.INF:
		return
	var to_aim := view.aim_point - player.camera.global_position
	if to_aim.length() < 0.05 or absf(to_aim.normalized().y) > 0.999:
		return
	player.camera.look_at(view.aim_point, Vector3.UP)


## Руки-муляж и клочья души висят на камере в глазах и снаружи торчали бы из облика. Уходят вместе с наследием
## первого лица (шаг 5 карточки). S_SoulCloud включает клочья только при смене «во плоти / вне тела» — гасим каждый кадр.
func _hide_first_person(player: E_Player) -> void:
	var arms := player.camera.get_node_or_null(NodePath(O_BodyVisual.FP_ARMS_NODE)) as Node3D
	if arms != null:
		arms.visible = false
	# Голова и руки облика «только тенью» (RS_EntityVisuals.hide_from_wearer) — снаружи облик был бы без головы.
	var worn := player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE))
	if worn != null:
		for geo: GeometryInstance3D in worn.find_children("*", "GeometryInstance3D", true, false):
			if geo.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var cloud := player.get_component(C_SoulCloud) as C_SoulCloud
	if cloud == null:
		return
	var wisps := player.get_node_or_null(cloud.wisps_path) as Node3D
	if wisps != null:
		wisps.visible = false
