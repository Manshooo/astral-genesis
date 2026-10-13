# res://src/levels/menu_map/l_menu_map.gd
## Живая сцена за главным меню — крупный план инкубатора глазами души (§8 «Меню —
## спека», язык «Отголосок»): в колбе плавает мозг, от которого разряд отделил
## Бифижа, колба светится изнутри цветом души, а за ней, в темноте и тумане, —
## лаборатория после катастрофы: тела учёных, гончая над одним из них, кровь,
## умирающая люминесцентная лампа. Камера — сама душа: не облетает сцену, а
## «дышит».
##
## Арт ещё рисуется, и сцена собрана так, чтобы приход модели был подменой
## ресурса, а не переделкой. Всё, что зависит от формы инкубатора, скрипт берёт у
## самой модели: объём колбы — по поверхности со стеклом MAT_incubator_glass,
## мозг и пузырьки — по пустым меткам BodyAnchor и BubbleSource; пока их нет,
## действуют запасные значения. Свечение кольца и лампы идёт через материалы
## слотов (MAT_incubator_glow, MAT_light_fluorescent_glow), а не через узлы:
## модель, у которой слот назван так же, получит тот же .tres по ссылке из
## .import и замерцает сама. Действие модели (собака ест, учёный лежит в позе)
## лежит меткой menu_action на узле сцены — она переживает подмену заглушки.
##
## Числа движения здесь, а не в AnimationPlayer: свечение и лампа случайны по
## построению, а дыхание — тот же такт, что у HUD (6 с).
extends Node3D

## Сдвиг композиции: душа смотрит на мозг, но кадр повёрнут так, что инкубатор
## уходит вправо (меню слева, точка схода ≈ x 1040 из 1497).
const COMPOSITION_YAW := 0.39
## Дыхание камеры: ±4 см по высоте за 6 с.
const BREATH_AMPLITUDE := 0.04
const BREATH_PERIOD := 6.0

## Свечение колбы плавает на ±12 % — живое, но не мигает. Шум, а не синус:
## период у синуса читается через пару циклов, и свет становится механизмом.
const GLOW_SWING := 0.12
## Скорость по шуму, единиц шума в секунду при частоте 1: перелив за 1.5–3 с.
## Шум с двумя октавами редко выходит за ±0.8 (замер на 10⁵ выборок), этим и
## нормируется.
const GLOW_RATE := 0.5
const GLOW_NOISE_PEAK := 0.8

## Мозг покачивается в жидкости и медленно поворачивается.
const SPECIMEN_BOB := 0.03
const SPECIMEN_BOB_PERIOD := 7.0
const SPECIMEN_TURN := 0.05

## Лампа: долгая темнота, потом серия вспышек, иногда — короткое «поймала» в
## конце серии. Пределы — [от, до] в секундах (число вспышек — штук).
const FLICKER_PAUSE := Vector2(1.5, 5.0)
const FLICKER_FLASHES := Vector2i(2, 6)
const FLASH_ON := Vector2(0.03, 0.16)
const FLASH_OFF := Vector2(0.03, 0.12)
const FLICKER_HOLD := Vector2(0.4, 1.4)
const FLICKER_HOLD_CHANCE := 0.35
## Погасшая трубка не чёрная: концы умирающей люминесцентной лампы тлеют.
const LAMP_DEAD_GLOW := 0.08

## Колба, пока у модели нет стекла: колонна нынешней болванки (r 0.88 м,
## y 1.15–4.9 м), с запасом внутрь. Не подгонка под болванку, а последнее, на
## что опереться: пришедшее стекло перекроет это число своим объёмом.
const FLASK_FALLBACK := AABB(Vector3(-0.85, 1.15, -0.85), Vector3(1.7, 3.75, 1.7))
## Туман и пузырьки держатся чуть внутри стекла — иначе их край лёг бы на него.
const FLASK_INSET := 0.92
const GLASS_MATERIAL := "MAT_incubator_glass"
const BODY_ANCHOR := "BodyAnchor"
const BUBBLE_SOURCE := "BubbleSource"
## Средняя скорость подъёма пузырька, м/с: жизнь частицы — высота колбы на неё,
## чтобы пузырёк гас у крышки, а не на полпути и не над ней.
const BUBBLE_SPEED := 0.55
const ACTION_META := &"menu_action"

