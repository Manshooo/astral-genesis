# res://src/levels/menu_map/stubs/menu_scientist_stub.gd
## Заглушка мёртвого учёного до модели с позами: фигура из капсул в коде (три позы узлами — три набора трансформов,
## которые выбросят целиком). Поза — из метки menu_action (l_menu_map.gd). @tool: видна в редакторе, части в файл не пишутся.
@tool
extends Node3D

const ACTION_META := &"menu_action"
const DEFAULT_POSE := &"pose_back"

## Поза → [часть, позиция, поворот в градусах]; голова к −Z, фигура на полу.
const POSES := {
	&"pose_back": [
		[&"torso", Vector3(0, 0.17, 0), Vector3(90, 0, 0)],
		[&"head", Vector3(0.02, 0.11, -0.5), Vector3.ZERO],
		[&"leg", Vector3(0.11, 0.08, 0.72), Vector3(90, 0, -4)],
		[&"leg", Vector3(-0.13, 0.08, 0.7), Vector3(90, 0, 10)],
		[&"arm", Vector3(0.27, 0.06, -0.05), Vector3(90, 0, 0)],
		[&"arm", Vector3(-0.48, 0.06, -0.3), Vector3(90, 0, 70)],
	],
	&"pose_side": [
		[&"torso", Vector3(0, 0.2, 0), Vector3(90, 0, 15)],
		[&"head", Vector3(0.06, 0.13, -0.5), Vector3.ZERO],
		[&"leg", Vector3(0.28, 0.1, 0.48), Vector3(90, -50, 0)],
		[&"leg", Vector3(0.2, 0.22, 0.56), Vector3(90, -40, 0)],
		[&"arm", Vector3(0.3, 0.08, -0.3), Vector3(90, -60, 0)],
		[&"arm", Vector3(0.22, 0.25, -0.18), Vector3(90, -30, 0)],
	],
	&"pose_face_down": [
		[&"torso", Vector3(0, 0.16, 0), Vector3(90, 0, 0)],
		[&"head", Vector3(-0.03, 0.11, -0.49), Vector3.ZERO],
		[&"leg", Vector3(0.12, 0.08, 0.72), Vector3(90, 0, -8)],
		[&"leg", Vector3(-0.12, 0.08, 0.74), Vector3(90, 0, 6)],
		[&"arm", Vector3(0.22, 0.06, -0.78), Vector3(90, 0, -8)],
		[&"arm", Vector3(-0.3, 0.06, -0.62), Vector3(90, 0, 25)],
	],
}

static var _parts: Dictionary = {}


func _ready() -> void:
	var pose: StringName = StringName(get_meta(ACTION_META, DEFAULT_POSE))
	for part: Array in POSES.get(pose, POSES[DEFAULT_POSE]):
		var mesh := MeshInstance3D.new()
		mesh.mesh = _part_mesh(part[0])
		mesh.position = part[1]
		mesh.rotation_degrees = part[2]
		add_child(mesh)


static func _part_mesh(part: StringName) -> Mesh:
	if _parts.has(part):
		return _parts[part]
	var coat := _material(Color(0.68, 0.68, 0.66))
	var mesh: PrimitiveMesh
	match part:
		&"torso":
			mesh = CapsuleMesh.new()
			mesh.radius = 0.17
			mesh.height = 0.72
			mesh.material = coat
		&"head":
			mesh = SphereMesh.new()
			mesh.radius = 0.11
			mesh.height = 0.22
			mesh.material = _material(Color(0.5, 0.43, 0.39))
		&"leg":
			mesh = CapsuleMesh.new()
			mesh.radius = 0.07
			mesh.height = 0.86
			mesh.material = _material(Color(0.11, 0.11, 0.13))
		_:
			mesh = CapsuleMesh.new()
			mesh.radius = 0.05
			mesh.height = 0.6
			mesh.material = coat
	_parts[part] = mesh
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
