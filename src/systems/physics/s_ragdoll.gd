# res://src/systems/physics/s_ragdoll.gd
# Группа "physics": мышцы рэгдолла трупа (C_Ragdoll). Jolt не умеет мягких пределов суставов (softness/damping
# пределов он игнорирует с предупреждением), поэтому сустав ведёт момент отсюда: торможение у предела, слабая тяга
# к нейтральной позе и демпфирование, а удар, уронивший тело, разбрасывает руки и ноги. Работает несколько секунд
# после старта рэгдолла — дальше тело лежит и засыпает. Вики: [[Захват тела]].
class_name S_Ragdoll
extends System


func query() -> QueryBuilder:
	return q.with_all([C_Ragdoll])


## Структурных правок нет — только поля компонента и импульсы костям.
func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var ragdoll := entity.get_component(C_Ragdoll) as C_Ragdoll
		if ragdoll.done or ragdoll.profile == null:
			continue
		if ragdoll.elapsed < 0.0:
			_try_start(entity, ragdoll)
			continue
		ragdoll.elapsed += delta
		if not ragdoll.kicked:
			# Со второго физкадра: в первом кости только встают в позу скелета и перезаписали бы скорость.
			ragdoll.kicked = true
			launch(ragdoll)
		var profile := ragdoll.profile
		var gain := 1.0 - clampf((ragdoll.elapsed - (profile.active_seconds - profile.fade_seconds))
			/ maxf(profile.fade_seconds, 0.001), 0.0, 1.0)
		if gain <= 0.0:
			ragdoll.done = true
			ragdoll.joints = []
			continue
		for joint: Joint in ragdoll.joints:
			joint.drive(profile, gain, delta)


## Рэгдолл стартует не здесь (e_body_rigged: сразу или посреди клипа гибели) — система ждёт, когда кости поплывут.
func _try_start(entity: Entity, ragdoll: C_Ragdoll) -> void:
	if ragdoll.simulator == null:
		var found := (entity as Node).find_children("*", "PhysicalBoneSimulator3D", true, false)
		if found.is_empty():
			ragdoll.done = true
			return
		ragdoll.simulator = found[0] as PhysicalBoneSimulator3D
	var bones := ragdoll.simulator.find_children("*", "PhysicalBone3D", false, false)
	if bones.is_empty() or not (bones[0] as PhysicalBone3D).is_simulating_physics():
		return
	ragdoll.joints = build_joints(ragdoll.simulator, ragdoll.profile)
	ragdoll.elapsed = 0.0


## Суставы рэгдолла: у каждой кости с телом — ближайший предок с телом (между ними бывают кости без тел, Spine → Chest).
static func build_joints(simulator: PhysicalBoneSimulator3D, profile: RS_RagdollProfile) -> Array:
	var skeleton := simulator.get_parent() as Skeleton3D
	var by_bone := {}
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			by_bone[skeleton.find_bone((child as PhysicalBone3D).bone_name)] = child
	var out: Array = []
	for bone: int in by_bone:
		var chain: Array[int] = [bone]
		var parent := skeleton.get_bone_parent(bone)
		while parent >= 0 and not by_bone.has(parent):
			chain.push_front(parent)
			parent = skeleton.get_bone_parent(parent)
		if parent < 0:
			continue
		out.append(Joint.new(skeleton, by_bone[bone], by_bone[parent], chain, profile))
	return out


