extends Camera3D
## Камера облёта для экранов станций полигона: смотрит на цель со стороны, пока игровая камера ждёт. Живёт в сцене экрана
## (под Control она мировая — родитель не Node3D), с его закрытием ход возвращается камере игрока. Вики: [[Полигон]].

## Градусов поворота на пиксель движения мыши.
const TURN_PER_PIXEL := 0.3
## Во сколько раз шаг колеса меняет дистанцию.
const ZOOM_STEP := 1.12
const DISTANCE_RANGE := Vector2(0.6, 30.0)
const PITCH_RANGE := Vector2(-85.0, 85.0)

## Цель облёта; камера держит её в центре кадра.
var target: Node3D
## Сдвиг точки взгляда от цели (колёсико с зажатой кнопкой — панорама).
var offset := Vector3.ZERO
var yaw := 30.0
var pitch := -15.0
var distance := 5.0

var _dragging := false
var _panning := false


## Начать облёт [param focus] с дистанции [param from_distance], глядя на [param height] м выше его начала координат.
func look_at_target(focus: Node3D, from_distance: float, height := 0.0) -> void:
	target = focus
	distance = from_distance
	offset = Vector3(0.0, height, 0.0)
	make_current()
	_place()


## Экран закрыли — кадр снова у камеры игрока (иначе движок взял бы первую попавшуюся).
func _exit_tree() -> void:
	if not current:
		return
	var player := E_Player.find() as E_Player
	if player != null and player.camera != null:
		player.camera.make_current()


func _process(_delta: float) -> void:
	_place()


## Клик по панели экрана сюда не доходит — GUI забирает его раньше; пустое место экрана пропускает (mouse_filter IGNORE).
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT:
				_dragging = button.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				distance = clampf(distance / ZOOM_STEP, DISTANCE_RANGE.x, DISTANCE_RANGE.y)
			MOUSE_BUTTON_WHEEL_DOWN:
				distance = clampf(distance * ZOOM_STEP, DISTANCE_RANGE.x, DISTANCE_RANGE.y)
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _dragging:
		yaw -= motion.relative.x * TURN_PER_PIXEL
		pitch = clampf(pitch - motion.relative.y * TURN_PER_PIXEL, PITCH_RANGE.x, PITCH_RANGE.y)
	elif _panning:
		var per_pixel := distance * 0.002
		offset += (-global_basis.x * motion.relative.x + global_basis.y * motion.relative.y) * per_pixel


func _place() -> void:
	if not is_instance_valid(target):
		return
	var focus := target.global_position + offset
	var direction := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)) * Vector3.BACK
	global_position = focus + direction * distance
	look_at(focus, Vector3.UP)
