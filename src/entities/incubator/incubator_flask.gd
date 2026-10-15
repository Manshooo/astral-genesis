# res://src/entities/incubator/incubator_flask.gd
## Колба инкубатора: мозг в жидкости, свечение цветом души изнутри, пузырьки.
## Живёт в сцене сущности, а не у того, кто её поставил: колба одна и та же в
## хабе и за главным меню, и её поведение не должно размножаться по уровням.
##
## Арт ещё рисуется, и колба собрана так, чтобы приход модели был подменой
## ресурса, а не переделкой. Всё, что зависит от формы инкубатора, берётся у
## самой модели: объём колбы — по поверхности со стеклом MAT_incubator_glass,
## мозг и пузырьки — по пустым меткам BodyAnchor и BubbleSource; пока их нет,
## действуют запасные значения. Свечение кольца идёт через материал слота
## MAT_incubator_glow, а не через узел: модель, у которой слот назван так же,
## получит тот же .tres по ссылке из .import и задышит сама.
##
## Мутная светящаяся жидкость — в шейдере стекла (glass_refraction.gdshader), а
## не FogVolume: объёмный туман включён только в окружении меню, и в хабе колба
## с туманом была пустой. Колба передаёт своему экземпляру стекла диаметр (не
## толще него жидкость) и пульс свечения — instance uniform, общий .tres цел.
##
## Пузырьки — непрозрачные сферы, а не полупрозрачные спрайты, и появляются и
## гаснут масштабом, а не альфой. Стекло с преломлением рисует то, что за ним,
## из копии экрана, снятой ДО прохода прозрачных, и само пишет глубину
## (glass_refraction.gdshader повторяет в этом BaseMaterial3D с refraction:
## depth_draw_always, ALPHA = 1). Прозрачный пузырёк проигрывает при любом
## порядке: раньше стекла — затёрт копией экрана, где его нет; позже — отсечён
## глубиной передней стенки, и render_priority тут бессилен. Непрозрачный
## попадает в копию, и стекло преломляет его, как мозг. Тонкое кольцо для этого
## не годится: копию стекло читает с мипа roughness × 8, и кольцо в дюжину
## пикселей размывается в ничто.
##
## Числа движения здесь, а не в AnimationPlayer: свечение случайно по построению.
## Узел декоративный, а не ECS: в игровом состоянии колба ничего не меняет, а
## меню, где она тоже стоит, мира GECS не имеет.
class_name IncubatorFlask
extends Node3D

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

## Колба, пока у модели нет стекла: колонна болванки (r 0.88 м, y 1.15–4.9 м),
## с запасом внутрь. Не подгонка под болванку, а последнее, на что опереться:
## пришедшее стекло перекроет это число своим объёмом.
const FLASK_FALLBACK := AABB(Vector3(-0.85, 1.15, -0.85), Vector3(1.7, 3.75, 1.7))
## Пузырьки держатся чуть внутри стекла — иначе их край лёг бы на него.
const FLASK_INSET := 0.92
const GLASS_MATERIAL := "MAT_incubator_glass"
const BODY_ANCHOR := "BodyAnchor"
const BUBBLE_SOURCE := "BubbleSource"
## instance uniform шейдера стекла.
const GLASS_GLOW := &"glow"
const GLASS_LIQUID_DEPTH := &"liquid_depth"

## Материал слота свечения — тот самый ресурс, на который сошлётся .import
## пришедшей модели. Полем, а не const: в константу GDScript писать не даёт.
var _ring_glow: StandardMaterial3D = preload("res://assets/materials/MAT_incubator_glow.tres")

@onready var _model: Node3D = $Model
@onready var _glow: Light3D = $Glow
@onready var _bubbles: GPUParticles3D = $Bubbles
@onready var specimen: Node3D = $Specimen

var _noise := FastNoiseLite.new()
var _time := 0.0
var _specimen_base := Vector3.ZERO
## Меш со стеклом модели, а без стекла — null: тогда и жидкости нет.
var _glass: MeshInstance3D = null

