extends Node3D
## Прототип камеры от третьего лица для станции полигона: опора за ригом игрока, плечо вбок и плечо назад
## (SpringArm3D), своя Camera3D. Взгляд пока едет на S_FPSLook: рыскание — с рига, тангаж — из C_FPSCamera.
## Это стенд для подбора чисел, а не игровая камера: на шаге 2 она переезжает в src. Вики: [[Полигон]], [[Вид от третьего лица]].

## Геометрия, в которую камера может упереться: static_colliders, moving_colliders, permeable. Упирается она только
## в то из этого, во что упирается сама форма (решение 05.11), поэтому маска плеча — маска рига, урезанная до этих слоёв.
const GEOMETRY_MASK := 1 | 1 << 4 | 1 << 5
const FADE_MODES: Array[int] = [
	BaseMaterial3D.DISTANCE_FADE_DISABLED,
	BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER,
	BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER,
]
const FADE_NAMES: Array[String] = ["выкл", "объект", "пиксель"]

## Длина плеча назад — доля роста формы, но не короче min_arm.
@export var arm_scale := 1.0
@export var min_arm := 1.6
## Сдвиг вбок — доля от (радиус формы + shoulder_pad).
@export var shoulder_scale := 1.0
@export var shoulder_pad := 0.35
## Сторона плеча: 1 — правое, −1 — левое.
@export var side := 1.0
## Опора над глазами формы — доля роста; ниже нуля — под глазами.
@export var pivot_lift := 0.0
## Опора не ниже стольких метров над подошвой: у маленькой формы (душа — 0.52 м) сфера плеча иначе
## цепляла бы пол от малейшего наклона взгляда, и камера прыгала бы к форме и обратно.
@export var min_pivot := 0.9
## Докуда луч из камеры ищет точку под прицелом.
@export var aim_range := 100.0
## Менять плечо, когда своё упёрлось вдвое, а с другой стороны свободнее.
@export var auto_side := false
## Как гаснет надетый облик вблизи: индекс в FADE_MODES; ближе own_fade_min облика не видно, дальше own_fade_max он плотный.
@export var own_fade := 1
@export var own_fade_min := 0.6
@export var own_fade_max := 1.6
## Как быстро сдвиг доезжает до стороны после смены плеча, 1/с.
@export var side_speed := 6.0

var active := false
## Текущий сдвиг вбок со знаком стороны: при смене плеча он проходит через ноль, а не прыгает.
var _offset := 0.0
## Полный сдвиг вбок у нынешней формы — его и меряет смена плеча у стены.
var _reach := 0.0
## Облик, которому уже открыты голова и руки и выданы копии материалов.
var _worn: Node
## GeometryInstance3D → что вернуть: {"shadow", "override", "surfaces"}.
var _restore := {}
## Что плечи не видят: свой риг. Список хранится здесь — у SpringArm3D нет геттера исключений.
var _excluded: Array[RID] = []
## Точка под прицелом — куда смотрит луч из камеры через центр кадра; ищется в физкадре.
var aim := Vector3.INF

@onready var shoulder: SpringArm3D = $Shoulder
@onready var arm: SpringArm3D = $Shoulder/Arm
@onready var camera: Camera3D = $Shoulder/Arm/Camera3D


func _ready() -> void:
	# Риг сам идёт за интерполированным трансформом игрока; интерполируй его движок ещё раз — камера отставала бы на тик.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)
	set_physics_process(false)


func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	set_process(on)
	set_physics_process(on)
	var player := E_Player.find() as E_Player
	if player == null:
		return
	if on:
		_excluded = [(player as Node as CollisionObject3D).get_rid()]
		for spring: SpringArm3D in [shoulder, arm]:
			spring.clear_excluded_objects()
			spring.add_excluded_object(_excluded[0])
		_follow(player, 0.0)
		camera.make_current()
	else:
		_dress_down()
		_show_first_person(player, true)
		aim = Vector3.INF
		var look := player.get_component(C_FPSCamera) as C_FPSCamera
		player.camera.rotation = Vector3(look.pitch if look != null else 0.0, 0.0, 0.0)
		if camera.current:
			player.camera.make_current()


