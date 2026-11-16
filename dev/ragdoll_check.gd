extends "res://dev/check_harness.gd"
## Проверка мышц рэгдолла трупа (C_Ragdoll + S_Ragdoll, RS_RagdollProfile).
##
## Проверяет ПОВЕДЕНИЕ: тело, лежащее с начала, стартует рэгдоллом из нейтральной
## позы (колени согнуты), а не из позы покоя; колено при падении не выгибается
## назад; свежий труп подхватывается рэгдоллом посреди клипа гибели и продолжает
## падение со скоростью клипа; удар, уронивший тело, бросает руки по удару, а
## ноги навстречу; через active_seconds мышцы гаснут и больше не тратят кадр.
## Ломается это тихо — тело просто снова валится мешком.
## Запускать: godot --headless dev/ragdoll_check.tscn

const SCIENTIST_BODY := "res://src/entities/body/e_body_scientist.tscn"
const HOUND_BODY := "res://src/entities/body/e_body_hound.tscn"
const STATIC_LAYER := 1 << 0
const KNEES: Array[StringName] = [&"LeftLowerLeg", &"RightLowerLeg"]
## Насколько колено может уйти против сгиба: жёсткий предел Jolt — 0, чуть сверху прощаем на проникание.
const KNEE_SLACK := deg_to_rad(6.0)

var _world: World


func _ready() -> void:
	_world = _new_world()
	_add_systems(_world, "physics", [S_Ragdoll.new()])
	_add_floor()
	await _check_lying(SCIENTIST_BODY, Vector3(-4.0, 0.0, 0.0))
	await _check_lying(HOUND_BODY, Vector3(4.0, 0.0, 0.0))
	await _check_dying()
	_finish()


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = STATIC_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)


func _spawn(path: String, at: Vector3, dying: bool) -> E_Body:
	var body := (load(path) as PackedScene).instantiate() as E_Body
	body.dying = dying
	body.position = at
	add_child(body)
	_world.add_entity(body)
	return body


## Ждёт, пока S_Ragdoll подхватит рэгдолл тела; false — так и не подхватил.
func _await_start(ragdoll: C_Ragdoll, frames: int) -> bool:
	for _i in frames:
		if ragdoll.elapsed >= 0.0:
			return true
		await _physics(1)
	return ragdoll.elapsed >= 0.0


func _knees(ragdoll: C_Ragdoll) -> Array:
	return ragdoll.joints.filter(func(j: S_Ragdoll.Joint) -> bool: return KNEES.has(j.child.bone_name))


# --- 1. Тело с начала: нейтральная поза, колено не выгибается, мышцы гаснут -----
func _check_lying(path: String, at: Vector3) -> void:
	var body := _spawn(path, at, false)
	var name := path.get_file().get_basename()
	var ragdoll := body.get_component(C_Ragdoll) as C_Ragdoll
	_check("%s: у тела есть мышцы рэгдолла" % name, ragdoll != null and ragdoll.profile != null, "")
	if ragdoll == null:
		return
	var started := await _await_start(ragdoll, 5)
	_check("%s: S_Ragdoll подхватил рэгдолл тела" % name, started and not ragdoll.joints.is_empty(), "")
	var knees := _knees(ragdoll)
	_check("%s: у рэгдолла два колена-шарнира" % name, knees.size() == 2, str(knees.size()))
	if knees.size() != 2:
		return
	var start_bend: float = knees.map(func(j: S_Ragdoll.Joint) -> float: return j.bend()).min()
	# Нейтральная поза — колени согнуты; поза покоя (T-поза) дала бы ноль.
	_check("%s: рэгдолл стартует из нейтральной позы (колени согнуты)" % name, start_bend > deg_to_rad(25.0),
		"%.0f°" % rad_to_deg(start_bend))

	var lowest := INF
	var profile := ragdoll.profile
	var frames := int((profile.active_seconds + 0.5) * Engine.physics_ticks_per_second)
	for _i in frames:
		await _physics(1)
		if ragdoll.done:
			break
		for knee: S_Ragdoll.Joint in knees:
			lowest = minf(lowest, knee.bend())
	_check("%s: колено при падении не выгибается назад" % name, lowest > -KNEE_SLACK, "%.1f°" % rad_to_deg(lowest))
	_check("%s: через active_seconds мышцы гаснут" % name, ragdoll.done and ragdoll.joints.is_empty(),
		"elapsed %.2f" % ragdoll.elapsed)
	_world.remove_entity(body)


# --- 2. Свежий труп: подхват посреди клипа, скорость клипа, разлёт от удара ------
func _check_dying() -> void:
	var push := Vector3(1.0, 0.0, 0.0)
	var body := _spawn(SCIENTIST_BODY, Vector3(0.0, 0.0, 6.0), true)
	var ragdoll := body.get_component(C_Ragdoll) as C_Ragdoll
	if ragdoll == null:
		_check("свежий труп: у тела есть мышцы рэгдолла", false, "")
		return
	ragdoll.struck_from = push
	var clip := 0.0
	var tree := RS_EntityVisuals.animation_tree(body)
	for key in tree.get_animation_library_list():
		if tree.get_animation_library(key).has_animation(S_BodyAnimation.DEATH):
			clip = tree.get_animation_library(key).get_animation(S_BodyAnimation.DEATH).length
	var born := Time.get_ticks_msec()
	_check("свежий труп: пока идёт клип, рэгдолла нет", ragdoll.elapsed < 0.0, "")
	var started := await _await_start(ragdoll, int(clip * 2.0 * Engine.physics_ticks_per_second))
	var waited := (Time.get_ticks_msec() - born) / 1000.0
	_check("свежий труп: рэгдолл подхватывает тело посреди клипа гибели, а не после",
		started and waited < clip * 0.9, "через %.2f с при клипе %.2f с" % [waited, clip])
	_check("свежий труп: из клипа унесена скорость костей", not ragdoll.launch.is_empty()
		and ragdoll.launch.values().any(func(v: Vector3) -> bool: return v.length() > 0.2), str(ragdoll.launch.size()))

	while not ragdoll.kicked:
		await _physics(1)
	var arms_ok := true
	var legs_ok := true
	var detail := ""
	for joint: S_Ragdoll.Joint in ragdoll.joints:
		var bone := joint.child
		var away := push if ragdoll.profile.hit_back_bones.has(bone.bone_name) else -push \
			if ragdoll.profile.hit_forward_bones.has(bone.bone_name) else Vector3.ZERO
		if away == Vector3.ZERO:
			continue
		# Вращение вокруг along × away уводит конец кости в сторону away.
		var spin := bone.angular_velocity.dot(bone.global_basis.y.cross(away).normalized())
		detail += "%s %.1f " % [bone.bone_name, spin]
		if spin <= 0.0:
			if away == push:
				arms_ok = false
			else:
				legs_ok = false
	_check("удар бросает руки трупа по удару", arms_ok, detail)
	_check("удар бросает ноги трупа навстречу ударившему", legs_ok, detail)
	_world.remove_entity(body)