## Первый толчок рэгдоллу: скорость костей из клипа гибели (падение продолжается, а не начинается с места) и удар,
## уронивший тело, — руки уходят по удару, ноги навстречу, с разбросом величины и оси, чтобы не зеркально.
static func launch(ragdoll: C_Ragdoll) -> void:
	# По детям симулятора, а не по суставам: у корня (таза) сустава нет, а скорость нужна и ему.
	for node in ragdoll.simulator.get_children():
		var bone := node as PhysicalBone3D
		if bone != null and ragdoll.launch.has(bone.bone_name):
			bone.linear_velocity = ragdoll.launch[bone.bone_name]
	var push := Vector3(ragdoll.struck_from.x, 0.0, ragdoll.struck_from.z).normalized()
	if push == Vector3.ZERO:
		return
	var profile := ragdoll.profile
	for joint: Joint in ragdoll.joints:
		var bone: String = joint.child.bone_name
		var toward := push if profile.hit_back_bones.has(bone) else -push if profile.hit_forward_bones.has(bone) else Vector3.ZERO
		if toward == Vector3.ZERO:
			continue
		# Вращение вокруг along × toward уводит конец кости в сторону toward.
		var axis := joint.child.global_basis.y.cross(toward)
		if axis.length() < 0.1:
			continue  # кость уже смотрит по удару — вращать некуда
		var wobble := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		if wobble != Vector3.ZERO:
			axis = axis.normalized().rotated(wobble.normalized(), deg_to_rad(randf_range(-1.0, 1.0) * profile.hit_axis_jitter_degrees))
		var spin := profile.hit_spin * (1.0 + randf_range(-profile.hit_spin_jitter, profile.hit_spin_jitter))
		joint.child.angular_velocity += axis.normalized() * spin


