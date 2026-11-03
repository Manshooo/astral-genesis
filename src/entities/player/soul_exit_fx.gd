# res://src/entities/player/soul_exit_fx.gd
# Выход души из тела: брошенное тело теряет управление и из позы, в которой его бросили, валится рэгдоллом по
# инерции, потом сгорает: частицы стягиваются к душе, из места выхода бьёт клуб дыма. Узел убирает себя сам.
# Ставит O_SoulExit. Вики: [[Захват тела]].
class_name SoulExitFx
extends Node3D

## Сколько тело падает, прежде чем начать испаряться.
@export var fall_seconds := 0.35
@export var evaporate_seconds := 1.4
## Сколько живёт эффект после того, как тело исчезло: частицы долетают до души.
@export var linger_seconds := 2.2
## Откуда бьёт клуб дыма — над подошвой, на уровне груди.
@export var burst_height := 1.0
## Чем тело сгорает: отсечение по шуму с тлеющей кромкой. Цвет каждой поверхности берётся у её родного материала.
@export var burn_material: ShaderMaterial
## Толчок верха тела вперёд при выходе стоя, м/с: без него тело из позы покоя стояло бы истуканом и оседало на месте.
@export var stand_push := 0.8

var _soul: Node3D
var _husk: Node3D
var _bones: Array[PhysicalBone3D] = []
var _geometry: Array[GeometryInstance3D] = []
var _velocity := Vector3.ZERO
var _kicked := false
var _burning := false
var _time := 0.0
var _forward := Vector3.FORWARD

@onready var _burst := %Burst as GPUParticles3D
@onready var _vapor := %Vapor as GPUParticles3D
# Аттрактор тянет только слой soul_exit (cull_mask в сцене): без маски к душе летели бы все частицы рядом.
@onready var _attractor := %Attractor as GPUParticlesAttractorSphere3D


## Тело ставится подошвой в placement — туда, где стоял риг; velocity — скорость рига в момент выхода; pose —
## поза костей надетого тела в этот миг (имя кости → локальная поза), пустая — тело стартует из своей позы покоя.
func start(body_scene: PackedScene, placement: Transform3D, velocity: Vector3, soul: Node3D, pose: Dictionary = {}) -> void:
	global_transform = placement
	_soul = soul
	_velocity = velocity
	_forward = -placement.basis.z
	_husk = body_scene.instantiate() as Node3D
	# Ни луч захвата, ни игрок оболочку не задевают: она декорация, а не тело — поглощённое не захватить снова.
	# Маска остаётся — кости падают на пол. До add_child: рэгдолл стартует в _ready.
	for node in [_husk] + _husk.find_children("*", "CollisionObject3D", true, false):
		if node is CollisionObject3D:
			(node as CollisionObject3D).collision_layer = 0
	_apply_pose(pose)
	add_child(_husk)
	for node in _husk.find_children("*", "PhysicalBone3D", true, false):
		_bones.append(node as PhysicalBone3D)
	for node in _husk.find_children("*", "GeometryInstance3D", true, false):
		_geometry.append(node as GeometryInstance3D)
	_fit_vapor()
	_burst.global_position = placement.origin + placement.basis.y * burst_height
	_burst.restart()


func _physics_process(_delta: float) -> void:
	# Скорость костям — со второго физкадра после старта рэгдолла: в первом он только встаёт в позу и перезаписал бы её.
	if _kicked or _bones.is_empty() or _time <= 0.0:
		return
	_kicked = true
	_topple()


## Тело теряет управление: скорость костям растёт с высотой — верх уходит дальше ног, и тело заваливается, а не
## скользит истуканом. Выход стоя добавляет верху толчок вперёд, иначе тело из позы покоя оседало бы на месте.
func _topple() -> void:
	var low := INF
	var high := -INF
	for bone in _bones:
		low = minf(low, bone.global_position.y)
		high = maxf(high, bone.global_position.y)
	var push := _forward * stand_push * (1.0 - clampf(_velocity.length() / 2.0, 0.0, 1.0))
	for bone in _bones:
		var up := clampf((bone.global_position.y - low) / maxf(high - low, 0.01), 0.0, 1.0)
		bone.linear_velocity = _velocity * lerpf(0.35, 1.3, up) + push * up


