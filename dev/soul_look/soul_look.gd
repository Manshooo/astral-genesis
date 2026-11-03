extends Node3D
## Витрина облика БФЖ: выбранный сгусток (вид снаружи) и клочья по краям кадра
## (вид от первого лица), чтобы доводить облик глазами. Ничего из игры не трогает;
## запуск — F6 на сцене. Решения и выводы — [[Облик БФЖ]].

const SoulMover := preload("res://dev/soul_look/soul_mover.gd")

enum Mode { SIDE, FPV }

const FPV_NAMES: Array[String] = ["без клочьев", "экранный шейдер", "частицы у камеры", "карточки, наплывают и тают"]
const PALETTE_NAMES: Array[String] = ["холодный бело-голубой", "тёмный дым с ядром"]
const OVERVIEW_TARGET := Vector3(0.0, 1.4, 0.0)
## Комната 16×16 м: дальше камера уходит за стену.
const OVERVIEW_DISTANCE := 7.0
const MOUSE_SENSITIVITY := 0.003
const FLY_SPEED := 2.5

var mode := Mode.SIDE
var fpv_variant := 1
var palette := 1
## Распад для облика, как его отдаёт S_SoulCloud в игре (0 — спокойно, 1 — на исходе).
var decay := 0.0

var _focus := -1
var _target := OVERVIEW_TARGET
var _target_goal := OVERVIEW_TARGET
var _yaw := 0.0
var _pitch := -0.25
var _distance := OVERVIEW_DISTANCE
var _distance_goal := OVERVIEW_DISTANCE
var _fpv_yaw := 0.0
var _fpv_pitch := 0.0
var _orbiting := false

@onready var _side_camera: Camera3D = %SideCamera
@onready var _fpv_camera: Camera3D = %FpvCamera
@onready var _stands: Node3D = %Stands
@onready var _hud: Label = %Hud
## След игрока: дымка из той же частицы, что шлейф сгустка, идёт всегда и стекает
## вниз — стоя видно, как она течёт к полу, на ходу она тянется за камерой.
@onready var _trail: GPUParticles3D = %FpvTrail
## Место следа относительно глаз — из сцены; узел top_level, чтобы не наклоняться с камерой.
@onready var _trail_offset: Vector3 = _trail.position
@onready var _fpv_nodes: Array = [
	[],
	[%FpvScreenCold, %FpvScreenDark],
	[%FpvParticlesCold, %FpvParticlesDark],
	[%FpvCardsCold, %FpvCardsDark],
]


func _ready() -> void:
	_fpv_yaw = _fpv_camera.rotation.y
	_fpv_pitch = _fpv_camera.rotation.x
	set_mode(Mode.SIDE)
	focus(0)


func set_mode(value: Mode) -> void:
	mode = value
	_side_camera.current = mode == Mode.SIDE
	_fpv_camera.current = mode == Mode.FPV
	_trail.visible = mode == Mode.FPV
	_trail.emitting = mode == Mode.FPV
	if mode == Mode.SIDE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_fpv()


func set_fpv(variant: int, palette_index: int) -> void:
	fpv_variant = clampi(variant, 0, FPV_NAMES.size() - 1)
	palette = clampi(palette_index, 0, PALETTE_NAMES.size() - 1)
	_apply_fpv()


## Сгусток вблизи (0) или общий план (-1).
func focus(index: int) -> void:
	_focus = index if index < _stands.get_child_count() else -1
	if _focus < 0:
		_target_goal = OVERVIEW_TARGET
		_distance_goal = OVERVIEW_DISTANCE
	else:
		var stand := _stands.get_child(_focus) as SoulMover
		_target_goal = stand.global_position + Vector3(0.0, stand.height, 0.0)
		_distance_goal = 3.6


func snap_camera() -> void:
	_target = _target_goal
	_distance = _distance_goal
	_update_side_camera(0.0)


