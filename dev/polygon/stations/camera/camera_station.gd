extends Node3D
## Станция «Камера от третьего лица»: трасса тесноты из настоящего кита коридоров, решётка на permeable, тела разных
## габаритов, цели для лучей и пульт режимов игровой камеры (C_ThirdPersonCamera игрока) в разделе «Полигон» меню отладки.
## Свой облик, тела и враги гаснут вблизи камеры сами (игра); проп и решётку, у которых растворения в игре пока нет,
## станция растворяет сама. Станция полигона: title, маркер Spawn, setup(polygon) — dev/polygon/polygon.gd.
## Вики: [[Полигон]], [[Камера от третьего лица]].

## Значения, по которым листают записи пульта.
const ARM_SCALES: Array[float] = [0.6, 0.8, 1.0, 1.5]
const SHOULDER_SCALES: Array[float] = [0.0, 0.5, 1.0, 1.5]
const PIVOT_LIFTS: Array[float] = [-0.2, -0.1, 0.0, 0.1]
const MIN_PIVOTS: Array[float] = [0.6, 0.9, 1.2]

@export var title := "Камера от третьего лица"
## Манекен-враг в коридоре: без C_EnemyInput стоит и не нападает.
@export var dummy_scene: PackedScene

var polygon: Node
var dummy: E_Enemy
## Сколько раз взяли цель за углом — счётчик на табличке.
var target_hits := 0

@onready var bodies: Node3D = %BodyRow


func setup(owner_polygon: Node) -> void:
	polygon = owner_polygon
	bodies.lay_bodies()
	_spawn_dummy()
	(%BodyConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: bodies.lay_bodies())
	(%TargetConsole as E_InteractableObject).interacted.connect(func(_e: Entity) -> void: _count_target())
	for root: Node in [%Props, %Grate]:
		_fade_under(root)


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


## Геометрии под [param root] — копии материалов, гаснущие вблизи камеры, как у тел и врагов (RS_EntityVisuals.ACTOR_FADE).
## У CSG материал в своём свойстве, а не в поверхностях — копию кладём в material_override.
static func _fade_under(root: Node) -> void:
	RS_EntityVisuals.fade_near_camera(root, BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER,
		RS_EntityVisuals.ACTOR_FADE.x, RS_EntityVisuals.ACTOR_FADE.y)
	for csg: CSGPrimitive3D in root.find_children("*", "CSGPrimitive3D", true, false):
		var material := csg.get(&"material") as BaseMaterial3D
		if material == null:
			continue
		var copy := material.duplicate() as BaseMaterial3D
		copy.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		copy.distance_fade_min_distance = RS_EntityVisuals.ACTOR_FADE.x
		copy.distance_fade_max_distance = RS_EntityVisuals.ACTOR_FADE.y
		csg.material_override = copy


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
