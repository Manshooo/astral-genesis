## res://addons/game_design_tool/world/editor_camera.gd
## Фри-камера редакторского вьюпорта генератора: облёт по ПКМ (WASD, пока
## зажата) и орбита по СКМ вокруг точки, которую передаёт хозяин (обычно —
## выделенный узел). Сама камера ничего не знает про выделение или узлы графа —
## это оставлено GDT_ViewportHost (`viewport_host.gd`), у которого есть
## контекст сцены; камера только вращается, летает и умеет фокусироваться на
## переданном AABB.
##
## @tool обязателен: скрипт живёт целиком внутри работающего редактора (это не
## игровая камера), и без @tool Godot не станет вызывать её _ready/_process.
##
## Camera3D — не Control и GUI-события не получает; вызывающий (viewport_host)
## перехватывает их через _gui_input и дёргает методы этого скрипта руками, а
## не полагается на встроенную маршрутизацию ввода Godot.
@tool
extends Camera3D

const MOVE_SPEED := 24.0
const BOOST_MULTIPLIER := 3.0
const LOOK_SENSITIVITY := 0.004
const ORBIT_SENSITIVITY := 0.01
const ZOOM_STEP := 4.0
const MIN_ORBIT_DISTANCE := 4.0
## Множитель к наибольшему габариту AABB при автокадрировании — запас, чтобы
## комната/слой не упирались в края вьюпорта.
const FOCUS_FRAME_MARGIN := 0.9

var _flying := false
var _orbiting := false
var _yaw := 0.0
var _pitch := 0.0
## Точка, вокруг которой вращает СКМ, и она же — центр последнего focus_on.
var _orbit_pivot := Vector3.ZERO
var _orbit_distance := 30.0


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func set_flying(active: bool) -> void:
	_flying = active
	_update_capture()


func set_orbiting(active: bool) -> void:
	_orbiting = active
	_update_capture()


## Хозяин зовёт перед set_orbiting(true) — камера сама не решает, вокруг чего
## вращаться (это могла бы быть выделенная комната, а могла — точка перед
## камерой; выбор оставлен вызывающему).
func begin_orbit(pivot: Vector3) -> void:
	_orbit_pivot = pivot
	_orbit_distance = maxf(position.distance_to(pivot), MIN_ORBIT_DISTANCE)


func orbit_distance() -> float:
	return _orbit_distance


func handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _flying:
		_yaw -= event.relative.x * LOOK_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENSITIVITY, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif _orbiting:
		_yaw -= event.relative.x * ORBIT_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * ORBIT_SENSITIVITY, -1.5, 1.5)
		_apply_orbit()


## direction: -1 — придвинуться (колесо вверх), +1 — отодвинуться.
func dolly(direction: float) -> void:
	position += -transform.basis.z * direction * ZOOM_STEP


## Ставит камеру так, чтобы [param aabb] было видно целиком, орбитой вокруг её
## центра — тот же пивот, которым потом воспользуется СКМ, если зажать её сразу
## после F или после автокадрирования слоя.
func focus_on(aabb: AABB) -> void:
	var span: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_orbit_pivot = aabb.get_center()
	_orbit_distance = maxf(span * FOCUS_FRAME_MARGIN, MIN_ORBIT_DISTANCE)
	_apply_orbit()
	# Последующий орбит-драг СКМ должен продолжить именно с этого ракурса, а не
	# дёрнуться к последнему yaw/pitch, оставшемуся от предыдущей орбиты.
	_yaw = rotation.y
	_pitch = rotation.x


func _process(delta: float) -> void:
	if not _flying:
		return
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_physical_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_physical_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		dir += Vector3.DOWN
	if dir == Vector3.ZERO:
		return
	var speed := MOVE_SPEED * (BOOST_MULTIPLIER if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	position += dir.normalized() * speed * delta


func _apply_orbit() -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	position = _orbit_pivot + basis.z * _orbit_distance
	look_at(_orbit_pivot, Vector3.UP)


func _update_capture() -> void:
	# Пока камера в движении (облёт или орбита) — курсор захвачен, как в родном
	# 3D-редакторе: иначе бесконечный драг мышью упирается в край экрана.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if (_flying or _orbiting) else Input.MOUSE_MODE_VISIBLE
