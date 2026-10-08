# res://src/levels/menu_map/l_menu_map.gd
## Живая сцена за главным меню — операционная глазами души (§8 «Меню —
## спека», язык «Отголосок»): каталка с телом под простынёй, пустой бак, где
## держали мозг, сиреневые струйки из него, единственная тёплая лампа с пылью в
## луче. Камера — сама душа под потолком: не облетает сцену, а «дышит».
##
## Сцена собрана из примитивов поверх коробки кита и инкубатора — моделей
## каталки и тела нет. Числа движения здесь, а не в AnimationPlayer: их два, и
## оба — тот же такт, что у HUD (дыхание 6 с, подмигивание лампы ~5 с).
extends Node3D

## Куда смотрит душа: каталка, и чуть левее её — меню стоит слева, композиция
## смещена вправо (точка схода ≈ x 1040 из 1497).
const LOOK_AT := Vector3(2.1, 0.9, 0.2)
const COMPOSITION_YAW := 0.22
## Дыхание камеры: ±4 см по высоте за 6 с.
const BREATH_AMPLITUDE := 0.04
const BREATH_PERIOD := 6.0
## Лампа подмигивает: раз в ~5.3 с проседает до 55 % на один кадр-два.
const FLICKER_PERIOD := 5.3
const FLICKER_DIP := 0.55
const FLICKER_TIME := 0.06

@onready var camera: Camera3D = $Camera3D
@onready var _lamp: SpotLight3D = $Lamp

var _base_height := 0.0
var _lamp_energy := 0.0
var _next_flicker := 0.0
var _flicker_left := 0.0
var _time := 0.0


func _ready() -> void:
	camera.make_current()
	camera.look_at(LOOK_AT)
	camera.rotate_y(COMPOSITION_YAW)
	_base_height = camera.position.y
	_lamp_energy = _lamp.light_energy
	_next_flicker = FLICKER_PERIOD


func _process(delta: float) -> void:
	_time += delta
	camera.position.y = _base_height + BREATH_AMPLITUDE * sin(TAU * _time / BREATH_PERIOD)

	if _flicker_left > 0.0:
		_flicker_left -= delta
		if _flicker_left <= 0.0:
			_lamp.light_energy = _lamp_energy
	elif _time >= _next_flicker:
		_lamp.light_energy = _lamp_energy * FLICKER_DIP
		_flicker_left = FLICKER_TIME
		# Не метроном: подмигивание с разбросом читается как старая лампа, а не
		# как анимация.
		_next_flicker = _time + FLICKER_PERIOD * randf_range(0.7, 1.3)
