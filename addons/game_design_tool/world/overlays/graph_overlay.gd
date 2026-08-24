## res://addons/game_design_tool/world/overlays/graph_overlay.gd
## Оверлей «Граф: узлы и рёбра» — тот же RS_LevelGraph и RS_LayerPlan, что и у
## геометрии комнат, поэтому узлы стоят ровно там же, где комнаты: переключение
## оверлеев не двигает камеру и не требует своей раскладки (см. §2
## [[world-generator-tool-spec]]).
##
## Узлы — SphereMesh, приподнятый над полом (иначе тонет в геометрии комнаты и
## его не видно поверх стен). Рёбра — один ImmediateMesh на весь слой: дешевле,
## чем нода на каждое ребро, и не плодит мусор при перестройке.
##
## Межслойные рёбра (vertical_hub на ДРУГУЮ глубину) не рисуются — у их цели
## нет позиции в текущем плане, рисовать в никуда нечем. Видно только то, что
## физически укладывается в этот слой.
@tool
extends Node3D

const NODE_RADIUS := 1.4
## Насколько приподнят маркер узла над полом — примерно середина высоты
## комнаты, чтобы не тонуть в полу и не протыкать потолок.
const NODE_HEIGHT := 3.0

const COLOR_DEFAULT := Color(0.55, 0.75, 0.95)
const COLOR_ENTRY := Color(1.0, 0.85, 0.35)
const COLOR_EXIT := Color(0.5, 0.95, 0.55)
const COLOR_SELECTED := Color(1.0, 1.0, 1.0)

const EDGE_COLOR_DOOR := Color(0.7, 0.7, 0.75, 0.9)
const EDGE_COLOR_CORRIDOR := Color(0.55, 0.65, 0.85, 0.9)
const EDGE_COLOR_VERTICAL := Color(0.8, 0.6, 0.95, 0.9)
## Замок перекрывает цвет по типу связи — это самый важный сигнал на ребре.
const EDGE_COLOR_LOCKED := Color(0.9, 0.45, 0.3, 0.95)

var _spheres: Dictionary[StringName, MeshInstance3D] = {}
## Цвет узла ДО выделения — чтобы set_selected мог вернуть прежний цвет, не
## пересчитывая роль узла (вход/выход/обычный) заново.
var _base_color: Dictionary[StringName, Color] = {}
var _edges: MeshInstance3D
var _selected_id: StringName = &""


func _init() -> void:
	_edges = MeshInstance3D.new()
	_edges.name = "Edges"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_edges.material_override = mat
	add_child(_edges)


func rebuild(graph: RS_LevelGraph, layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan) -> void:
	_clear_spheres()

	var on_layer: Dictionary[StringName, bool] = {}
	for node_data: RS_LevelNode in layer_nodes:
		on_layer[node_data.id] = true

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = NODE_RADIUS
	sphere_mesh.height = NODE_RADIUS * 2.0

	for node_data: RS_LevelNode in layer_nodes:
		var color := COLOR_DEFAULT
		if node_data.id == graph.entry_node_id:
			color = COLOR_ENTRY
		elif node_data.has_tag(&"level_exit"):
			color = COLOR_EXIT
		_base_color[node_data.id] = color

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = sphere_mesh
		mesh_instance.position = plan.positions.get(node_data.id, Vector3.ZERO) + Vector3(0, NODE_HEIGHT, 0)
		mesh_instance.material_override = _unshaded_material(color)
		add_child(mesh_instance)
		_spheres[node_data.id] = mesh_instance

	_rebuild_edges(layer_nodes, plan, on_layer)


func set_selected(node_id: StringName) -> void:
	if _selected_id != &"" and _spheres.has(_selected_id):
		_spheres[_selected_id].material_override = _unshaded_material(
			_base_color.get(_selected_id, COLOR_DEFAULT)
		)
	_selected_id = node_id
	if node_id != &"" and _spheres.has(node_id):
		_spheres[node_id].material_override = _unshaded_material(COLOR_SELECTED)


## free(), не queue_free() — та же причина, что у RoomsOverlay.clear(): смена
## слоя синхронная, отложенное удаление наложило бы старые сферы на новые.
func _clear_spheres() -> void:
	for sphere: MeshInstance3D in _spheres.values():
		sphere.free()
	_spheres.clear()
	_base_color.clear()
	_selected_id = &""


func _rebuild_edges(
	layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan, on_layer: Dictionary
) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var drawn: Dictionary[String, bool] = {}
	for node_data: RS_LevelNode in layer_nodes:
		var from: Vector3 = plan.positions.get(node_data.id, Vector3.ZERO) + Vector3(0, NODE_HEIGHT, 0)
		for conn: RS_LevelConnection in node_data.connections:
			if not on_layer.get(conn.target_node_id, false):
				continue  # ведёт на другую глубину — здесь рисовать нечем
			var pair_key := _pair_key(node_data.id, conn.target_node_id)
			if drawn.has(pair_key):
				continue  # ребро хранится на обоих концах — не дублируем линию
			drawn[pair_key] = true
			var to: Vector3 = plan.positions.get(conn.target_node_id, Vector3.ZERO) + Vector3(0, NODE_HEIGHT, 0)
			var color := _edge_color(conn)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(from)
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(to)
	mesh.surface_end()
	_edges.mesh = mesh


func _pair_key(a: StringName, b: StringName) -> String:
	var sa := String(a)
	var sb := String(b)
	return (sa + "|" + sb) if sa < sb else (sb + "|" + sa)


func _edge_color(conn: RS_LevelConnection) -> Color:
	if conn.is_locked():
		return EDGE_COLOR_LOCKED
	match conn.type:
		RS_LevelConnection.Type.ELEVATOR, RS_LevelConnection.Type.STAIRWELL:
			return EDGE_COLOR_VERTICAL
		RS_LevelConnection.Type.CORRIDOR:
			return EDGE_COLOR_CORRIDOR
		_:
			return EDGE_COLOR_DOOR


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
