extends SceneTree
## Позы мёртвых учёных сцены меню, два режима. Запекание: клип облика → рэгдолл оседает на пол → кости пишутся
## в Skeleton3D учёного в L_menu_map.tscn; кому какую позу — метка menu_action, учёного с меткой не из POSES
## (поставленного руками) не трогает. Досимуляция (--settle Узел): поза, выставленная руками в редакторе, отпускается
## рэгдоллом в настоящей комнате меню и оседает — в редакторе физика не идёт. Вики: [[Меню — спека]] §8.
## Запускать при сохранённой и потом перезагруженной в редакторе сцене:
##   godot --headless --path . -s dev/bake_menu_scientist_poses.gd
##   godot --headless --path . -s dev/bake_menu_scientist_poses.gd -- --settle ScientistSlumped [--time 0.3]

const VISUAL := "res://assets/characters/SK_scientist/SK_scientist.tscn"
const CLIPS := "res://assets/characters/_rigs/humanoid/ANIM_humanoid.glb"
const MENU := "res://src/levels/menu_map/L_menu_map.tscn"
const SKELETON_PATH := "scientist_skel/Skeleton3D"
const ACTION_META := &"menu_action"

## Поза → клип старта и время в нём (-1 — конец); topple — куда валит тело в пространстве облика (+Z — вперёд).
## Сама по себе физика решает по-своему: рэгдолл из конца death так и остаётся на коленях, а толчок из стойки
## кладёт то на спину, то ничком. Наклонять облик нельзя — кости рэгдолла стартуют под полом и проваливаются.
const POSES := {
	&"pose_back": {clip = &"idle", at = 0.0, topple = Vector3(0.0, 0.0, -1.0)},
	&"pose_face_down": {clip = &"death", at = -1.0, topple = Vector3(0.0, 0.0, 1.0)},
}
## Первые полсекунды гравитация наклонена в сторону падения: тело валится туда, а ноги держит трение пола.
const TOPPLE_TIME := 0.5
const TOPPLE_TILT := 0.7
const SETTLE_MAX := 8.0
const SETTLE_SPEED := 0.03
## Халат ведут CoatDrive и пружины облика — его кости не пишутся, иначе привод ляжет дважды.
const SKIP_BONES := "Coat"

var _captured := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var settle := args.find("--settle")
	var error: Error
	var time := args.find("--time")
	if settle >= 0 and settle + 1 < args.size():
		error = await _settle(args[settle + 1], float(args[time + 1]) if time >= 0 and time + 1 < args.size() else INF)
	else:
		error = await _bake_all()
	print("сцена ", MENU, " — ", error_string(error))
	quit(0 if error == OK else 1)


# --- Запекание ---------------------------------------------------------------

func _bake_all() -> Error:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 0xFFFFFFFF
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	shape.position.y = -0.5
	floor_body.add_child(shape)
	root.add_child(floor_body)

	var poses := {}
	for pose: StringName in POSES:
		poses[pose] = await _bake(pose)
	var menu: Node = (load(MENU) as PackedScene).instantiate()
	var by_node := {}
	for node in menu.get_node("Lab").get_children():
		var pose := StringName(node.get_meta(ACTION_META, &""))
		if poses.has(pose):
			by_node[String(node.name)] = poses[pose]
			print("  ", node.name, " ← ", pose)
	menu.free()
	return _patch_menu(by_node)


## Поза → {имя кости: локальный Transform3D}.
func _bake(pose: StringName) -> Dictionary:
	var setup: Dictionary = POSES[pose]
	var visual: Node3D = load(VISUAL).instantiate()
	root.add_child(visual)
	var skeleton := visual.get_node(SKELETON_PATH) as Skeleton3D
	for spring in visual.find_children("*", "SpringBoneSimulator3D", true, false):
		(spring as SpringBoneSimulator3D).active = false

	var player := AnimationPlayer.new()
	visual.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library(&"", load(CLIPS))
	var clip := player.get_animation(setup.clip)
	player.play(setup.clip)
	player.seek(clip.length if setup.at < 0.0 else setup.at, true)
	player.pause()
	await physics_frame
	await physics_frame
	player.active = false

	var simulator := _simulator(visual)
	var space := visual.get_world_3d().space
	var topple: Vector3 = visual.global_basis * Vector3(setup.topple)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR,
			(Vector3.DOWN + topple * TOPPLE_TILT).normalized())
	simulator.physical_bones_start_simulation()
	await _wait_settled(simulator, space)
	print(pose, " осел")

	await _capture(skeleton, simulator)
	var skeleton_in_visual := visual.global_transform.affine_inverse() * skeleton.global_transform
	var result := _to_pose(skeleton, simulator, skeleton_in_visual)
	visual.queue_free()
	await process_frame
	return result


