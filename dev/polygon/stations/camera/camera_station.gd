extends Node3D
## Станция «Камера от третьего лица»: трасса тесноты из настоящего кита коридоров, решётка на permeable, тела разных
## габаритов, цели для лучей и пульт режимов игровой камеры (C_ThirdPersonCamera игрока) в разделе «Полигон» меню отладки.
## Растворение вблизи станция пока ведёт сама — в игре его нет до шага 5 карточки.
## Станция полигона: title, маркер Spawn, setup(polygon) — dev/polygon/polygon.gd. Вики: [[Полигон]], [[Вид от третьего лица]].

## Значения, по которым листают записи пульта.
const ARM_SCALES: Array[float] = [0.6, 0.8, 1.0, 1.5]
const SHOULDER_SCALES: Array[float] = [0.0, 0.5, 1.0, 1.5]
const PIVOT_LIFTS: Array[float] = [-0.2, -0.1, 0.0, 0.1]
const MIN_PIVOTS: Array[float] = [0.6, 0.9, 1.2]
const OWN_FADE_RANGES: Array[Vector2] = [Vector2(0.3, 1.0), Vector2(0.6, 1.6), Vector2(1.0, 2.5)]
## Чужие объекты гаснут ближе этого: ближе x их не видно, дальше y они плотные.
const OTHERS_FADE_RANGE := Vector2(0.4, 1.4)
const FADE_MODES: Array[int] = [
	BaseMaterial3D.DISTANCE_FADE_DISABLED,
	BaseMaterial3D.DISTANCE_FADE_OBJECT_DITHER,
	BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER,
]
const FADE_NAMES: Array[String] = ["выкл", "объект", "пиксель"]

@export var title := "Камера от третьего лица"
## Манекен-враг в коридоре: без C_EnemyInput стоит и не нападает.
@export var dummy_scene: PackedScene
## Как гаснут вблизи чужие объекты станции и свой облик: индексы в FADE_MODES.
@export var others_fade := 2
@export var own_fade := 1
@export var own_fade_range := Vector2(0.6, 1.6)

var polygon: Node
var dummy: E_Enemy
## Сколько раз взяли цель за углом — счётчик на табличке.
var target_hits := 0
## GeometryInstance3D → что вернуть, когда дизер сменят: чужие объекты и надетый облик порознь.
var _faded := {}
var _worn_faded := {}
## Облик, которому уже выданы копии материалов.
var _worn: Node

@onready var bodies: Node3D = %BodyRow


func setup(owner_polygon: Node) -> void:
	polygon = owner_polygon
	bodies.laid.connect(func(_body: E_Body) -> void: refade())
	bodies.lay_bodies()
	_spawn_dummy()
	(%BodyConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: bodies.lay_bodies())
	(%TargetConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: _count_target())
	refade()


## Свой облик гаснет копиями материалов; надетый облик сменился — копии выдаются заново.
func _process(_delta: float) -> void:
	var player := E_Player.find() as Node
	var worn := player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE)) if player != null else null
	if worn == _worn:
		return
	_unfade(_worn_faded)
	_worn = worn
	if worn != null:
		_fade_under(worn, _worn_faded, FADE_MODES[own_fade], own_fade_range)


## Пульт режимов: записи раздела «Полигон» меню отладки, каждая листает своё значение и отчитывается строкой.
func debug_entries() -> Array[Dictionary]:
	var view := _view()
	if view == null:
		return []
	return [
		{"title": "Плечо: %s" % _side_name(view), "call": swap_side},
		{"title": "Смена плеча у стены: %s" % ("вкл" if view.auto_side else "выкл"), "call": toggle_auto_side},
		{"title": "Длина плеча: ×%s роста" % view.arm_scale, "call": next_arm},
		{"title": "Сдвиг вбок: ×%s" % view.shoulder_scale, "call": next_shoulder},
		{"title": "Опора от глаз: %s роста" % view.pivot_lift, "call": next_pivot_lift},
		{"title": "Опора не ниже: %s м" % view.min_pivot, "call": next_min_pivot},
		{"title": "Интерполяция физики: %s" % ("вкл" if get_tree().physics_interpolation else "выкл"), "call": toggle_interpolation},
		{"title": "Дизер своего облика: %s" % FADE_NAMES[own_fade], "call": next_own_fade},
		{"title": "Дизер облика: %s–%s м" % [own_fade_range.x, own_fade_range.y], "call": next_own_range},
		{"title": "Дизер чужих: %s" % FADE_NAMES[others_fade], "call": next_others_fade},
		{"title": "Положить тела", "call": func() -> String: return "положено тел: %d" % bodies.lay_bodies()},
	]


func swap_side() -> String:
	var view := _view()
	view.side = -view.side
	return "плечо: %s" % _side_name(view)


func toggle_auto_side() -> String:
	var view := _view()
	view.auto_side = not view.auto_side
	return "смена плеча у стены: %s" % ("вкл" if view.auto_side else "выкл")


func next_arm() -> String:
	var view := _view()
	view.arm_scale = _next(ARM_SCALES, view.arm_scale)
	return "длина плеча: ×%s роста (не короче %s м)" % [view.arm_scale, view.min_arm]


