extends "res://dev/check_harness.gd"
## Сцены облика персонажей (assets/characters/*/CH_*.tscn) держат контракт рига
## ([[Пайплайн персонажей]]). Запуск: godot --headless dev/character_check.tscn
##
## Сцена облика наследует .glb, и всё, что на ней настроено, висит внутри
## импортированной ветки: модификаторы скелета ссылаются на кости по имени, а
## переопределения — на узлы базы по пути. Переименование кости или объекта в
## Blender не роняет ничего: модификатор молча ничего не двигает, а
## переопределение узла, которого в базе больше нет, просто отбрасывается при
## загрузке. Поэтому по каждой сцене облика сверяется:
## - кости Root и Head есть (Root — origin, Head — взгляд головы);
## - каждое свойство *bone_name узлов под скелетом называет существующую кость —
##   так ловятся и IK, и CopyTransform, и LookAt, и физические кости, без списка
##   классов, который отставал бы от новых модификаторов;
## - каждый узел, записанный в .tscn, нашёлся в собранной сцене;
## - у каждой поверхности внешний материал MAT_* — встроенный перезаписывается
##   на каждом реимпорте (Blender-Godot пайплайн §8).
##
## Пока персонажей нет, детектор доказывается синтетикой: чистый облик проходит,
## каждая мутация валит свою сверку.

const CHARACTERS_DIR := "res://assets/characters"
## Кости, без которых облик не работает: имена — из SkeletonProfileHumanoid,
## эталоны типов рига лежат в tools/blender/godot_pipeline/rigs/.
const REQUIRED_BONES: Array[StringName] = [&"Root", &"Head"]
const MATERIALS_DIR := "res://assets/materials"
## Синтетическая пара «база + унаследованная сцена». Не сейв игрока: папка
## заводится и удаляется прогоном.
const SCRATCH_DIR := "user://character_check"


func _ready() -> void:
	_check_real_scenes()
	_check_synthetic()
	_check_lost_base_node()
	_finish()


# --- сверка ------------------------------------------------------------------


## Нарушения контракта в собранной сцене облика. state — состояние самой сцены
## облика (её .tscn), а не базы: именно в нём записаны переопределения.
func _inspect(root: Node, state: SceneState) -> PackedStringArray:
	var problems := PackedStringArray()
	if state != null:
		for i in state.get_node_count():
			var path := state.get_node_path(i)
			if root.get_node_or_null(path) == null:
				problems.append("узла %s нет в собранной сцене — база переименована?" % path)

	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		problems.append("нет Skeleton3D")
	for skeleton: Skeleton3D in skeletons:
		for bone in REQUIRED_BONES:
			if skeleton.find_bone(bone) < 0:
				problems.append("у скелета %s нет кости %s" % [root.get_path_to(skeleton), bone])
		for node in skeleton.find_children("*", "", true, false):
			for property in node.get_property_list():
				var key: String = property.name
				if not key.ends_with("bone_name"):
					continue
				if property.type != TYPE_STRING and property.type != TYPE_STRING_NAME:
					continue
				var bone := String(node.get(key))
				if not bone.is_empty() and skeleton.find_bone(bone) < 0:
					problems.append("%s.%s = «%s»: такой кости нет"
							% [root.get_path_to(node), key, bone])

	for mesh_instance: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			var where := "%s, поверхность %d" % [root.get_path_to(mesh_instance), surface]
			if material == null:
				problems.append("%s: материала нет" % where)
			elif material.resource_path.is_empty() or material.resource_path.contains("::"):
				problems.append("%s: материал встроенный, реимпорт его перезапишет" % where)
			elif not material.resource_path.get_file().begins_with("MAT_"):
				problems.append("%s: материал %s не MAT_*" % [where, material.resource_path])
	return problems


# --- 1. настоящие сцены облика -----------------------------------------------


func _check_real_scenes() -> void:
	var scenes := _character_scenes()
	if scenes.is_empty():
		# Не ассерт: «сверять нечего» не может упасть. Персонажи появятся в
		# сессии B2 — до тех пор детектор держат синтетические сверки ниже.
		print("  сцен облика в %s пока нет" % CHARACTERS_DIR)
		return
	var problems := PackedStringArray()
	for path in scenes:
		var packed := load(path) as PackedScene
		if packed == null:
			problems.append("%s: не загрузилась" % path)
			continue
		var root := packed.instantiate()
		for problem in _inspect(root, packed.get_state()):
			problems.append("%s: %s" % [path.get_file(), problem])
		root.free()
	_check("сцены облика (%d) держат контракт рига" % scenes.size(), problems.is_empty(),
			"; ".join(problems.slice(0, 6)))


func _character_scenes() -> PackedStringArray:
	var found := PackedStringArray()
	if not DirAccess.dir_exists_absolute(CHARACTERS_DIR):
		return found
	for folder in DirAccess.get_directories_at(CHARACTERS_DIR):
		var dir := CHARACTERS_DIR.path_join(folder)
		for file in DirAccess.get_files_at(dir):
			if file.begins_with("CH_") and file.get_extension() == "tscn":
				found.append(dir.path_join(file))
	return found


# --- 2. синтетика: детектор ловит то, ради чего писан ------------------------


