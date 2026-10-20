## res://addons/game_design_tool/world/viewport_host.gd
## 3D-превью вкладки «Генератор мира»: SubViewport, камера, оверлеи (по реестру) и
## пикинг. Граф и раскладку отдаёт вкладка через show_layer.
## Вики: [[Редакторские инструменты]] (Коридоры и сетка во вьюпорте).
@tool
extends SubViewportContainer

signal node_picked(node_id: StringName)
## Камера устаканилась (не каждый кадр драга) — стоит сохранить позицию.
signal camera_changed

const EditorCamera := preload("res://addons/game_design_tool/world/editor_camera.gd")
const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")

## Меньше — клик по узлу, больше — это уже был драг камеры, а не выбор.
const CLICK_DRAG_THRESHOLD := 6.0
## Высота пивота орбиты над полом выбранной комнаты, м.
const ORBIT_PIVOT_HEIGHT := 3.0
## Дистанция пивота перед камерой без выделения, м (не orbit_distance() камеры).
const DEFAULT_ORBIT_DISTANCE := 20.0

var _viewport: SubViewport
var _camera: EditorCamera
## id оверлея -> его узел, в порядке OverlayRegistry.OVERLAYS.
var _overlays: Dictionary[StringName, Node3D] = {}

var _view: LayerView = LayerView.new()
var _selected_id: StringName = &""

var _press_pos := Vector2.ZERO
var _left_pressed := false


func _init() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Без фокуса Control не получает InputEventKey в _gui_input — F не долетит.
	focus_mode = Control.FOCUS_ALL

	_viewport = SubViewport.new()
	# Свой мир: не пересекаться с 3D-редактором открытой сцены.
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

	for descriptor: Dictionary in OverlayRegistry.OVERLAYS:
		var overlay := (descriptor["script"] as GDScript).new() as Node3D
		overlay.name = String(descriptor["id"])
		_overlays[descriptor["id"]] = overlay
		_viewport.add_child(overlay)


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


## Отдаёт вьюпорту готовый слой; сам ничего не генерирует, только отображает.
func show_layer(view: LayerView) -> void:
	_view = view
	for overlay: Node3D in _overlays.values():
		overlay.rebuild(view)
	_select(&"")
	frame_layer()


## Оверлей по id из реестра — для проверок и отладки.
func overlay(overlay_id: StringName) -> Node3D:
	return _overlays.get(overlay_id)


func set_overlay_visible(overlay_id: StringName, is_visible: bool) -> void:
	var target := _overlays.get(overlay_id)
	if target:
		target.visible = is_visible


func selected_node_id() -> StringName:
	return _selected_id


## Выделение из кода — тем же путём, что клик (сигнал node_picked).
func select(node_id: StringName) -> void:
	_select(node_id)


func camera_position() -> Vector3:
	return _camera.position


func camera_rotation_degrees() -> Vector3:
	return _camera.rotation_degrees


## Ставит камеру в сохранённое положение; почему не просто position=, см. EditorCamera.restore_transform.
func restore_camera(pos: Vector3, rot_degrees: Vector3) -> void:
	_camera.restore_transform(pos, rot_degrees)


func focus_selected() -> void:
	if _selected_id == &"" or _view.plan == null:
		return
	_camera.focus_on(Picker.room_aabb(_selected_id, _view.nodes, _view.plan))
	camera_changed.emit()


## Кадрирует камеру на весь слой: при show_layer и по кнопке «Сбросить вид».
func frame_layer() -> void:
	if _view.is_empty():
		return
	var bounds := Picker.room_aabb(_view.nodes[0].id, _view.nodes, _view.plan)
	for i in range(1, _view.nodes.size()):
		bounds = bounds.merge(Picker.room_aabb(_view.nodes[i].id, _view.nodes, _view.plan))
	_camera.focus_on(bounds)
	camera_changed.emit()


## Отпускание кнопки вне окна (Alt+Tab посреди драга) или спрятанная вкладка до
## _gui_input не доходят — захват мыши нужно снять самим.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_FOCUS_EXIT, NOTIFICATION_EXIT_TREE:
			_release_camera()
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				_release_camera()


## Только если камера и правда держит мышь: иначе отнимем захват у чужого инструмента.
func _release_camera() -> void:
	if _camera == null or not _camera.is_moving():
		return
	_camera.set_flying(false)
	_camera.set_orbiting(false)


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
				# Клик, а не драг: дрожание зажатой мыши не должно пикать мимо.
				if mb.position.distance_to(_press_pos) <= CLICK_DRAG_THRESHOLD:
					_pick_at(mb.position)
		MOUSE_BUTTON_RIGHT:
			_camera.set_flying(mb.pressed)
			if not mb.pressed:
				camera_changed.emit()  # конец облёта, не каждый кадр драга
		MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_camera.begin_orbit(_orbit_pivot_hint())
			_camera.set_orbiting(mb.pressed)
			if not mb.pressed:
				camera_changed.emit()  # конец орбиты
		MOUSE_BUTTON_WHEEL_UP:
			if mb.pressed:
				_camera.dolly(1.0)  # вверх — навстречу взгляду, приближение
				camera_changed.emit()
		MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_camera.dolly(-1.0)  # вниз — от взгляда, отдаление
				camera_changed.emit()
		_:
			# Боковые кнопки не глотаем — они нужны редактору («назад/вперёд»).
			return
	accept_event()


func _handle_key(key: InputEventKey) -> void:
	if key.pressed and not key.echo and key.keycode == KEY_F:
		focus_selected()
		accept_event()


## Центр выделенной комнаты, иначе комната по центру экрана, иначе точка перед камерой.
func _orbit_pivot_hint() -> Vector3:
	if _selected_id != &"" and _view.plan and _view.plan.cells.has(_selected_id):
		return _view.plan.position_of(_selected_id) + Vector3(0, ORBIT_PIVOT_HEIGHT, 0)
	return _pivot_ahead_of_camera()


## Не orbit_distance(): она может остаться от автокадрирования слоя (сотни метров)
## и увести пивот за пределы видимого.
func _pivot_ahead_of_camera() -> Vector3:
	if not _view.is_empty():
		var origin := _camera.project_ray_origin(size / 2.0)
		var dir := _camera.project_ray_normal(size / 2.0)
		var hit_id := Picker.pick(origin, dir, _view.nodes, _view.plan)
		if hit_id != &"":
			return Picker.room_aabb(hit_id, _view.nodes, _view.plan).get_center()
	return _camera.position + (-_camera.transform.basis.z) * DEFAULT_ORBIT_DISTANCE


func _pick_at(local_pos: Vector2) -> void:
	if _view.plan == null:
		return
	var origin := _camera.project_ray_origin(local_pos)
	var dir := _camera.project_ray_normal(local_pos)
	_select(Picker.pick(origin, dir, _view.nodes, _view.plan))


func _select(node_id: StringName) -> void:
	_selected_id = node_id
	for target: Node3D in _overlays.values():
		target.set_selected(node_id)
	node_picked.emit(node_id)