## Сустав между костью и её родителем по телам. Всё считается в осях кости ребёнка (X — ось сгиба, Y — вдоль кости),
## от позы покоя: в ней рэгдолл строит свои суставы (PhysicalBone3D на входе в дерево).
class Joint:
	extends RefCounted

	var child: PhysicalBone3D
	var parent: PhysicalBone3D
	## Тело → кость: базис тела, умноженный на это, — базис кости.
	var _child_to_bone: Basis
	var _parent_to_bone: Basis
	## Кость родителя → кость ребёнка в покое и в нейтральной позе (через кости без тел между ними).
	var _chain_rest: Basis
	var _chain_target: Basis
	var _pulled: bool
	var _hinge: bool
	var _cone: bool
	## Пределы, рад: шарнир — сгиб вокруг X кости (знак как в Blender); конус — отклонение от Y и кручение вокруг Y.
	var _lower := 0.0
	var _upper := 0.0
	var _swing := 0.0
	var _twist := 0.0
	## Приведённый момент инерции пары: одинаковый момент даёт суставу одно и то же ускорение при любом весе костей.
	var _inertia := 0.0

	func _init(skeleton: Skeleton3D, child_body: PhysicalBone3D, parent_body: PhysicalBone3D, chain: Array[int],
			profile: RS_RagdollProfile) -> void:
		child = child_body
		parent = parent_body
		_child_to_bone = child.body_offset.basis.orthonormalized().inverse()
		_parent_to_bone = parent.body_offset.basis.orthonormalized().inverse()
		_chain_rest = Basis.IDENTITY
		_chain_target = Basis.IDENTITY
		for bone in chain:
			var rest := skeleton.get_bone_rest(bone).basis.orthonormalized()
			_chain_rest = _chain_rest * rest
			_chain_target = _chain_target * rest * profile.neutral_of(skeleton.get_bone_name(bone))
		_pulled = chain.any(func(bone: int) -> bool: return profile.neutral_pose.has(skeleton.get_bone_name(bone)))
		_hinge = child.joint_type == PhysicalBone3D.JOINT_TYPE_HINGE \
			and bool(child.get("joint_constraints/angular_limit_enabled"))
		_cone = child.joint_type == PhysicalBone3D.JOINT_TYPE_CONE
		if _hinge:
			# Угол шарнира Jolt растёт против сгиба кости (collision_post_import.gd) — пределы обратно в знак Blender.
			_lower = -deg_to_rad(float(child.get("joint_constraints/angular_limit_upper")))
			_upper = -deg_to_rad(float(child.get("joint_constraints/angular_limit_lower")))
		elif _cone:
			_swing = deg_to_rad(float(child.get("joint_constraints/swing_span")))
			_twist = deg_to_rad(float(child.get("joint_constraints/twist_span")))
		var own := _inertia_of(child)
		var other := _inertia_of(parent)
		_inertia = own * other / (own + other)

	func drive(profile: RS_RagdollProfile, gain: float, delta: float) -> void:
		var frame := parent.global_basis * _parent_to_bone
		var bone := child.global_basis * _child_to_bone
		var spin := child.angular_velocity - parent.angular_velocity
		var accel := -spin * profile.pose_damping * gain
		if _pulled:
			var error := ((frame * _chain_target) * bone.inverse()).get_rotation_quaternion()
			accel += _rotation_vector(error) * profile.pose_stiffness * gain
		accel += _soft_limits(frame * _chain_rest, bone, spin, profile) * gain
		if accel == Vector3.ZERO:
			return
		var impulse := accel * _inertia * delta
		PhysicsServer3D.body_apply_torque_impulse(child.get_rid(), impulse)
		PhysicsServer3D.body_apply_torque_impulse(parent.get_rid(), -impulse)

	## Сгиб шарнира от покоя, рад, знак как в Blender (у колена и локтя сгиб положительный); у не-шарнира 0.
	func bend() -> float:
		if not _hinge:
			return 0.0
		var rest := parent.global_basis * _parent_to_bone * _chain_rest
		return _bend_of(rest.inverse() * child.global_basis * _child_to_bone)

	static func _bend_of(local: Basis) -> float:
		return atan2(local.y.z, local.y.y)

	## Отклонение кости от покоя в её же осях и ответ зон у пределов.
	func _soft_limits(rest: Basis, bone: Basis, spin: Vector3, profile: RS_RagdollProfile) -> Vector3:
		var local := rest.inverse() * bone
		var zone := deg_to_rad(profile.soft_zone_degrees)
		var accel := Vector3.ZERO
		if _hinge:
			var bend := _bend_of(local)
			var axis := bone.x
			var half := minf(zone, (_upper - _lower) * 0.5)
			accel += _cushion(bend, _upper, half, axis, spin, profile)
			accel += _cushion(-bend, -_lower, half, -axis, spin, profile)
		elif _cone:
			var swing := acos(clampf(local.y.y, -1.0, 1.0))
			var tilt := Vector3.UP.cross(local.y)
			if tilt.length() > 0.0001:
				accel += _cushion(swing, _swing, minf(zone, _swing * 0.5), rest * tilt.normalized(), spin, profile)
			var turn := local.get_rotation_quaternion()
			if turn.w < 0.0:
				turn = -turn
			var twist := 2.0 * atan2(turn.y, turn.w)
			var half := minf(zone, _twist * 0.5)
			accel += _cushion(twist, _twist, half, bone.y, spin, profile)
			accel += _cushion(-twist, _twist, half, -bone.y, spin, profile)
		return accel

	## Один предел: [param angle] растёт вращением вокруг [param axis] и упирается в [param limit]. В зоне шириной
	## [param zone] у предела — возврат, растущий к пределу, и торможение движения к нему.
	static func _cushion(angle: float, limit: float, zone: float, axis: Vector3, spin: Vector3,
			profile: RS_RagdollProfile) -> Vector3:
		if zone <= 0.0 or angle <= limit - zone:
			return Vector3.ZERO
		var depth := minf((angle - (limit - zone)) / zone, 1.5)
		var toward := spin.dot(axis)
		var accel := -axis * profile.soft_stiffness * depth
		if toward > 0.0:
			accel -= axis * profile.soft_damping * depth * toward
		return accel

	static func _rotation_vector(turn: Quaternion) -> Vector3:
		if turn.w < 0.0:
			turn = -turn
		var angle := 2.0 * acos(clampf(turn.w, -1.0, 1.0))
		var s := sqrt(maxf(1.0 - turn.w * turn.w, 0.0))
		if s < 0.0001:
			return Vector3.ZERO
		return Vector3(turn.x, turn.y, turn.z) / s * angle

	## Стержень от сустава до центра тела и столько же за ним: m·(2L)²/3.
	static func _inertia_of(body: PhysicalBone3D) -> float:
		var lever := maxf(body.body_offset.origin.length(), 0.05)
		return body.mass * lever * lever * 4.0 / 3.0