## Перечитать облик: сменился режим или расстояния дизера.
func refresh() -> void:
	_dress_down()


## Высота и радиус формы рига — по его коллайдеру, как E_Player.foot_offset, а не числом.
static func form_size(player: Node) -> Vector2:
	var holder := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape := holder.shape if holder != null else null
	if shape == null:
		return Vector2.ZERO
	var radius := 0.0
	if shape is SphereShape3D:
		radius = (shape as SphereShape3D).radius
	elif shape is CapsuleShape3D:
		radius = (shape as CapsuleShape3D).radius
	elif shape is CylinderShape3D:
		radius = (shape as CylinderShape3D).radius
	elif shape is BoxShape3D:
		var box := (shape as BoxShape3D).size
		radius = maxf(box.x, box.z) * 0.5
	return Vector2(maxf(E_Player.shape_half_height(shape) * 2.0, 0.0), radius)


## Копия материала с дизером по расстоянию до камеры; общий материал не трогается. Не BaseMaterial3D — как есть.
static func faded_copy(material: Material, mode: int, near: float, far: float) -> Material:
	var base := material as BaseMaterial3D
	if base == null:
		return material
	var copy := base.duplicate() as BaseMaterial3D
	copy.distance_fade_mode = mode as BaseMaterial3D.DistanceFadeMode
	copy.distance_fade_min_distance = near
	copy.distance_fade_max_distance = far
	return copy


func _process(delta: float) -> void:
	var player := E_Player.find() as E_Player
	if player == null:
		return
	_follow(player, delta)
	_aim_eyes(player)
	_show_first_person(player, false)
	_dress_up(player)
	# Экран станции со своей камерой облёта кадр забирает, а закрываясь, отдаёт камере игрока — забираем обратно.
	var current := get_viewport().get_camera_3d()
	if current == null or current == player.camera:
		camera.make_current()


## Точка под прицелом и смена плеча у стены: лучи — запросы к space-state, поэтому из физкадра (Jolt на отдельном потоке).
func _physics_process(_delta: float) -> void:
	var from := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * aim_range, 0xFFFFFFFF, _excluded)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	aim = hit["position"] if not hit.is_empty() else query.to
	if not auto_side or _reach <= 0.0:
		return
	var here := _free_reach(side)
	if here >= _reach * 0.5:
		return
	if _free_reach(-side) > here + 0.1:
		side = -side


## Лучи игры (интерактив, захват, удар) пока идут из камеры игрока в глазах формы. Наводим её в точку под прицелом:
## луч из глаз приходит туда, куда показывает прицел, а дальность считается от тела — схема двух лучей шага 4.
func _aim_eyes(player: E_Player) -> void:
	if aim == Vector3.INF:
		return
	var eye := player.camera.global_position
	var to_aim := aim - eye
	if to_aim.length() < 0.05 or absf(to_aim.normalized().y) > 0.999:
		return
	player.camera.look_at(aim, Vector3.UP)


func _free_reach(towards: float) -> float:
	var from := global_position
	var to := from + global_basis.x * towards * _reach
	var query := PhysicsRayQueryParameters3D.create(from, to, shoulder.collision_mask, _excluded)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return from.distance_to(hit["position"]) if not hit.is_empty() else _reach