func _check_synthetic() -> void:
	var material := _project_material()
	_check("в проекте есть внешний MAT_* для синтетики", material != null, MATERIALS_DIR)
	if material == null:
		return

	var root := _synthetic_outfit(material)
	var problems := _inspect(root, null)
	_check("облик по контракту претензий не вызывает", problems.is_empty(), "; ".join(problems))

	var look_at := root.get_node("Skeleton3D/LookAt") as LookAtModifier3D
	look_at.bone_name = "NoSuchBone"
	_check("модификатор на несуществующую кость ловится",
			_mentions(_inspect(root, null), "NoSuchBone"))
	look_at.bone_name = "Head"

	# Настройки IK — массив свойств settings/N/..., а не поле класса: сверка по
	# имени свойства обязана находить и их.
	var ik := root.get_node("Skeleton3D/LegIK") as TwoBoneIK3D
	ik.set("settings/0/end_bone_name", "foot.001.l")
	_check("кость в настройках IK ловится", _mentions(_inspect(root, null), "foot.001.l"))
	ik.set("settings/0/end_bone_name", "LeftFoot")

	var skeleton := root.get_node("Skeleton3D") as Skeleton3D
	skeleton.set_bone_name(skeleton.find_bone("Head"), "head")
	look_at.bone_name = "head"
	_check("облик без кости Head ловится", _mentions(_inspect(root, null), "нет кости Head"))
	skeleton.set_bone_name(skeleton.find_bone("head"), "Head")
	look_at.bone_name = "Head"

	var body := root.get_node("Skeleton3D/Body") as MeshInstance3D
	body.set_surface_override_material(0, StandardMaterial3D.new())
	_check("встроенный материал ловится", _mentions(_inspect(root, null), "встроенный"))
	body.set_surface_override_material(0, null)

	_check("после мутаций облик снова чист", _inspect(root, null).is_empty())
	root.free()


## Облик в памяти: скелет с костями контракта, модификаторы на них и меш с
## внешним материалом.
func _synthetic_outfit(material: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "CH_synthetic"
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	root.add_child(skeleton)
	for bone in ["Root", "Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Head"]:
		var index := skeleton.add_bone(bone)
		if index > 0:
			skeleton.set_bone_parent(index, 0 if bone in ["Hips", "Head"] else index - 1)

	var look_at := LookAtModifier3D.new()
	look_at.name = "LookAt"
	look_at.bone_name = "Head"
	skeleton.add_child(look_at)

	var ik := TwoBoneIK3D.new()
	ik.name = "LegIK"
	ik.set("setting_count", 1)
	ik.set("settings/0/root_bone_name", "LeftUpperLeg")
	ik.set("settings/0/middle_bone_name", "LeftLowerLeg")
	ik.set("settings/0/end_bone_name", "LeftFoot")
	skeleton.add_child(ik)

	var body := MeshInstance3D.new()
	body.name = "Body"
	var mesh := BoxMesh.new()
	mesh.material = material
	body.mesh = mesh
	skeleton.add_child(body)
	return root


func _project_material() -> Material:
	for file in DirAccess.get_files_at(MATERIALS_DIR):
		if file.begins_with("MAT_") and file.get_extension() == "tres":
			return load(MATERIALS_DIR.path_join(file)) as Material
	return null


func _mentions(problems: PackedStringArray, text: String) -> bool:
	for problem in problems:
		if problem.contains(text):
			return true
	return false


# --- 3. потеря переопределения унаследованной сцены --------------------------


## Настоящая пара файлов: переименование узла в базе — ровно то, что делает
## переименование объекта в Blender с .glb под сценой облика. В памяти этого не
## воспроизвести: переопределение живёт в SceneState загруженного .tscn.
func _check_lost_base_node() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var base_path := SCRATCH_DIR.path_join("base.tscn")
	var outfit_path := SCRATCH_DIR.path_join("CH_outfit.tscn")
	var outfit_text := "\n".join([
		"[gd_scene format=3]",
		"",
		"[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_base\"]" % base_path,
		"",
		"[node name=\"CH_outfit\" instance=ExtResource(\"1_base\")]",
		"",
		"[node name=\"Skeleton3D\" parent=\".\"]",
		"show_rest_only = true",
		"",
		"[node name=\"LookAt\" type=\"LookAtModifier3D\" parent=\"Skeleton3D\"]",
		"bone_name = \"Head\"",
		"",
	])
	_write(outfit_path, outfit_text)

	_save_base(base_path, "Skeleton3D")
	var intact := _inspect_file(outfit_path)
	_check("унаследованная сцена с целой базой претензий не вызывает", intact.is_empty(),
			"; ".join(intact))

	_save_base(base_path, "Armature")
	var lost := _inspect_file(outfit_path)
	_check("узел базы, переименованный в Blender, ловится",
			_mentions(lost, "Skeleton3D") and _mentions(lost, "LookAt"), "; ".join(lost))

	for file in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(SCRATCH_DIR.path_join(file))
	DirAccess.remove_absolute(SCRATCH_DIR)


## База — то, что в жизни приходит из .glb: корень и скелет с костями контракта.
func _save_base(path: String, skeleton_name: String) -> void:
	var root := Node3D.new()
	root.name = "CH_outfit"
	var skeleton := Skeleton3D.new()
	skeleton.name = skeleton_name
	skeleton.add_bone("Root")
	skeleton.add_bone("Head")
	root.add_child(skeleton)
	skeleton.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, path)
	root.free()


func _inspect_file(path: String) -> PackedStringArray:
	var packed := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if packed == null:
		return PackedStringArray(["%s не загрузилась" % path])
	var root := packed.instantiate()
	if root == null:
		return PackedStringArray(["%s не собралась" % path])
	var problems := _inspect(root, packed.get_state())
	root.free()
	return problems


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
