# res://src/levels/menu_map/l_menu_map.gd
## Живая сцена за главным меню — крупный план инкубатора глазами души (§8 «Меню — спека»): колба (IncubatorFlask),
## лаборатория в темноте и тумане, камера «дышит». Здесь только кадр меню: камера, лампа, кровь, тела. Арт заглушек
## подменяется ресурсом: свечение лампы — через материал слота, действие модели — меткой menu_action на узле.
extends Node3D

## Сдвиг композиции: инкубатор уходит вправо (меню слева, точка схода ~70 % ширины).
const COMPOSITION_YAW := 0.39
## Дыхание камеры: ±4 см по высоте за 6 с.
const BREATH_AMPLITUDE := 0.04
const BREATH_PERIOD := 6.0

## Лампа: долгая темнота, серия вспышек, иногда «поймала»; пределы — [от, до] (с / штук).
const FLICKER_PAUSE := Vector2(1.5, 5.0)
const FLICKER_FLASHES := Vector2i(2, 6)
const FLASH_ON := Vector2(0.03, 0.16)
const FLASH_OFF := Vector2(0.03, 0.12)
const FLICKER_HOLD := Vector2(0.4, 1.4)
const FLICKER_HOLD_CHANCE := 0.35
## Погасшая трубка не чёрная: концы тлеют.
const LAMP_DEAD_GLOW := 0.08

const ACTION_META := &"menu_action"

## Материал слота свечения лампы — ресурс, на который сошлётся .import модели. Полем: в const не пишется.
var _lamp_glow: StandardMaterial3D = preload("res://assets/materials/MAT_light_fluorescent_glow.tres")

@onready var camera: Camera3D = $Camera3D
@onready var _flask: IncubatorFlask = $Incubator/Flask
@onready var _lamp: Light3D = $FluorescentLamp/Light
@onready var _lab: Node3D = $Lab
@onready var _blood: Node3D = $Lab/Blood

var _time := 0.0
var _base_height := 0.0

## Авторские значения; материал слота общий .tres — на выходе возвращается.
var _lamp_energy := 0.0
var _lamp_glow_energy := 0.0

var _lamp_lit := false
var _flashes_left := 0
var _flicker_left := 0.0


func _ready() -> void:
	_lamp_energy = _lamp.light_energy
	_lamp_glow_energy = _lamp_glow.emission_energy_multiplier
	_flashes_left = randi_range(FLICKER_FLASHES.x, FLICKER_FLASHES.y)
	# Первая серия — скоро: лампа не должна молчать пять секунд.
	_flicker_left = randf_range(0.3, 1.2)
	_apply_lamp()

	_fill_blood_stubs()
	_play_actions()

	camera.make_current()
	# Мозг уже стоит: _ready() колбы отработал раньше.
	camera.look_at(_flask.specimen.global_position)
	camera.rotate_y(COMPOSITION_YAW)
	_base_height = camera.position.y


func _exit_tree() -> void:
	_lamp_glow.emission_energy_multiplier = _lamp_glow_energy


func _process(delta: float) -> void:
	_time += delta
	camera.position.y = _base_height + BREATH_AMPLITUDE * sin(TAU * _time / BREATH_PERIOD)
	_step_flicker(delta)


## Серии вспышек со случайными паузами: комната видна урывками.
func _step_flicker(delta: float) -> void:
	_flicker_left -= delta
	if _flicker_left > 0.0:
		return
	if _lamp_lit:
		_lamp_lit = false
		if _flashes_left > 0:
			_flicker_left = randf_range(FLASH_OFF.x, FLASH_OFF.y)
		else:
			_flashes_left = randi_range(FLICKER_FLASHES.x, FLICKER_FLASHES.y)
			_flicker_left = randf_range(FLICKER_PAUSE.x, FLICKER_PAUSE.y)
	else:
		_lamp_lit = true
		_flashes_left -= 1
		_flicker_left = randf_range(FLASH_ON.x, FLASH_ON.y)
		if _flashes_left == 0 and randf() < FLICKER_HOLD_CHANCE:
			_flicker_left = randf_range(FLICKER_HOLD.x, FLICKER_HOLD.y)
	_apply_lamp()


func _apply_lamp() -> void:
	_lamp.light_energy = _lamp_energy if _lamp_lit else 0.0
	_lamp_glow.emission_energy_multiplier = _lamp_glow_energy * (1.0 if _lamp_lit else LAMP_DEAD_GLOW)


## Заглушка атласа крови, только декалям без своей текстуры.
func _fill_blood_stubs() -> void:
	var stub: Texture2D = null
	for decal: Decal in _blood.find_children("*", "Decal", true, false):
		if decal.texture_albedo:
			continue
		if stub == null:
			stub = _draw_blood_stub()
		decal.texture_albedo = stub


## Одно пятно на все декали: разнообразие — поворот и размер.
static func _draw_blood_stub() -> ImageTexture:
	const SIZE := 128
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.045
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Брызги вокруг лужи: (центр, радиус) в долях стороны.
	var drops: Array[Vector3] = []
	for i in 14:
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(0.34, 0.47)
		drops.append(Vector3(0.5 + cos(angle) * reach, 0.5 + sin(angle) * reach, rng.randf_range(0.008, 0.03)))
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var uv := Vector2(x, y) / SIZE
			var pool := 1.0 - uv.distance_to(Vector2(0.5, 0.5)) / 0.32 + 0.35 * noise.get_noise_2d(x, y)
			var alpha := clampf((pool - 0.1) * 5.0, 0.0, 1.0)
			for drop in drops:
				if uv.distance_to(Vector2(drop.x, drop.y)) < drop.z:
					alpha = 1.0
			# Края темнее середины — засохшая лужа читается кровью, а не краской.
			var shade := lerpf(0.11, 0.24, clampf(pool, 0.0, 1.0))
			image.set_pixel(x, y, Color(shade, shade * 0.08, shade * 0.08, alpha))
	return ImageTexture.create_from_image(image)


## Действие из метки menu_action: модель с такой анимацией играет её; заглушки читают метку сами.
func _play_actions() -> void:
	for node in _lab.get_children():
		if not node.has_meta(ACTION_META):
			continue
		var action := StringName(node.get_meta(ACTION_META))
		for player: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
			if player.has_animation(action):
				player.play(action)
				break
