## res://addons/game_design_tool/world/editor_camera.gd
## Фри-камера вьюпорта генератора: облёт по ПКМ и орбита по СКМ. Про выделение
## и узлы графа не знает — методы ей зовёт GDT_ViewportHost.
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
@tool
extends Camera3D

const MOVE_SPEED := 24.0
const BOOST_MULTIPLIER := 3.0
const LOOK_SENSITIVITY := 0.004
const ORBIT_SENSITIVITY := 0.01
const ZOOM_STEP := 4.0
const MIN_ORBIT_DISTANCE := 4.0
## Запас к наибольшему габариту AABB при автокадрировании.
const FOCUS_FRAME_MARGIN := 0.9

var _flying := false
var _orbiting := false
var _yaw := 0.0
var _pitch := 0.0
## Центр орбиты СКМ и последнего focus_on.
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


## Держит ли камера мышь прямо сейчас (облёт или орбита).
func is_moving() -> bool:
	return _flying or _orbiting


## Хозяин зовёт перед set_orbiting(true): вокруг чего вращаться, решает он.
func begin_orbit(pivot: Vector3) -> void:
	_orbit_pivot = pivot
	_orbit_distance = maxf(position.distance_to(pivot), MIN_ORBIT_DISTANCE)


func orbit_distance() -> float:
	return _orbit_distance


## Восстанавливает сохранённое положение; _yaw/_pitch пересчитываются из него,
## иначе первый облёт дёрнет камеру к ракурсу, оставшемуся с _ready().
func restore_transform(pos: Vector3, rot_degrees: Vector3) -> void:
	position = pos
	rotation_degrees = rot_degrees
	_yaw = rotation.y
	_pitch = rotation.x


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


## Кадрирует [param aabb] целиком орбитой вокруг его центра (он же пивот СКМ).
func focus_on(aabb: AABB) -> void:
	var span: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	_orbit_pivot = aabb.get_center()
	_orbit_distance = maxf(span * FOCUS_FRAME_MARGIN, MIN_ORBIT_DISTANCE)
	_apply_orbit()
	# Иначе следующий драг СКМ дёрнется к yaw/pitch прошлой орбиты.
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
	# Захват курсора, как в родном 3D-редакторе: иначе драг упирается в край экрана.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if (_flying or _orbiting) else Input.MOUSE_MODE_VISIBLE