func _follow(player: E_Player, delta: float) -> void:
	var rig := player as Node as Node3D
	var size := form_size(player)
	var look := player.get_component(C_FPSCamera) as C_FPSCamera
	var eyes := player.camera.position.y
	if look != null and look.eye_position != Vector3.INF:
		eyes = look.eye_position.y  # база глаз без качки S_FirstPersonMotion
	var origin := rig.get_global_transform_interpolated().origin
	var lift := maxf(eyes + pivot_lift * size.x, min_pivot - player.foot_offset().y)
	global_position = origin + Vector3.UP * lift
	# Рыскание — с самого рига, не с интерполированного: его пишет мышь в кадре отрисовки, а не физика.
	global_rotation = Vector3(look.pitch if look != null else 0.0, rig.global_rotation.y, 0.0)

	var mask := (player as Node as CollisionObject3D).collision_mask & GEOMETRY_MASK
	shoulder.collision_mask = mask
	arm.collision_mask = mask
	arm.spring_length = maxf(min_arm, size.x * arm_scale)
	_reach = shoulder_scale * (size.y + shoulder_pad)
	var wanted := side * _reach
	_offset = wanted if delta <= 0.0 else lerpf(_offset, wanted, 1.0 - exp(-side_speed * delta))
	shoulder.spring_length = absf(_offset)
	# Плечо вбок кастует по своей +Z: поворот на четверть оборота наводит её вправо или влево, заднее плечо
	# поворачивается обратно и кастует назад от опоры.
	var turn := PI * 0.5 if _offset >= 0.0 else -PI * 0.5
	shoulder.rotation.y = turn
	arm.rotation.y = -turn


## Наследие первого лица мешает виду снаружи: руки-муляж висят на камере игрока, клочья души — у неё же.
func _show_first_person(player: E_Player, shown: bool) -> void:
	var arms := player.camera.get_node_or_null(NodePath(O_BodyVisual.FP_ARMS_NODE)) as Node3D
	if arms != null:
		arms.visible = shown
	var cloud := player.get_component(C_SoulCloud) as C_SoulCloud
	if cloud == null:
		return
	# S_SoulCloud включает клочья только при смене «во плоти / вне тела», поэтому прятать их надо каждый кадр.
	var wisps := player.get_node_or_null(cloud.wisps_path) as Node3D
	if wisps != null:
		wisps.visible = shown and not player.has_component(C_Embodied)


## Надетый облик целиком: голова и руки из «только тенью» обратно в кадр, материалы — копиями с дизером.
func _dress_up(player: E_Player) -> void:
	var worn := player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE))
	if worn == _worn:
		return
	_dress_down()
	_worn = worn
	if worn == null:
		return
	var mode := FADE_MODES[own_fade]
	for node in worn.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var saved := {"shadow": geo.cast_shadow, "override": geo.material_override, "surfaces": []}
		if geo.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			geo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mode != BaseMaterial3D.DISTANCE_FADE_DISABLED:
			fade_geometry(geo, saved, mode, own_fade_min, own_fade_max)
		_restore[geo] = saved


## Выдаёт геометрии копии материалов с дизером; что было, пишет в [param saved].
static func fade_geometry(geo: GeometryInstance3D, saved: Dictionary, mode: int, near: float, far: float) -> void:
	if geo.material_override != null:
		geo.material_override = faded_copy(geo.material_override, mode, near, far)
		return
	# У CSG материал в своём свойстве, а не в поверхностях: копию кладём поверх, в material_override.
	var csg := geo as CSGPrimitive3D
	if csg != null and csg.get(&"material") is Material:
		geo.material_override = faded_copy(csg.get(&"material"), mode, near, far)
		return
	var mesh := geo as MeshInstance3D
	if mesh == null:
		return
	for i in mesh.get_surface_override_material_count():
		saved["surfaces"].append(mesh.get_surface_override_material(i))
		var active_material := mesh.get_active_material(i)
		if active_material != null:
			mesh.set_surface_override_material(i, faded_copy(active_material, mode, near, far))


## Вернуть геометрии то, что записал fade_geometry и _dress_up.
static func restore(geo: GeometryInstance3D, saved: Dictionary) -> void:
	geo.cast_shadow = saved["shadow"]
	geo.material_override = saved["override"]
	var mesh := geo as MeshInstance3D
	var surfaces: Array = saved["surfaces"]
	if mesh != null and not surfaces.is_empty():
		for i in surfaces.size():
			mesh.set_surface_override_material(i, surfaces[i])


func _dress_down() -> void:
	for geo: Variant in _restore:
		if is_instance_valid(geo):
			restore(geo as GeometryInstance3D, _restore[geo])
	_restore.clear()
	_worn = null
