extends MultiMeshInstance3D
## Клочья облика БФЖ по краям кадра от первого лица — вариант «карточки» витрины:
## карточки у самой камеры, каждая живёт несколько секунд, наплывает из-за края
## и тает, а новая встаёт в другом месте — край кадра дышит, а не стоит рамкой.
## Едут с камерой жёстко: двигается только сам дым, не поворот мыши.
## top_level, родитель — камера. [[Облик БФЖ]].

@export var count := 11
@export var depth := 0.35
## Насколько карточка выходит за край кадра, в долях полукадра: 1 — сам край.
@export var reach := Vector2(1.0, 1.4)
@export var size := Vector2(0.14, 0.3)
@export var life := Vector2(3.0, 6.5)
## Насколько низ кадра гуще верха: 0 — поровну.
@export_range(0.0, 1.0) var bottom_weight := 0.5

var _rng := RandomNumberGenerator.new()
var _cards: Array[Dictionary] = []
var _time := 0.0

@onready var _camera: Camera3D = get_parent() as Camera3D


func _ready() -> void:
	_rng.randomize()
	multimesh.instance_count = count
	for i in count:
		var card := {}
		_respawn(card)
		# Разбросать возраст, иначе все родятся и растают разом.
		card.age = _rng.randf() * float(card.life)
		_cards.append(card)
	set_instance_shader_parameter(&"billboard", true)


func _process(delta: float) -> void:
	_time += delta
	var half := _half_extents()
	var basis := _camera.global_basis
	var eye := _camera.global_position
	for i in count:
		var card := _cards[i]
		card.age = float(card.age) + delta
		if float(card.age) >= float(card.life):
			_respawn(card)
		var k := float(card.age) / float(card.life)
		var a := float(card.angle) + float(card.crawl) * k
		var r := lerpf(float(card.reach), float(card.reach) - 0.12, sin(k * PI))
		var local := Vector3(cos(a) * half.x * r, sin(a) * half.y * r, -depth)
		var fade := pow(sin(k * PI), 1.5)
		var xform := Transform3D(Basis.from_scale(Vector3.ONE * float(card.size)), eye + basis * local)
		multimesh.set_instance_transform(i, xform)
		multimesh.set_instance_custom_data(i, Color(0.0, float(card.seed), fade, float(card.spin)))


func _respawn(card: Dictionary) -> void:
	var angle := _rng.randf() * TAU
	# Низ и бока кадра гуще верха: сверху клочья реже, как дым, который стелется.
	while _rng.randf() > 1.0 - bottom_weight * maxf(sin(angle), 0.0):
		angle = _rng.randf() * TAU
	card.angle = angle
	card.crawl = _rng.randf_range(-0.25, 0.25)
	card.reach = _rng.randf_range(reach.x, reach.y)
	card.size = _rng.randf_range(size.x, size.y)
	card.life = _rng.randf_range(life.x, life.y)
	card.seed = _rng.randf()
	card.spin = _rng.randf()
	card.age = 0.0


func _half_extents() -> Vector2:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	var t := tan(deg_to_rad(_camera.fov) * 0.5) * depth
	if _camera.keep_aspect == Camera3D.KEEP_WIDTH:
		return Vector2(t, t / aspect)
	return Vector2(t * aspect, t)