## Root ставится так, что таз над началом узла, а голова смотрит к −Z — как стояли заглушки.
func _to_pose(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D, skeleton_in_visual: Transform3D) -> Dictionary:
	var hips: Vector3 = _captured[skeleton.find_bone("Hips")][1].origin
	var head: Vector3 = _captured[skeleton.find_bone("Head")][1].origin
	var to_head := Vector2(head.x - hips.x, head.z - hips.z)
	# Повернуть (x, z) к (0, −1) вокруг Y.
	var yaw := to_head.angle_to(Vector2(0.0, -1.0))
	var on_floor := Transform3D(Basis(Vector3.UP, -yaw), Vector3.ZERO) * Transform3D(Basis.IDENTITY, Vector3(-hips.x, 0.0, -hips.z))
	var recenter: Transform3D = skeleton_in_visual.affine_inverse() * on_floor * _captured[-1]
	return _local_pose(skeleton, simulator, recenter)


# --- Досимуляция позы из редактора -------------------------------------------

## Учёный стартует из своей позы в сцене, рэгдолл оседает в комнате меню (её пол и стены — коллизия модели).
## [param seconds] — отпустить ненадолго: до конца сидящий складывается грудью на колени, а за доли секунды
## только провисают руки и голова.
func _settle(node_name: String, seconds: float) -> Error:
	var menu: Node3D = (load(MENU) as PackedScene).instantiate()
	root.add_child(menu)
	var scientist := menu.get_node_or_null("Lab/" + node_name)
	if scientist == null:
		push_error("в сцене нет узла Lab/%s" % node_name)
		return ERR_DOES_NOT_EXIST
	var skeleton := scientist.get_node("Visual/" + SKELETON_PATH) as Skeleton3D
	await physics_frame
	await physics_frame
	var simulator := _simulator(scientist)
	simulator.physical_bones_start_simulation()
	if is_inf(seconds):
		await _wait_settled(simulator, menu.get_world_3d().space)
	else:
		await create_timer(seconds, true, true).timeout
	await _capture(skeleton, simulator)
	var hips: Vector3 = _captured[skeleton.find_bone("Hips")][1].origin
	print("%s осел, таз на %s (узел %s)" % [node_name, hips, (scientist as Node3D).global_position])
	if hips.y < -0.5:
		push_error("таз ушёл под пол — у комнаты нет коллизии на маске костей, запись отменена")
		return ERR_INVALID_DATA
	var pose := _local_pose(skeleton, simulator, Transform3D.IDENTITY)
	menu.queue_free()
	await process_frame
	return _patch_menu({node_name: pose})


# --- Общее -------------------------------------------------------------------

static func _simulator(owner_node: Node) -> PhysicalBoneSimulator3D:
	return owner_node.find_children("*", "PhysicalBoneSimulator3D", true, false)[0] as PhysicalBoneSimulator3D


## Ждёт, пока кости успокоятся; наклон гравитации снимается через TOPPLE_TIME.
func _wait_settled(simulator: PhysicalBoneSimulator3D, space: RID) -> void:
	var bones: Array[PhysicalBone3D] = []
	bones.assign(simulator.find_children("*", "PhysicalBone3D", false, false))
	var elapsed := 0.0
	while elapsed < SETTLE_MAX:
		await physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second
		if elapsed >= TOPPLE_TIME:
			PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
		if elapsed > 1.0 and bones.all(func(b: PhysicalBone3D) -> bool: return b.linear_velocity.length() < SETTLE_SPEED):
			return
	push_warning("кости не успокоились за %.0f с — пишется как есть" % SETTLE_MAX)


