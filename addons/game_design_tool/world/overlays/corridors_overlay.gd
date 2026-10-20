## res://addons/game_design_tool/world/overlays/corridors_overlay.gd
## Оверлей «Коридоры»: трассы веток по клеткам плана RS_CorridorPlanner — плита в
## центре тайла и «рукав» к каждому открытому проёму, цвет на ветку.
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
@tool
extends Node3D

const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
## Как у обводки в selection_outline.tres.
const SELECTED_COLOR := Color("#cfc61b")
## Ширина — сечение коридора в ките; высота и подъём — чтобы плита не мерцала с полом.
const SLAB_WIDTH := 6.0
const SLAB_HEIGHT := 0.25
const SLAB_LIFT := 0.3

## ветка -> её меши.
var _meshes_by_branch: Dictionary[StringName, Array] = {}
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var _selected_material := _flat_material(SELECTED_COLOR)
var _selected_id: StringName = &""


func rebuild(view: LayerView) -> void:
	clear()
	if view.plan == null or view.plan.corridor_tiles.is_empty():
		return
	var plan := view.plan
	for cell: Vector3i in plan.corridor_tiles:
		var branch: StringName = plan.node_by_cell.get(cell, &"")
		var origin := plan.embedding.cell_origin(cell)
		var center := origin + Vector3(0.0, SLAB_LIFT, 0.0)
		var material := _material_for(branch)
		_add_slab(branch, center, Vector3(SLAB_WIDTH, SLAB_HEIGHT, SLAB_WIDTH), material)
		var mask: int = plan.corridor_tiles[cell]
		for side in plan.topology.side_count(cell):
			if mask & (1 << side) == 0:
				continue
			# Длина рукава из вложения, а не из размера клетки в коде.
			var to_face := (plan.embedding.cell_origin(plan.topology.neighbour(cell, side)) - origin) * 0.5
			var dir := to_face.normalized()
			var length := to_face.length() - SLAB_WIDTH * 0.5
			var arm_center := center + dir * (SLAB_WIDTH * 0.5 + length * 0.5)
			var size := Vector3(
				length if absf(dir.x) > 0.5 else SLAB_WIDTH, SLAB_HEIGHT, length if absf(dir.z) > 0.5 else SLAB_WIDTH
			)
			_add_slab(branch, arm_center, size, material)
	set_selected(_selected_id)


func set_selected(node_id: StringName) -> void:
	if _selected_id != &"" and _meshes_by_branch.has(_selected_id):
		for mesh: MeshInstance3D in _meshes_by_branch[_selected_id]:
			mesh.material_override = _materials[_selected_id]
	_selected_id = node_id
	if node_id != &"" and _meshes_by_branch.has(node_id):
		for mesh: MeshInstance3D in _meshes_by_branch[node_id]:
			mesh.material_override = _selected_material


## Для проверки инструмента.
func branch_count() -> int:
	return _meshes_by_branch.size()


## free(), не queue_free(): пересборка синхронная, см. RoomsOverlay.clear.
func clear() -> void:
	for child in get_children():
		child.free()
	_meshes_by_branch.clear()
	_materials.clear()


func _add_slab(branch: StringName, center: Vector3, size: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = center
	add_child(mesh)
	if not _meshes_by_branch.has(branch):
		_meshes_by_branch[branch] = []
	_meshes_by_branch[branch].append(mesh)


## Цвет ветки от id; золотое сечение, а не остаток — иначе соседние имена
## дают один оттенок. Общий с «Сеткой».
static func branch_color(branch: StringName) -> Color:
	return Color.from_hsv(fposmod(hash(String(branch)) * 0.6180339887, 1.0), 0.55, 0.85)


func _material_for(branch: StringName) -> StandardMaterial3D:
	if not _materials.has(branch):
		_materials[branch] = _flat_material(branch_color(branch))
	return _materials[branch]


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