## Материалы слотов свечения — тот самый ресурс, на который сошлётся .import
## пришедшей модели. Полем, а не const: в константу GDScript писать не даёт.
var _ring_glow: StandardMaterial3D = preload("res://assets/materials/MAT_incubator_glow.tres")
var _lamp_glow: StandardMaterial3D = preload("res://assets/materials/MAT_light_fluorescent_glow.tres")

@onready var camera: Camera3D = $Camera3D
@onready var _incubator: Node3D = $Incubator
@onready var _model: Node3D = $Incubator/Model
@onready var _glow: Light3D = $Incubator/Glow
@onready var _glow_fog: FogVolume = $Incubator/GlowFog
@onready var _bubbles: GPUParticles3D = $Incubator/Bubbles
@onready var _specimen: Node3D = $Incubator/Specimen
@onready var _lamp: Light3D = $FluorescentLamp/Light
@onready var _lab: Node3D = $Lab
@onready var _blood: Node3D = $Lab/Blood

var _noise := FastNoiseLite.new()
var _time := 0.0
var _base_height := 0.0
var _specimen_base := Vector3.ZERO

## Авторские значения — множители считаются от них, а не от прошлого кадра.
## Материалы слотов — общие .tres, поэтому их значения возвращаются на выходе:
## иначе следующее меню сняло бы «авторское» с последней вспышки.
var _glow_energy := 0.0
var _fog_emission := Color.BLACK
var _ring_energy := 0.0
var _lamp_energy := 0.0
var _lamp_glow_energy := 0.0

var _lamp_lit := false
var _flashes_left := 0
var _flicker_left := 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_octaves = 2
	_noise.frequency = 1.0
	_noise.seed = randi()

	_fit_flask()
	_glow_energy = _glow.light_energy
	# Материал тумана правится каждый кадр — своя копия, а не ресурс сцены.
	_glow_fog.material = _glow_fog.material.duplicate()
	_fog_emission = (_glow_fog.material as FogMaterial).emission
	_ring_energy = _ring_glow.emission_energy_multiplier
	_lamp_energy = _lamp.light_energy
	_lamp_glow_energy = _lamp_glow.emission_energy_multiplier
	_flashes_left = randi_range(FLICKER_FLASHES.x, FLICKER_FLASHES.y)
	# Первая серия — скоро: меню открыли, и лампа не должна молчать пять секунд.
	_flicker_left = randf_range(0.3, 1.2)
	_apply_lamp()

	_fill_blood_stubs()
	_play_actions()

	camera.make_current()
	camera.look_at(_specimen.global_position)
	camera.rotate_y(COMPOSITION_YAW)
	_base_height = camera.position.y


func _exit_tree() -> void:
	_ring_glow.emission_energy_multiplier = _ring_energy
	_lamp_glow.emission_energy_multiplier = _lamp_glow_energy


func _process(delta: float) -> void:
	_time += delta
	camera.position.y = _base_height + BREATH_AMPLITUDE * sin(TAU * _time / BREATH_PERIOD)

	var glow := glow_factor(_time)
	_glow.light_energy = _glow_energy * glow
	(_glow_fog.material as FogMaterial).emission = _fog_emission * glow
	_ring_glow.emission_energy_multiplier = _ring_energy * glow

	_specimen.position = _specimen_base \
			+ Vector3.UP * SPECIMEN_BOB * sin(TAU * _time / SPECIMEN_BOB_PERIOD)
	_specimen.rotate_y(SPECIMEN_TURN * delta)

	_step_flicker(delta)


## Множитель свечения колбы в момент [param t]: 1 ± GLOW_SWING.
func glow_factor(t: float) -> float:
	var n := _noise.get_noise_1d(t * GLOW_RATE)
	return 1.0 + GLOW_SWING * clampf(n / GLOW_NOISE_PEAK, -1.0, 1.0)


