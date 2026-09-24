## res://addons/game_design_tool/world/viewport_host.gd
## SubViewportContainer с 3D-превью генератора: владеет SubViewport, камерой,
## оверлеями и пикингом. Сам не знает, ЧТО содержательно показывать (граф,
## слой) — граф и раскладку считает вкладка «Генератор мира» (world_gen.gd) и
## отдаёт их одним GDT_LayerView через show_layer; этот узел решает, КАК это
## отрисовать и как по нему кликнуть.
##
## Оверлеи не перечислены здесь поимённо: узел создаёт, пересобирает и
## переключает их циклом по GDT_OverlayRegistry.OVERLAYS. Раньше на каждый был
## свой var, свой вызов rebuild() со своей подписью и своя ветка match в
## set_overlay_visible — реестр обещал, что новый оверлей стоит одной строки
## данных, а на деле требовал ещё трёх правок здесь.
##
## Камера — не Control и GUI-события не получает; узел ловит их через
## _gui_input и передаёт камере руками, а не полагается на встроенную
## маршрутизацию ввода Godot (её для Camera3D и нет).
@tool
extends SubViewportContainer

signal node_picked(node_id: StringName)
## Камера сдвинулась/повернулась достаточно значимо, чтобы стоило сохранить
## позицию между сессиями (world_gen.gd слушает и пишет в EditorSettings).
## НЕ на каждый кадр драга — только на «устаканившиеся» моменты (отпустили
## кнопку, крутанули колесо, нажали F/«Сбросить вид»): постоянные записи в
## EditorSettings на каждый пиксель движения мыши были бы чистым расточительством.
signal camera_changed

const EditorCamera := preload("res://addons/game_design_tool/world/editor_camera.gd")
const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")

## Меньше — клик по узлу, больше — это уже был драг камеры, а не выбор.
const CLICK_DRAG_THRESHOLD := 6.0
## Высота, на которую приподнят пивот орбиты над полом выбранной комнаты —
## орбитировать вокруг пола неудобно, крутит камеру «подмышкой».
const ORBIT_PIVOT_HEIGHT := 3.0
## Пивот по умолчанию без выделения и без комнаты по центру экрана — фиксированная
## точка перед камерой, НЕ camera.orbit_distance(): та могла остаться от
## автокадрирования всего слоя (десятки-сотни метров) и после облёта ближе к
## делу уводила пивот далеко за пределы видимого — см. _pivot_ahead_of_camera.
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

	# Порядок в дереве — порядок реестра: оверлеи не перекрывают друг друга по
	# глубине, но предсказуемый порядок узлов упрощает отладку сцены вьюпорта.
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


## Отдаёт вьюпорту готовый слой: граф — для роли узла (вход/выход) и рёбер,
## узлы и раскладку — что и где рисовать, подписи пресетов — оверлею
## «Подписи». Всё считает вызывающий (RS_LevelGraph.generate_run +
## RS_LayerPlan.build); этот узел сам ничего не генерирует, только отображает.
func show_layer(view: LayerView) -> void:
	_view = view
	for overlay: Node3D in _overlays.values():
		overlay.rebuild(view)
	_select(&"")
	frame_layer()


## Оверлей по id из реестра — для проверок и отладки; вкладке он не нужен, она
## ходит через set_overlay_visible.
func overlay(overlay_id: StringName) -> Node3D:
	return _overlays.get(overlay_id)


func set_overlay_visible(overlay_id: StringName, is_visible: bool) -> void:
	var target := _overlays.get(overlay_id)
	if target:
		target.visible = is_visible


func selected_node_id() -> StringName:
	return _selected_id


func camera_position() -> Vector3:
	return _camera.position


func camera_rotation_degrees() -> Vector3:
	return _camera.rotation_degrees


## Ставит камеру в сохранённое между сессиями положение — см.
## EditorCamera.restore_transform про то, почему это не просто position=/
## rotation_degrees=.
func restore_camera(pos: Vector3, rot_degrees: Vector3) -> void:
	_camera.restore_transform(pos, rot_degrees)


func focus_selected() -> void:
	if _selected_id == &"" or _view.plan == null:
		return
	_camera.focus_on(Picker.room_aabb(_selected_id, _view.nodes, _view.plan))
	camera_changed.emit()


## Кадрирует камеру на весь текущий слой. Зовётся автоматически при
## show_layer() и вручную — кнопкой «Сбросить вид» на панели (world_gen.gd):
## после облёта камерой куда-нибудь далеко это самый предсказуемый способ
## вернуться к осмысленному виду, без побочных эффектов на СКМ (см.
## _orbit_pivot_hint — раньше сброс происходил неявно как эффект орбиты).
func frame_layer() -> void:
	if _view.is_empty():
		return
	var bounds := Picker.room_aabb(_view.nodes[0].id, _view.nodes, _view.plan)
	for i in range(1, _view.nodes.size()):
		bounds = bounds.merge(Picker.room_aabb(_view.nodes[i].id, _view.nodes, _view.plan))
	_camera.focus_on(bounds)
	camera_changed.emit()


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
			# Боковые кнопки мыши вьюпорту не нужны — и глотать их незачем:
			# accept_event() на них отнимал бы у редактора его собственные
			# «назад/вперёд», не давая взамен ничего.
			return
	accept_event()


func _handle_key(key: InputEventKey) -> void:
	if key.pressed and not key.echo and key.keycode == KEY_F:
		focus_selected()
		accept_event()


## Куда встаёт точка вращения при СКМ: центр выделенной комнаты, если она
## есть, иначе — комната по центру экрана (тот же пикинг, что и по клику, но
## без самого клика), иначе — фиксированная точка перед камерой.
func _orbit_pivot_hint() -> Vector3:
	if _selected_id != &"" and _view.plan and _view.plan.positions.has(_selected_id):
		return _view.plan.positions[_selected_id] + Vector3(0, ORBIT_PIVOT_HEIGHT, 0)
	return _pivot_ahead_of_camera()


## НЕ camera.orbit_distance(): та могла остаться от автокадрирования всего
## слоя (десятки-сотни метров, см. frame_layer). Если пивот без выделения
## считать через неё, облёт камерой ближе к делу и последующая орбита СКМ
## уводили пивот далеко за пределы видимого — выглядело так, будто камера
## «сбрасывается» и вращается из начала координат слоя.
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
