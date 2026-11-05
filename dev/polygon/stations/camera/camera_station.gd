extends Node3D
## Станция «Камера от третьего лица»: трасса тесноты из настоящего кита коридоров, решётка на permeable, тела разных
## габаритов, цели для лучей и прототип камеры (third_person_rig) с пультом режимов в разделе «Полигон» меню отладки.
## Станция полигона: title, маркер Spawn, setup(polygon) — dev/polygon/polygon.gd. Вики: [[Полигон]], [[Вид от третьего лица]].

const Rig := preload("res://dev/polygon/stations/camera/third_person_rig.gd")
## Значения, по которым листают записи пульта.
const ARM_SCALES: Array[float] = [0.6, 0.8, 1.0, 1.5]
const SHOULDER_SCALES: Array[float] = [0.0, 0.5, 1.0, 1.5]
const FOVS: Array[float] = [70.0, 80.0, 90.0, 103.0]
const PIVOT_LIFTS: Array[float] = [-0.2, -0.1, 0.0, 0.1]
const MIN_PIVOTS: Array[float] = [0.6, 0.9, 1.2]
const OWN_FADE_RANGES: Array[Vector2] = [Vector2(0.3, 1.0), Vector2(0.6, 1.6), Vector2(1.0, 2.5)]
## Чужие объекты гаснут ближе этого: ближе x их не видно, дальше y они плотные.
const OTHERS_FADE_RANGE := Vector2(0.4, 1.4)

@export var title := "Камера от третьего лица"
## Манекен-враг в коридоре: без C_EnemyInput стоит и не нападает.
@export var dummy_scene: PackedScene
## Как гаснут вблизи чужие объекты станции: индекс в Rig.FADE_MODES.
@export var others_fade := 2

var polygon: Node
var dummy: E_Enemy
## Сколько раз взяли цель за углом — счётчик на табличке.
var target_hits := 0
## GeometryInstance3D → что вернуть, когда дизер чужих выключат или сменят.
var _faded := {}
## Интерполяция физики до прихода на станцию — её вернёт уход.
var _interpolation_before := false

@onready var rig: Node3D = %ThirdPersonRig
@onready var bodies: Node3D = %BodyRow


func setup(owner_polygon: Node) -> void:
	polygon = owner_polygon
	bodies.laid.connect(func(_body: E_Body) -> void: refade())
	bodies.lay_bodies()
	_spawn_dummy()
	(%BodyConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: bodies.lay_bodies())
	(%TargetConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: _count_target())
	refade()


## Игрока перенесли на станцию — смотреть от третьего лица. Интерполяция физики включается сразу: без неё риг,
## который двигается только в физкадре, на фоне камеры дёргается (карточка, шаг 2). Пульт её выключает для сравнения.
func arrive() -> void:
	if rig.active:
		return
	_interpolation_before = get_tree().physics_interpolation
	get_tree().physics_interpolation = true
	var player := E_Player.find() as Node
	if player != null:
		player.reset_physics_interpolation()
	rig.set_active(true)


## Игрока перенесли на другую станцию — кадр снова у камеры игрока, интерполяция — какой была до станции.
func depart() -> void:
	if not rig.active:
		return
	get_tree().physics_interpolation = _interpolation_before
	rig.set_active(false)


## Пульт режимов: записи раздела «Полигон» меню отладки, каждая листает своё значение и отчитывается строкой.
func debug_entries() -> Array[Dictionary]:
	var on := "вкл" if rig.active else "выкл"
	return [
		{"title": "Камера от третьего лица: %s" % on, "call": toggle_camera},
		{"title": "Плечо: %s" % _side_name(), "call": swap_side},
		{"title": "Смена плеча у стены: %s" % ("вкл" if rig.auto_side else "выкл"), "call": toggle_auto_side},
		{"title": "Длина плеча: ×%s роста" % rig.arm_scale, "call": next_arm},
		{"title": "Сдвиг вбок: ×%s" % rig.shoulder_scale, "call": next_shoulder},
		{"title": "Опора от глаз: %s роста" % rig.pivot_lift, "call": next_pivot_lift},
		{"title": "Опора не ниже: %s м" % rig.min_pivot, "call": next_min_pivot},
		{"title": "Угол обзора: %s°" % rig.camera.fov, "call": next_fov},
		{"title": "Интерполяция физики: %s" % ("вкл" if get_tree().physics_interpolation else "выкл"), "call": toggle_interpolation},
		{"title": "Дизер своего облика: %s" % Rig.FADE_NAMES[rig.own_fade], "call": next_own_fade},
		{"title": "Дизер облика: %s–%s м" % [rig.own_fade_min, rig.own_fade_max], "call": next_own_range},
		{"title": "Дизер чужих: %s" % Rig.FADE_NAMES[others_fade], "call": next_others_fade},
		{"title": "Положить тела", "call": func() -> String: return "положено тел: %d" % bodies.lay_bodies()},
	]