func set_orbit(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch


func place_fpv(at: Vector3, yaw: float, pitch: float) -> void:
	_fpv_camera.global_position = at
	_fpv_yaw = yaw
	_fpv_pitch = pitch
	_fpv_camera.rotation = Vector3(_fpv_pitch, _fpv_yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key((event as InputEventKey).physical_keycode)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var motion := (event as InputEventMouseMotion).relative
		if mode == Mode.SIDE and _orbiting:
			_yaw -= motion.x * MOUSE_SENSITIVITY
			_pitch = clampf(_pitch - motion.y * MOUSE_SENSITIVITY, -1.4, 1.2)
		elif mode == Mode.FPV and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_fpv_yaw -= motion.x * MOUSE_SENSITIVITY
			_fpv_pitch = clampf(_fpv_pitch - motion.y * MOUSE_SENSITIVITY, -1.5, 1.5)


func _on_key(key: Key) -> void:
	match key:
		KEY_TAB:
			set_mode(Mode.FPV if mode == Mode.SIDE else Mode.SIDE)
		KEY_F:
			SoulMover.paused = not SoulMover.paused
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			set_decay(decay + (0.1 if key == KEY_BRACKETRIGHT else -0.1))
		KEY_C:
			set_fpv(fpv_variant, 1 - palette)
		KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_:
			var digit := key - KEY_0
			if digit < 0 or digit > 9:
				return
			if mode == Mode.SIDE:
				focus(digit - 1)
			elif digit < FPV_NAMES.size():
				set_fpv(digit, palette)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if mode == Mode.SIDE:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_distance_goal = maxf(_distance_goal * 0.9, 1.2)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_distance_goal = minf(_distance_goal * 1.1, 16.0)
	elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_update_side_camera(delta)
	if mode == Mode.FPV:
		_fly(delta)
	_hud.text = _hud_text()


func _update_side_camera(delta: float) -> void:
	var k := 1.0 - exp(-6.0 * delta) if delta > 0.0 else 1.0
	_target = _target.lerp(_target_goal, k)
	_distance = lerpf(_distance, _distance_goal, k)
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_side_camera.global_position = _target + dir * _distance
	_side_camera.look_at(_target)


func _fly(delta: float) -> void:
	_fpv_camera.rotation = Vector3(_fpv_pitch, _fpv_yaw, 0.0)
	var input := Vector3(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	var speed := FLY_SPEED * (2.5 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	_fpv_camera.global_position += _fpv_camera.global_basis * input.limit_length(1.0) * speed * delta
	# Под ногами, а не под объективом: с наклоном камеры след ушёл бы за спину.
	_trail.global_position = _fpv_camera.global_position + Basis(Vector3.UP, _fpv_yaw) * _trail_offset


## Та же раздача, что у S_SoulCloud._apply_decay: параметр шейдера всем клочкам и меньше частиц.
func set_decay(value: float) -> void:
	decay = clampf(snappedf(value, 0.1), 0.0, 1.0)
	var share := C_SoulCloud.new().decay_amount
	for node in find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).set_instance_shader_parameter(&"decay", decay)
		if node is GPUParticles3D:
			(node as GPUParticles3D).amount_ratio = lerpf(1.0, share, decay)


func _apply_fpv() -> void:
	for v in _fpv_nodes.size():
		var pair: Array = _fpv_nodes[v]
		for p in pair.size():
			var shown: bool = mode == Mode.FPV and v == fpv_variant and p == palette
			var node: Node = pair[p]
			node.set(&"visible", shown)
			if node is GPUParticles3D:
				(node as GPUParticles3D).emitting = shown


func _hud_text() -> String:
	var lines: Array[String] = []
	if mode == Mode.SIDE:
		lines.append("СНАРУЖИ — %s" % ("общий план" if _focus < 0 else "вблизи"))
		lines.append("1 вблизи · 0 общий план · ЛКМ орбита · колесо зум")
	else:
		lines.append("ОТ ПЕРВОГО ЛИЦА — %s · %s" % [FPV_NAMES[fpv_variant], PALETTE_NAMES[palette]])
		lines.append("ЛКМ захват мыши · WASD/QE полёт · 1–3 вариант · 0 без · C палитра · Esc мышь")
	lines.append("Tab снаружи/первое лицо · F движение %s · [ ] распад %.1f" % [
			"стоит" if SoulMover.paused else "идёт", decay])
	return "\n".join(lines)
