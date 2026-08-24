## res://addons/game_design_tool/world/viewport_host.gd
## SubViewportContainer с 3D-превью генератора: владеет SubViewport, камерой,
## оверлеями и пикингом. Сам не знает, ЧТО содержательно показывать (граф,
## слой) — граф и раскладку считает вкладка «Генератор мира» (world_gen.gd) и
## отдаёт их через show_layer; этот узел решает, КАК это отрисовать и как по
## нему кликнуть.
##
## Камера — не Control и GUI-события не получает; узел ловит их через
## _gui_input и передаёт камере руками, а не полагается на встроенную
## маршрутизацию ввода Godot (её для Camera3D и нет).
@tool
extends SubViewportContainer

signal node_picked(node_id: StringName)

const EditorCamera := preload("res://addons/game_design_tool/world/editor_camera.gd")
const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const RoomsOverlay := preload("res://addons/game_design_tool/world/overlays/rooms_overlay.gd")
const GraphOverlay := preload("res://addons/game_design_tool/world/overlays/graph_overlay.gd")

## Меньше — клик по узлу, больше — это уже был драг камеры, а не выбор.
const CLICK_DRAG_THRESHOLD := 6.0
## Высота, на которую приподнят пивот орбиты над полом выбранной комнаты —
## орбитировать вокруг пола неудобно, крутит камеру «подмышкой».
const ORBIT_PIVOT_HEIGHT := 3.0

var _viewport: SubViewport
var _camera: EditorCamera
var _rooms_overlay: RoomsOverlay
var _graph_overlay: GraphOverlay

var _layer_nodes: Array[RS_LevelNode] = []
var _plan: RS_LayerPlan
var _selected_id: StringName = &""

var _press_pos := Vector2.ZERO
var _left_pressed := false


func _init() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Без фокуса Control не получает InputEventKey в _gui_input вообще — F
	# (фокус на выделенном) иначе никогда не долетит. grab_focus() зовём сами
	# при любом клике мышью, см. _handle_mouse_button.
	focus_mode = Control.FOCUS_ALL

	_viewport = SubViewport.new()
	# own_world_3d — этот вьюпорт не должен пересекаться с 3D-миром, если у
	# пользователя параллельно открыта сцена в обычном 3D-редакторе.
	_viewport.own_world_3d = true
	add_child(_viewport)

	_viewport.add_child(_build_environment())
	_viewport.add_child(_build_sun())

	_camera = EditorCamera.new()
	_camera.position = Vector3(40, 45, 70)
	_camera.rotation_degrees = Vector3(-28.0, 30.0, 0.0)
	_camera.current = true
	_camera.far = 4000.0
	_viewport.add_child(_camera)

	_rooms_overlay = RoomsOverlay.new()
	_viewport.add_child(_rooms_overlay)

	_graph_overlay = GraphOverlay.new()
	_viewport.add_child(_graph_overlay)


func _build_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.6
	var node := WorldEnvironment.new()
	node.environment = env
	return node


func _build_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.1
	return sun


## Отдаёт вьюпорту готовую раскладку: graph — для роли узла (вход/выход) и
## рёбер, layer_nodes/plan — что и где рисовать. Граф и раскладку считает
## вызывающий (RS_LevelGraph.generate_run + RS_LayerPlan.build) — этот узел
## сам ничего не генерирует, только отображает.
func show_layer(graph: RS_LevelGraph, layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan) -> void:
	_layer_nodes = layer_nodes
	_plan = plan
	_rooms_overlay.rebuild(layer_nodes, plan)
	_graph_overlay.rebuild(graph, layer_nodes, plan)
	_select(&"")
	_frame_layer()


func set_overlay_visible(overlay_id: StringName, is_visible: bool) -> void:
	match overlay_id:
		&"rooms":
			_rooms_overlay.visible = is_visible
		&"graph":
			_graph_overlay.visible = is_visible


func selected_node_id() -> StringName:
	return _selected_id


func focus_selected() -> void:
	if _selected_id == &"" or _plan == null:
		return
	_camera.focus_on(Picker.room_aabb(_selected_id, _layer_nodes, _plan))


func _frame_layer() -> void:
	if _layer_nodes.is_empty() or _plan == null:
		return
	var bounds := Picker.room_aabb(_layer_nodes[0].id, _layer_nodes, _plan)
	for i in range(1, _layer_nodes.size()):
		bounds = bounds.merge(Picker.room_aabb(_layer_nodes[i].id, _layer_nodes, _plan))
	_camera.focus_on(bounds)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
		return
	if event is InputEventMouseMotion:
		_camera.handle_mouse_motion(event as InputEventMouseMotion)
		return
	if event is InputEventKey:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	grab_focus()
	match mb.button_index:
		MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_press_pos = mb.position
				_left_pressed = true
			elif _left_pressed:
				_left_pressed = false
				# Клик, а не драг камерой (тот идёт по ПКМ/СКМ и сюда не попадает,
				# но зажатый ЛКМ + случайное дрожание мыши не должен пикать мимо).
				if mb.position.distance_to(_press_pos) <= CLICK_DRAG_THRESHOLD:
					_pick_at(mb.position)
		MOUSE_BUTTON_RIGHT:
			_camera.set_flying(mb.pressed)
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_camera.begin_orbit(_orbit_pivot_hint())
			_camera.set_orbiting(mb.pressed)
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_camera.dolly(1.0)  # вверх — навстречу взгляду, приближение
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_camera.dolly(-1.0)  # вниз — от взгляда, отдаление
	accept_event()


func _handle_key(key: InputEventKey) -> void:
	if key.pressed and not key.echo and key.keycode == KEY_F:
		focus_selected()
		accept_event()


## Куда встаёт точка вращения при СКМ: центр выделенной комнаты, если она
## есть, иначе — точка перед камерой на её текущей орбитальной дистанции (так
## первый же орбит-драг без выделения не улетает в никуда).
func _orbit_pivot_hint() -> Vector3:
	if _selected_id != &"" and _plan and _plan.positions.has(_selected_id):
		return _plan.positions[_selected_id] + Vector3(0, ORBIT_PIVOT_HEIGHT, 0)
	return _camera.position + (-_camera.transform.basis.z) * _camera.orbit_distance()


func _pick_at(local_pos: Vector2) -> void:
	if _plan == null:
		return
	var origin := _camera.project_ray_origin(local_pos)
	var dir := _camera.project_ray_normal(local_pos)
	_select(Picker.pick(origin, dir, _layer_nodes, _plan))


func _select(node_id: StringName) -> void:
	_selected_id = node_id
	_graph_overlay.set_selected(node_id)
	node_picked.emit(node_id)