## Поза брошенного тела — та, в которой его застал выход: ставится скелету ДО add_child, потому что рэгдолл стартует
## в _ready тела и берёт позу скелета в этот миг. Кости сверяются по имени — скелеты одной сцены совпадают.
func _apply_pose(pose: Dictionary) -> void:
	if pose.is_empty():
		return
	for node in _husk.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for bone_name: String in pose:
			var bone := skeleton.find_bone(bone_name)
			if bone < 0:
				continue
			var local: Transform3D = pose[bone_name]
			skeleton.set_bone_pose_position(bone, local.origin)
			skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
			skeleton.set_bone_pose_scale(bone, local.basis.get_scale())


func _process(delta: float) -> void:
	_time += delta
	if is_instance_valid(_soul):
		# В объектив, а не в центр души: дым тела втекает игроку в глаза и гаснет у самой камеры (near_fade).
		var rig: Node = _soul
		var eye: Camera3D = (rig as E_Player).camera if rig is E_Player else null
		_attractor.global_position = eye.global_position if eye != null else _soul.global_position
	var t := _time
	var k := clampf((t - fall_seconds) / evaporate_seconds, 0.0, 1.0)
	if is_instance_valid(_husk):
		_vapor.global_position = _husk_center()
		_vapor.emitting = t >= fall_seconds and k < 1.0
		if t >= fall_seconds and not _burning:
			_ignite()
		if _burning:
			for g in _geometry:
				g.set_instance_shader_parameter(&"burn", k)
		if k >= 1.0:
			_husk.queue_free()
			_husk = null
	if t >= fall_seconds + evaporate_seconds + linger_seconds:
		queue_free()


## Тело переодевается в материал сгорания с его же цветом: альбедо, текстура и сдвиг UV палитры родного
## материала. Без материала сгорания — просто тает прозрачностью.
func _ignite() -> void:
	_burning = true
	for g in _geometry:
		var mesh_instance := g as MeshInstance3D
		if burn_material == null or mesh_instance == null or mesh_instance.mesh == null:
			g.transparency = 1.0
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var burn := burn_material.duplicate() as ShaderMaterial
			var own := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if own != null:
				burn.set_shader_parameter(&"albedo_color", own.albedo_color)
				burn.set_shader_parameter(&"albedo_tex", own.albedo_texture)
				burn.set_shader_parameter(&"uv_scale", Vector2(own.uv1_scale.x, own.uv1_scale.y))
				burn.set_shader_parameter(&"uv_offset", Vector2(own.uv1_offset.x, own.uv1_offset.y))
			mesh_instance.set_surface_override_material(surface, burn)
		# material_override сильнее поверхностных — снять, иначе тело так и осталось бы в родном.
		mesh_instance.material_override = null


## Пока тело падает, середина — по костям; у тела без рэгдолла — по его коробке.
func _husk_center() -> Vector3:
	if _bones.is_empty():
		return _husk.global_position + _husk.global_basis.y * burst_height
	var sum := Vector3.ZERO
	for bone in _bones:
		sum += bone.global_position
	return sum / _bones.size()


## Облако испарения — по габариту тела: у ползуна ниже и шире, чем у ходока. Материал копируется: он общий у всех выходов.
func _fit_vapor() -> void:
	var box := AABB()
	for g in _geometry:
		var local := RS_EntityVisuals.transform_relative_to(g, _husk) * g.get_aabb()
		box = local if box.size == Vector3.ZERO else box.merge(local)
	var process := (_vapor.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	process.emission_box_extents = (box.size * 0.4).max(Vector3(0.15, 0.15, 0.15))
	_vapor.process_material = process
