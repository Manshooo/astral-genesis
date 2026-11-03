extends Node3D
## Стенд витрины облика БФЖ: водит сгусток `Blob` восьмёркой с остановками и
## помнит его след за последние `trail_seconds` — по следу варианты строят шлейф.
## На остановке след стягивается в сгусток сам: точки следа догоняют голову.
## [[Облик БФЖ]].

## Общая на все стенды пауза движения (клавиша F витрины).
static var paused := false

@export var amplitude := Vector3(1.0, 0.15, 0.6)
@export var height := 1.4
@export var speed := 1.4
@export var phase_offset := 0.0
@export var trail_seconds := 1.1
@export_range(4, 128) var samples := 32

var _time := 0.0
var _phase := 0.0
var _acc := 0.0
var _history := PackedVector3Array()
var _geometry: Array[GeometryInstance3D] = []

@onready var blob: Node3D = $Blob


func _ready() -> void:
	_time = phase_offset
	_phase = phase_offset
	_place_blob()
	_history.resize(samples)
	_history.fill(blob.global_position)
	for node in find_children("*", "GeometryInstance3D", true, false):
		_geometry.append(node as GeometryInstance3D)


func _process(delta: float) -> void:
	if not paused:
		_time += delta
		# Движется примерно половину времени: видно и вытянутый шлейф, и как он стягивается.
		var gate := smoothstep(-0.2, 0.4, sin(_time * 0.8))
		_phase += delta * speed * gate
	_place_blob()
	var step := trail_seconds / samples
	_acc += delta
	while _acc >= step:
		_acc -= step
		for i in range(samples - 1, 0, -1):
			_history[i] = _history[i - 1]
	_history[0] = blob.global_position
	for g in _geometry:
		g.set_instance_shader_parameter(&"blob_center", blob.global_position)


## Точка следа: 0 — сам сгусток, 1 — самая старая.
func sample(t: float) -> Vector3:
	var f := clampf(t, 0.0, 1.0) * (samples - 1)
	var i := mini(int(f), samples - 2)
	return _history[i].lerp(_history[i + 1], f - i)


func velocity() -> Vector3:
	return (_history[0] - _history[2]) / (2.0 * trail_seconds / samples)


func _place_blob() -> void:
	blob.position = Vector3(
			amplitude.x * sin(_phase),
			height + amplitude.y * sin(_phase * 3.0),
			amplitude.z * sin(_phase * 2.0))
