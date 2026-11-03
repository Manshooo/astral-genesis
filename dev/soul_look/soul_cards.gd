extends MultiMeshInstance3D
## Голова облика БФЖ для витрины: горсть карточек-билбордов вокруг сгустка
## стенда, сложенная из нескольких бродящих комков, — форма не держится шаром.
## Шлейф — не здесь, его тянут частицы стенда. Узел top_level: карточки на ходу
## отстают по следу в мире, а не едут за стендом. [[Облик БФЖ]].

const SoulMover := preload("res://dev/soul_look/soul_mover.gd")

@export var count := 30
@export var radius := 0.55
## Сплюснутость по осям: плоский широкий сгусток стелется, а не висит шаром.
@export var shape := Vector3(1.3, 0.55, 1.1)
@export var card_size := Vector2(0.5, 0.9)
## Сколько комков бродит друг относительно друга; 1 — один ком.
@export var lobes := 4
@export var lobe_spread := 0.55
## На ходу карточки отстают до этой доли следа — голова тянется, а не едет целиком.
@export var drag := 0.12
@export var spin := 0.35
@export var rng_seed := 7

var _offsets: Array[Vector3] = []
var _seeds := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _order: Array[int] = []
var _items: Array[Dictionary] = []
var _time := 0.0

@onready var _mover: SoulMover = get_parent() as SoulMover


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	multimesh.instance_count = count
	for i in count:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		_offsets.append(dir.normalized() * pow(rng.randf(), 0.6) * shape)
		_seeds.append(rng.randf())
		_sizes.append(rng.randf())
		_order.append(i)
		_items.append({})


func _process(delta: float) -> void:
	_time += delta
	for i in count:
		var s := _seeds[i]
		var wobble := Vector3(sin(_time * 0.9 + s * 6.0), sin(_time * 1.1 + s * 4.0), cos(_time * 0.8 + s * 5.0)) * 0.04
		var base := _mover.sample(_sizes[i] * drag)
		var pos := base + _lobe_center(i % maxi(lobes, 1)) + _offsets[i] * radius * (1.0 - lobe_spread * 0.4) + wobble
		var size := lerpf(card_size.x, card_size.y, _sizes[i])
		var core := 1.0 - _offsets[i].length() * 0.5
		var rot := s + _time * spin * 0.15 * (s - 0.5)
		_items[i] = {"xform": Transform3D(Basis.from_scale(Vector3.ONE * size), pos), "custom": Color(core, s, 1.0, rot)}
	_write_sorted()


func _lobe_center(k: int) -> Vector3:
	if lobes <= 1:
		return Vector3.ZERO
	var p := k * 2.1
	return Vector3(sin(_time * 0.37 + p * 1.3), 0.5 * sin(_time * 0.29 + p * 2.7), cos(_time * 0.31 + p * 0.9)) \
			* radius * lobe_spread * shape


## Прозрачные экземпляры MultiMesh не сортируются движком — рисуем дальние первыми сами.
func _write_sorted() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var eye := camera.global_position
		_order.sort_custom(func(a: int, b: int) -> bool:
			return (_items[a].xform as Transform3D).origin.distance_squared_to(eye) \
					> (_items[b].xform as Transform3D).origin.distance_squared_to(eye))
	for k in _order.size():
		var item := _items[_order[k]]
		multimesh.set_instance_transform(k, item.xform)
		multimesh.set_instance_custom_data(k, item.custom)