## Объём колбы в пространстве Incubator: по стеклу модели, а без стекла — запасной.
func flask_box() -> AABB:
	var to_local := _incubator.global_transform.affine_inverse()
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			if _is_glass(mesh.get_active_material(surface)):
				return _surface_box(mesh, surface, to_local * mesh.global_transform)
	return FLASK_FALLBACK


## Туман, свет, пузырьки и мозг — в объём колбы и на метки модели.
func _fit_flask() -> void:
	var box := flask_box()
	var center := box.get_center()
	var radius := minf(box.size.x, box.size.z) * 0.5 * FLASK_INSET
	var height := box.size.y * FLASK_INSET

	_glow.position = center
	_glow_fog.position = center
	_glow_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
	_glow_fog.size = Vector3(radius * 2.0, height, radius * 2.0)

	_specimen.position = _marker_position(BODY_ANCHOR, center)
	_specimen_base = _specimen.position

	var top := center.y + height * 0.5
	_bubbles.position = _marker_position(BUBBLE_SOURCE, center - Vector3.UP * height * 0.5)
	var process := _bubbles.process_material.duplicate() as ParticleProcessMaterial
	process.emission_ring_radius = radius * 0.85
	_bubbles.process_material = process
	_bubbles.lifetime = maxf(top - _bubbles.position.y, 0.5) / BUBBLE_SPEED


## Позиция метки модели в пространстве Incubator, а без метки — [param fallback].
## Ищется вглубь и среди чужих узлов: метка лежит внутри инстанса .glb.
func _marker_position(marker_name: String, fallback: Vector3) -> Vector3:
	var marker := _model.find_child(marker_name, true, false) as Node3D
	if marker == null:
		return fallback
	return _incubator.global_transform.affine_inverse() * marker.global_position


static func _is_glass(material: Material) -> bool:
	if material == null:
		return false
	return material.resource_name == GLASS_MATERIAL \
			or material.resource_path.get_file().get_basename() == GLASS_MATERIAL


## Коробка одной поверхности, а не всего меша: стекло может прийти поверхностью
## того же меша, что корпус, и коробка меша накрыла бы корпус целиком.
static func _surface_box(mesh: MeshInstance3D, surface: int, xform: Transform3D) -> AABB:
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
	if vertices.is_empty():
		return xform * mesh.get_aabb()
	var box := AABB(xform * vertices[0], Vector3.ZERO)
	for vertex in vertices:
		box = box.expand(xform * vertex)
	return box


## Серии вспышек со случайными паузами: лампа почти всё время мертва, и
## комната видна урывками.
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


## Заглушка атласа крови — пятно, нарисованное кодом, и только тем декалям, у
## которых своей текстуры ещё нет: пришедший атлас назначается декали в сцене, и
## код её больше не трогает.
func _fill_blood_stubs() -> void:
	var stub: Texture2D = null
	for decal: Decal in _blood.find_children("*", "Decal", true, false):
		if decal.texture_albedo:
			continue
		if stub == null:
			stub = _draw_blood_stub()
		decal.texture_albedo = stub


## Одно пятно на все декали: разнообразие дают поворот и размер декали.
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
			# Края запекаются темнее середины — так засохшая лужа читается кровью,
			# а не краской.
			var shade := lerpf(0.11, 0.24, clampf(pool, 0.0, 1.0))
			image.set_pixel(x, y, Color(shade, shade * 0.08, shade * 0.08, alpha))
	return ImageTexture.create_from_image(image)


## Действие из метки menu_action: модель, у которой есть анимация с этим
## именем, играет её. Заглушки анимаций не имеют и читают метку сами.
func _play_actions() -> void:
	for node in _lab.get_children():
		if not node.has_meta(ACTION_META):
			continue
		var action := StringName(node.get_meta(ACTION_META))
		for player: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
			if player.has_animation(action):
				player.play(action)
				break
