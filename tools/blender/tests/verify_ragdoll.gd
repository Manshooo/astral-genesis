extends SceneTree
## Godot-половина проверки плагина: собрался ли рэгдолл из метаданных Blender.
##
## Метаданные сами по себе не делают ничего — их читает collision_post_import.gd
## на импорте. Эта проверка смотрит на результат: узлы, а не на extras.
##
## Запускается раннером (run_addon_tests.ps1) на временном проекте, куда
## Blender-половина только что экспортировала фикстуру.

var failures: Array = []


func check(condition: bool, label: String) -> void:
	print(("PASS  " if condition else "FAIL  ") + label)
	if not condition:
		failures.append(label)


func tree(node: Node, depth: int = 0) -> String:
	var text := "\n" + "  ".repeat(depth) + node.name + " [" + node.get_class() + "]"
	for child in node.get_children():
		text += tree(child, depth + 1)
	return text


func find_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := find_of_type(child, type_name)
		if found != null:
			return found
	return null


func _initialize() -> void:
	var packed: PackedScene = load("res://assets/Ragdoll/Ragdoll.glb")
	if packed == null:
		check(false, "Ragdoll.glb загрузился")
		_finish()
		return

	var root := packed.instantiate()
	get_root().add_child(root)
	print(tree(root))
	print("")

	var skeleton := find_of_type(root, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		check(false, "в фикстуре нет Skeleton3D — проверять нечего")
		_finish()
		return

	var simulator: PhysicalBoneSimulator3D = null
	for child in skeleton.get_children():
		if child is PhysicalBoneSimulator3D:
			simulator = child
	check(simulator != null, "PhysicalBoneSimulator3D — прямой ребёнок скелета")
	if simulator == null:
		_finish()
		return
	# Без него соседние тела сталкиваются и заклинивают суставы.
	var sim_script := simulator.get_script() as Script
	check(sim_script != null and sim_script.resource_path.ends_with("ragdoll_collision_exceptions.gd"),
		"на симуляторе скрипт исключений столкновений (%s)"
		% (sim_script.resource_path if sim_script else "нет"))

	var bone: PhysicalBone3D = null
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			bone = child
	check(bone != null, "PhysicalBone3D создан")
	if bone == null:
		_finish()
		return

	check(bone.name == "upper_arm", "узел назван по кости (%s)" % bone.name)
	check(bone.bone_name == "upper_arm", "bone_name проставлен (%s)" % bone.bone_name)
	check(bone.joint_type == PhysicalBone3D.JOINT_TYPE_CONE,
		"joint_type = Cone Twist (%d)" % bone.joint_type)
	check(absf(bone.mass - 3.5) < 0.01, "масса доехала (%s)" % bone.mass)
	check(bone.collision_layer == 4, "слой = бит 3 (%d)" % bone.collision_layer)
	check(skeleton.find_bone(bone.bone_name) >= 0,
		"скелет знает кость '%s' из bone_name" % bone.bone_name)

	var shape_node: CollisionShape3D = null
	for child in bone.get_children():
		if child is CollisionShape3D:
			shape_node = child
	check(shape_node != null, "CollisionShape3D под телом")
	if shape_node != null:
		check(shape_node.shape is CapsuleShape3D,
			"форма — CapsuleShape3D (%s)" % shape_node.shape.get_class())

	# При старте симуляции тело встаёт в позу кости × body_offset. Без смещения
	# форма уехала бы в начало кости, к суставу; со смещением — туда, где её
	# поставили в Blender.
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(bone.bone_name))
	check((rest * bone.body_offset).origin.distance_to(bone.transform.origin) < 0.01
		and bone.body_offset.origin.length() > 0.1,
		"body_offset возвращает тело на место формы (%v)" % bone.body_offset.origin)
	var joint_in_bone := bone.body_offset * bone.joint_offset
	check(joint_in_bone.origin.length() < 0.01,
		"сустав в начале кости (%v)" % joint_in_bone.origin)
	# Конус Jolt скручивает вокруг X сустава — он обязан смотреть вдоль кости.
	check(joint_in_bone.basis.x.distance_to(Vector3.UP) < 0.01,
		"ось скручивания конуса вдоль кости (%v)" % joint_in_bone.basis.x)
	check(absf(float(bone.get("joint_constraints/swing_span")) - 60.0) < 0.1
		and absf(float(bone.get("joint_constraints/twist_span")) - 20.0) < 0.1,
		"пределы конуса доехали (%s / %s)" % [bone.get("joint_constraints/swing_span"),
			bone.get("joint_constraints/twist_span")])

	var scale := bone.transform.basis.get_scale()
	check(absf(scale.x - 1.0) < 0.01 and absf(scale.y - 1.0) < 0.01
		and absf(scale.z - 1.0) < 0.01,
		"тело не отмасштабировано (%v)" % scale)

	# Прокси-меш обязан исчезнуть: он был болванкой под форму, а не геометрией.
	var strays := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).contains("arm_shape"):
			strays += 1
	check(strays == 0, "прокси-меш удалён (осталось %d)" % strays)

	_finish()


func _finish() -> void:
	print("")
	if failures.is_empty():
		print("=== ИТОГ: ВСЁ ЗЕЛЁНОЕ")
		quit(0)
	else:
		print("=== ИТОГ: ПРОВАЛОВ %d" % failures.size())
		for item in failures:
			print("  - " + str(item))
		quit(1)