func next_shoulder() -> String:
	var view := _view()
	view.shoulder_scale = _next(SHOULDER_SCALES, view.shoulder_scale)
	return "сдвиг вбок: ×%s" % view.shoulder_scale


func next_pivot_lift() -> String:
	var view := _view()
	view.pivot_lift = _next(PIVOT_LIFTS, view.pivot_lift)
	return "опора от глаз: %s роста (минус — ниже глаз)" % view.pivot_lift


func next_min_pivot() -> String:
	var view := _view()
	view.min_pivot = _next(MIN_PIVOTS, view.min_pivot)
	return "опора не ниже %s м над подошвой" % view.min_pivot


## Интерполяция — настройка дерева, а не сцены: уходя, полигон возвращает её к проектной.
func toggle_interpolation() -> String:
	var tree := get_tree()
	tree.physics_interpolation = not tree.physics_interpolation
	var player := E_Player.find() as Node
	if player != null:
		player.reset_physics_interpolation()
	return "интерполяция физики: %s" % ("вкл" if tree.physics_interpolation else "выкл")


func next_own_fade() -> String:
	own_fade = (own_fade + 1) % FADE_MODES.size()
	_rewear()
	return "дизер своего облика: %s" % FADE_NAMES[own_fade]


func next_own_range() -> String:
	var at := OWN_FADE_RANGES.find(own_fade_range)
	own_fade_range = OWN_FADE_RANGES[(at + 1) % OWN_FADE_RANGES.size()]
	_rewear()
	return "дизер облика: невидим ближе %s м, плотный дальше %s м" % [own_fade_range.x, own_fade_range.y]


func next_others_fade() -> String:
	others_fade = (others_fade + 1) % FADE_MODES.size()
	refade()
	return "дизер чужих: %s" % FADE_NAMES[others_fade]


## Чужие объекты станции — тела, манекен, пропы, решётка — копиями материалов с дизером; прежние копии снимаются.
func refade() -> void:
	_unfade(_faded)
	for root: Node in [bodies, %Dummies, %Props, %Grate]:
		_fade_under(root, _faded, FADE_MODES[others_fade], OTHERS_FADE_RANGE)


## Копия материала с дизером по расстоянию до камеры; общий материал не трогается. Не BaseMaterial3D — как есть.
static func faded_copy(material: Material, mode: int, near: float, far: float) -> Material:
	var base := material as BaseMaterial3D
	if base == null:
		return material
	var copy := base.duplicate() as BaseMaterial3D
	copy.distance_fade_mode = mode as BaseMaterial3D.DistanceFadeMode
	copy.distance_fade_min_distance = near
	copy.distance_fade_max_distance = far
	return copy


## Всей геометрии под [param root] — копии материалов с дизером; что было, пишется в [param saved].
static func _fade_under(root: Node, saved: Dictionary, mode: int, range_: Vector2) -> void:
	if mode == BaseMaterial3D.DISTANCE_FADE_DISABLED:
		return
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geo := node as GeometryInstance3D
		var was := {"override": geo.material_override, "surfaces": []}
		saved[geo] = was
		if geo.material_override != null:
			geo.material_override = faded_copy(geo.material_override, mode, range_.x, range_.y)
			continue
		# У CSG материал в своём свойстве, а не в поверхностях: копию кладём поверх, в material_override.
		var csg := geo as CSGPrimitive3D
		if csg != null and csg.get(&"material") is Material:
			geo.material_override = faded_copy(csg.get(&"material"), mode, range_.x, range_.y)
			continue
		var mesh := geo as MeshInstance3D
		if mesh == null:
			continue
		for i in mesh.get_surface_override_material_count():
			was["surfaces"].append(mesh.get_surface_override_material(i))
			var active_material := mesh.get_active_material(i)
			if active_material != null:
				mesh.set_surface_override_material(i, faded_copy(active_material, mode, range_.x, range_.y))


## Вернуть геометрии то, что записал _fade_under.
static func _unfade(saved: Dictionary) -> void:
	for geo: Variant in saved:
		if not is_instance_valid(geo):
			continue
		var node := geo as GeometryInstance3D
		var was: Dictionary = saved[geo]
		node.material_override = was["override"]
		var mesh := node as MeshInstance3D
		var surfaces: Array = was["surfaces"]
		if mesh != null:
			for i in surfaces.size():
				mesh.set_surface_override_material(i, surfaces[i])
	saved.clear()


## Свой облик — заново, с нынешним режимом и расстояниями.
func _rewear() -> void:
	_unfade(_worn_faded)
	_worn = null


func _view() -> C_ThirdPersonCamera:
	var player := E_Player.find()
	return player.get_component(C_ThirdPersonCamera) as C_ThirdPersonCamera if player != null else null


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


static func _side_name(view: C_ThirdPersonCamera) -> String:
	return "правое" if view.side > 0.0 else "левое"


static func _next(values: Array[float], current: float) -> float:
	var at := values.find(current)
	return values[(at + 1) % values.size()]