func toggle_camera() -> String:
	if rig.active:
		depart()
	else:
		arrive()
	return "камера от третьего лица: %s" % ("вкл" if rig.active else "выкл")


func swap_side() -> String:
	rig.side = -rig.side
	return "плечо: %s" % _side_name()


func toggle_auto_side() -> String:
	rig.auto_side = not rig.auto_side
	return "смена плеча у стены: %s" % ("вкл" if rig.auto_side else "выкл")


func next_arm() -> String:
	rig.arm_scale = _next(ARM_SCALES, rig.arm_scale)
	return "длина плеча: ×%s роста (не короче %s м)" % [rig.arm_scale, rig.min_arm]


func next_shoulder() -> String:
	rig.shoulder_scale = _next(SHOULDER_SCALES, rig.shoulder_scale)
	return "сдвиг вбок: ×%s" % rig.shoulder_scale


func next_pivot_lift() -> String:
	rig.pivot_lift = _next(PIVOT_LIFTS, rig.pivot_lift)
	return "опора от глаз: %s роста (минус — ниже глаз)" % rig.pivot_lift


func next_min_pivot() -> String:
	rig.min_pivot = _next(MIN_PIVOTS, rig.min_pivot)
	return "опора не ниже %s м над подошвой" % rig.min_pivot


func next_fov() -> String:
	rig.camera.fov = _next(FOVS, rig.camera.fov)
	return "угол обзора: %s° по горизонтали" % rig.camera.fov


## Интерполяция — настройка дерева, а не сцены: уходя, полигон возвращает её к проектной.
func toggle_interpolation() -> String:
	var tree := get_tree()
	tree.physics_interpolation = not tree.physics_interpolation
	var player := E_Player.find() as Node
	if player != null:
		player.reset_physics_interpolation()
	return "интерполяция физики: %s" % ("вкл" if tree.physics_interpolation else "выкл")


func next_own_fade() -> String:
	rig.own_fade = (rig.own_fade + 1) % Rig.FADE_MODES.size()
	rig.refresh()
	return "дизер своего облика: %s" % Rig.FADE_NAMES[rig.own_fade]


func next_own_range() -> String:
	var at := OWN_FADE_RANGES.find(Vector2(rig.own_fade_min, rig.own_fade_max))
	var range_ := OWN_FADE_RANGES[(at + 1) % OWN_FADE_RANGES.size()]
	rig.own_fade_min = range_.x
	rig.own_fade_max = range_.y
	rig.refresh()
	return "дизер облика: невидим ближе %s м, плотный дальше %s м" % [range_.x, range_.y]


func next_others_fade() -> String:
	others_fade = (others_fade + 1) % Rig.FADE_MODES.size()
	refade()
	return "дизер чужих: %s" % Rig.FADE_NAMES[others_fade]


## Чужие объекты станции — тела, манекен, пропы, решётка — копиями материалов с дизером; прежние копии снимаются.
func refade() -> void:
	for geo: Variant in _faded:
		if is_instance_valid(geo):
			Rig.restore(geo as GeometryInstance3D, _faded[geo])
	_faded.clear()
	var mode: int = Rig.FADE_MODES[others_fade]
	if mode == BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return
	for root: Node in [bodies, %Dummies, %Props, %Grate]:
		for node in root.find_children("*", "GeometryInstance3D", true, false):
			var geo := node as GeometryInstance3D
			var saved := {"shadow": geo.cast_shadow, "override": geo.material_override, "surfaces": []}
			Rig.fade_geometry(geo, saved, mode, OTHERS_FADE_RANGE.x, OTHERS_FADE_RANGE.y)
			_faded[geo] = saved


func _spawn_dummy() -> void:
	var enemy := dummy_scene.instantiate() as E_Enemy
	# Место до add_child: коллайдер регистрируется там, где узел вошёл в дерево.
	enemy.transform = (%DummyPoint as Node3D).transform
	(%Dummies as Node3D).add_child(enemy)
	ECS.world.add_entity(enemy)
	# Без C_EnemyInput манекена не берут ни S_EnemyAI, ни S_Walk (как на беговой дорожке станции hound).
	enemy.remove_component(C_EnemyInput)
	dummy = enemy


func _count_target() -> void:
	target_hits += 1
	(%Counter as Label3D).text = "Цель за углом\nвзята: %d" % target_hits


func _side_name() -> String:
	return "правое" if rig.side > 0.0 else "левое"


static func _next(values: Array[float], current: float) -> float:
	var at := values.find(current)
	return values[(at + 1) % values.size()]