## Авторские значения — множители считаются от них, а не от прошлого кадра.
## Материал слота — общий .tres, поэтому его значение возвращается на выходе:
## иначе следующая сцена сняла бы «авторское» с последнего перелива.
var _glow_energy := 0.0
var _ring_energy := 0.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_octaves = 2
	_noise.frequency = 1.0
	_noise.seed = randi()

	_fit()
	_glow_energy = _glow.light_energy
	_ring_energy = _ring_glow.emission_energy_multiplier


func _exit_tree() -> void:
	_ring_glow.emission_energy_multiplier = _ring_energy


func _process(delta: float) -> void:
	_time += delta
	var glow := glow_factor(_time)
	_glow.light_energy = _glow_energy * glow
	if _glass:
		_glass.set_instance_shader_parameter(GLASS_GLOW, glow)
	_ring_glow.emission_energy_multiplier = _ring_energy * glow

	specimen.position = _specimen_base \
			+ Vector3.UP * SPECIMEN_BOB * sin(TAU * _time / SPECIMEN_BOB_PERIOD)
	specimen.rotate_y(SPECIMEN_TURN * delta)


## Множитель свечения колбы в момент [param t]: 1 ± GLOW_SWING.
func glow_factor(t: float) -> float:
	var n := _noise.get_noise_1d(t * GLOW_RATE)
	return 1.0 + GLOW_SWING * clampf(n / GLOW_NOISE_PEAK, -1.0, 1.0)


## Объём колбы в пространстве этого узла: по стеклу модели, а без стекла — запасной.
func flask_box() -> AABB:
	var glass := _glass_surface()
	if glass.is_empty():
		return FLASK_FALLBACK
	var mesh: MeshInstance3D = glass[0]
	return _surface_box(mesh, glass[1], global_transform.affine_inverse() * mesh.global_transform)


## [меш, номер поверхности] со стеклом модели, а без стекла — пусто.
func _glass_surface() -> Array:
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			if _is_glass(mesh.get_active_material(surface)):
				return [mesh, surface]
	return []


## Свет, жидкость, пузырьки и мозг — в объём колбы и на метки модели.
func _fit() -> void:
	var box := flask_box()
	var center := box.get_center()
	var radius := minf(box.size.x, box.size.z) * 0.5 * FLASK_INSET
	var height := box.size.y * FLASK_INSET

	_glow.position = center
	var glass := _glass_surface()
	_glass = glass[0] if not glass.is_empty() else null
	if _glass:
		_glass.set_instance_shader_parameter(GLASS_LIQUID_DEPTH, minf(box.size.x, box.size.z))

	specimen.position = _marker_position(BODY_ANCHOR, center)
	_specimen_base = specimen.position

	var top := center.y + height * 0.5
	_bubbles.position = _marker_position(BUBBLE_SOURCE, center - Vector3.UP * height * 0.5)
	var process := _bubbles.process_material.duplicate() as ParticleProcessMaterial
	process.emission_ring_radius = radius * 0.85
	_bubbles.process_material = process
	_bubbles.lifetime = bubble_lifetime(process, maxf(top - _bubbles.position.y, 0.1))


## Жизнь пузырька, за которую САМЫЙ быстрый из них проходит [param height]:
## гаснут у крышки быстрые, медленные — чуть ниже, над крышкой — никто.
## Скорость и ускорение — из материала частиц, а не своим числом: материал
## разгоняет пузырьки вверх (gravity), и жизнь «высота на среднюю скорость»
## выпускала их над колбой на полметра.
static func bubble_lifetime(process: ParticleProcessMaterial, height: float) -> float:
	var speed := process.initial_velocity_max
	var lift := process.gravity.y
	if absf(lift) < 0.001:
		return height / maxf(speed, 0.01)
	# h = v·t + a·t²/2 — положительный корень.
	return (-speed + sqrt(maxf(speed * speed + 2.0 * lift * height, 0.0))) / lift


## Позиция метки модели в пространстве этого узла, а без метки — [param fallback].
## Ищется вглубь и среди чужих узлов: метка лежит внутри инстанса .glb.
func _marker_position(marker_name: String, fallback: Vector3) -> Vector3:
	var marker := _model.find_child(marker_name, true, false) as Node3D
	if marker == null:
		return fallback
	return global_transform.affine_inverse() * marker.global_position


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
