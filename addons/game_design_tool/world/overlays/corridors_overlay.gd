## res://addons/game_design_tool/world/overlays/corridors_overlay.gd
## Оверлей «Коридоры»: трассы веток по клеткам кита, как их разложил
## RS_CorridorPlanner, — плита в центре тайла и «рукав» к каждому открытому
## проёму, цвет на ветку. Так трасса видна раньше, чем появится сборка тайлов
## в игре (этап 4 карточки коридоров), и видна ровно та, что построит игра: план
## тот же, что у RunManager.
##
## Схема рядом с настоящими кусками кита (их ставит «Геометрия»): кусок
## выбирается по маске проёмов, а маску здесь и показываем — ошибка раскладки
## (проём в стену, лишний стык) видна по рукавам, тогда как настоящий меш её
## только замаскировал бы.
@tool
extends Node3D

const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
## Цвет выделенной ветки — тот же, что у обводки выделенной комнаты
## (selection_outline.tres): одна разметка инструмента на все оверлеи.
const SELECTED_COLOR := Color("#cfc61b")
## Ширина плиты — сечение коридора в ките (6 м внутри), толщина — чтобы не
## тонуть в полу комнат и не мерцать с ним.
const SLAB_WIDTH := 6.0
const SLAB_HEIGHT := 0.25
const SLAB_LIFT := 0.3

## ветка -> её меши; нужно, чтобы перекрасить выделенную целиком.
var _meshes_by_branch: Dictionary[StringName, Array] = {}
var _materials: Dictionary[StringName, StandardMaterial3D] = {}
var _selected_material := _flat_material(SELECTED_COLOR)
var _selected_id: StringName = &""


func rebuild(view: LayerView) -> void:
	clear()
	if view.plan == null or view.plan.corridor_tiles.is_empty():
		return
	var half := RS_LayerPlan.CELL_SIZE * 0.5
	for cell: Vector3i in view.plan.corridor_tiles:
		var branch: StringName = view.plan.node_by_cell.get(cell, &"")
		var center := view.plan.cell_position(Vector2i(cell.x, cell.z), cell.y) + Vector3(0.0, SLAB_LIFT, 0.0)
		var material := _material_for(branch)
		_add_slab(branch, center, Vector3(SLAB_WIDTH, SLAB_HEIGHT, SLAB_WIDTH), material)
		var mask: int = view.plan.corridor_tiles[cell]
		for side: StringName in RS_LayerPlan.SIDE_BITS:
			if mask & RS_LayerPlan.SIDE_BITS[side] == 0:
				continue
			var offset: Vector2i = RS_RoomLayout.OFFSETS[side]
			var dir := Vector3(offset.x, 0.0, offset.y)
			var length := half - SLAB_WIDTH * 0.5
			var arm_center := center + dir * (SLAB_WIDTH * 0.5 + length * 0.5)
			var size := Vector3(
				length if offset.x != 0 else SLAB_WIDTH, SLAB_HEIGHT, length if offset.y != 0 else SLAB_WIDTH
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


## Сколько веток нарисовано — для проверки инструмента.
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


## Цвет ветки — от её id, а не от порядка: одна и та же ветка на пересборке
## того же сида остаётся того же цвета, и глаз её не теряет.
func _material_for(branch: StringName) -> StandardMaterial3D:
	if not _materials.has(branch):
		var hue := float(hash(String(branch)) % 360) / 360.0
		_materials[branch] = _flat_material(Color.from_hsv(hue, 0.55, 0.85))
	return _materials[branch]


static func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