## Финальная поза видна только сразу после модификатора: позже Skeleton3D возвращает кости к позе до него.
func _capture(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D) -> void:
	_captured.clear()
	simulator.modification_processed.connect(func() -> void:
		_captured[-1] = skeleton.global_transform
		for bone in skeleton.get_bone_count():
			_captured[bone] = [skeleton.get_bone_pose(bone), skeleton.global_transform * skeleton.get_bone_global_pose(bone)]
	, CONNECT_ONE_SHOT)
	await process_frame
	await process_frame


## {имя кости: локальный Transform3D} без халата; корень скелета умножается на [param root_fix].
## Смещение берётся только у корня и верхних костей рэгдолла (таз), остальным — длина кости из покоя:
## суставы Jolt мягкие, растянутая шея иначе застыла бы зазором и голова «отвалилась» бы.
func _local_pose(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D, root_fix: Transform3D) -> Dictionary:
	var simulated := {}
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			simulated[(child as PhysicalBone3D).get_bone_id()] = true
	var result := {}
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		if bone_name.contains(SKIP_BONES):
			continue
		var local: Transform3D = _captured[bone][0]
		if skeleton.get_bone_parent(bone) < 0:
			local = root_fix * local
		elif not (simulated.has(bone) and not _has_simulated_ancestor(skeleton, bone, simulated)):
			local.origin = skeleton.get_bone_rest(bone).origin
		result[bone_name] = local
	return result


static func _has_simulated_ancestor(skeleton: Skeleton3D, bone: int, simulated: Dictionary) -> bool:
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		if simulated.has(parent):
			return true
		parent = skeleton.get_bone_parent(parent)
	return false


## Кости встают в .tscn текстом — в блок переопределения Skeleton3D учёного, как пишет редактор; прочие строки
## блока (масштаб, свойства) остаются. Не PackedScene.pack(): из headless он теряет uid сцены и ресурсов и
## переписывает то, что редактор сохранил сам.
func _patch_menu(by_node: Dictionary) -> Error:
	var visual := (load(VISUAL) as PackedScene).instantiate()
	var skeleton := visual.get_node(SKELETON_PATH) as Skeleton3D
	var file := FileAccess.open(MENU, FileAccess.READ)
	if file == null:
		visual.free()
		return FileAccess.get_open_error()
	var lines := file.get_as_text().split("\n")
	file.close()

	var bone_line := RegEx.create_from_string("^bones/\\d+/(position|rotation) = ")
	for node_name: String in by_node:
		var prefix := "[node name=\"Skeleton3D\" parent=\"Lab/%s/Visual/scientist_skel\"" % node_name
		var header := _find_header(lines, prefix)
		if header < 0:
			header = _block_end(lines, _find_header(lines, "[node name=\"%s\" parent=\"Lab\"" % node_name))
			lines.insert(header, prefix + "]")
			lines.insert(header + 1, "")
		var i := header + 1
		while i < lines.size() and not lines[i].begins_with("["):
			if bone_line.search(lines[i]):
				lines.remove_at(i)
			else:
				i += 1
		var bones: Dictionary = by_node[node_name]
		var at := header + 1
		for bone_name: String in bones:
			var bone := skeleton.find_bone(bone_name)
			var local: Transform3D = bones[bone_name]
			lines.insert(at, "bones/%d/position = %s" % [bone, var_to_str(local.origin)])
			lines.insert(at + 1, "bones/%d/rotation = %s" % [bone, var_to_str(local.basis.get_rotation_quaternion())])
			at += 2
	visual.free()

	file = FileAccess.open(MENU, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("\n".join(lines))
	file.close()
	return OK


static func _find_header(lines: PackedStringArray, prefix: String) -> int:
	for i in lines.size():
		if lines[i].begins_with(prefix):
			return i
	return -1


## Индекс строки сразу за блоком, начатым строкой [param start], — следующий заголовок или конец файла.
static func _block_end(lines: PackedStringArray, start: int) -> int:
	var i := start + 1
	while i < lines.size() and not lines[i].begins_with("["):
		i += 1
	return i
