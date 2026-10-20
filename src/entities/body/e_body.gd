# res://src/entities/body/e_body.gd
## Инертное тело/труп — цель захвата БФЖ; характеристики — в component_resources сцены (новое тело — копия e_body.tscn).
## Коллайдер на слое enemies (луч S_SnatchTargetDetector). origin тела — ПОДОШВА (у игрока — центр коллайдера;
## переходы идут через E_Player.foot_offset); лицом тело смотрит в −Z, доворот модели — под корнем. Вики: [[Захват тела]].
@tool
class_name E_Body
extends Entity

## Ключ ПЕРЕВОДА имени тела («BODY_WALKER»): сводка переживает смену языка. Свойство сцены, не компонент.
@export var display_name_key: StringName = &""

## Класс тела по шкале угроз L0..L5: от него очки души (RS_SoulPointsTable) и зачёт условию навыка.
## Свойство сцены: после захвата тела нет, класс спрашивают по пути сцены (class_of_scene).
@export_range(0, 5) var body_class: int = 0


## Облик тела (меш, материал, трансформ) из СЦЕНЫ — единственный источник правды, правило геометрии у
## RS_EntityVisuals. Трансформ относительно корня (подошвы): поворот МОДЕЛИ внутри сцены входит, поворот тела в комнате — нет.
## Подошву считаем по форме того же тела (C_BodyVisual.foot_offset). null — визуала нет.
static func visual_of(body: Node) -> C_BodyVisual:
	var entity := body as Entity
	if entity == null:
		return null
	var geo := RS_EntityVisuals.primary(entity) as MeshInstance3D
	if geo == null or geo.mesh == null:
		return null

	var form := form_of(entity)
	var visual := C_BodyVisual.new()
	visual.mesh = geo.mesh
	visual.material_override = geo.material_override
	visual.mesh_transform = RS_EntityVisuals.transform_relative_to(geo, entity)
	visual.foot_offset = form.foot_offset() if form else Vector3.ZERO
	return visual


## То же по пути сцены — для восстановления из сейва, где инстанса уже нет.
static func visual_of_scene(path: String) -> C_BodyVisual:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null

	var probe := scene.instantiate()
	var visual := visual_of(probe)
	probe.free()
	return visual


## Имя узла-маркера уровня глаз; ищется на любой глубине (под BoneAttachment3D на кости head).
const EYES_MARKER := "Eyes"


## Форма тела: габарит и уровень глаз. Габарит — с коллайдера ПРЯМО на корне (у ригов десятки на костях
## PhysicalBoneSimulator3D); это тот же коллайдер, по которому бьёт луч захвата. null — формы нет.
static func form_of(body: Node) -> C_BodyForm:
	var entity := body as Entity
	if entity == null:
		return null

	var form := C_BodyForm.new()
	form.shape = _root_shape(entity)
	form.eye_height = _eye_height(entity)
	if form.shape == null and form.eye_height < 0.0:
		return null
	return form


## То же по пути сцены.
static func form_of_scene(path: String) -> C_BodyForm:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null

	var probe := scene.instantiate()
	var form := form_of(probe)
	probe.free()
	return form


## Форма коллизии с коллайдера самого тела (только прямые дети корня, см. form_of).
static func _root_shape(entity: Entity) -> Shape3D:
	for child in entity.get_children():
		var collision := child as CollisionShape3D
		if collision and collision.shape:
			return collision.shape
	return null


## Высота глаз над подошвой или -1. Y относительно КОРНЯ: detached-инстанс global_position не знает.
static func _eye_height(entity: Entity) -> float:
	var found := entity.find_children(EYES_MARKER, "Node3D", true, false)
	if found.is_empty():
		return -1.0
	return RS_EntityVisuals.transform_relative_to(found[0], entity).origin.y


## Что тело отдаёт душе: все C_BodyTrait плюс C_Health (общий компонент всего живого — единственное исключение).
## Возвращаются КОПИИ: компонент в сцене — общий ресурс пресета.
static func traits_of(body: Node) -> Array[Component]:
	var entity := body as Entity
	if entity == null:
		return []
	return _wearable(entity.components.values())


## То же по пути сцены. Читаем component_resources: detached-инстанс компоненты ещё не разложил, но @export-массив доступен.
static func traits_of_scene(path: String) -> Array[Component]:
	if path.is_empty() or not ResourceLoader.exists(path):
		return []
	var scene := load(path) as PackedScene
	if scene == null:
		return []

	var probe := scene.instantiate()
	var entity := probe as Entity
	var found: Array[Component] = _wearable(entity.component_resources) if entity else []
	# Компоненты — Resource и переживают освобождение узла (считаются по ссылкам).
	probe.free()
	return found


## Ключ имени тела по пути сцены; пустой — не ошибка (прочерк в сводке).
static func name_key_of_scene(path: String) -> StringName:
	if path.is_empty() or not ResourceLoader.exists(path):
		return &""
	var scene := load(path) as PackedScene
	if scene == null:
		return &""

	var probe := scene.instantiate()
	var body := probe as E_Body
	var key: StringName = body.display_name_key if body else &""
	probe.free()
	return key


## Класс тела по пути сцены; 0, если сцены нет: неизвестное тело не приносит больше очков.
static func class_of_scene(path: String) -> int:
	if path.is_empty() or not ResourceLoader.exists(path):
		return 0
	var scene := load(path) as PackedScene
	if scene == null:
		return 0

	var probe := scene.instantiate()
	var body := probe as E_Body
	var body_class_value: int = body.body_class if body else 0
	probe.free()
	return body_class_value


## Носится ли компонент телом — ЕДИНСТВЕННОЕ определение: им надевают (S_BodySnatch), снимают (O_ExpelFromBody) и читают сцену.
static func is_wearable(component: Object) -> bool:
	return component is C_BodyTrait or component is C_Health


## Характеристики, надетые на entity сейчас, — оригиналы (снимают по типу); список заранее, снятие правит components.
static func worn_by(entity: Entity) -> Array[Component]:
	var found: Array[Component] = []
	for component in entity.components.values():
		if is_wearable(component):
			found.append(component as Component)
	return found


static func _wearable(source: Array) -> Array[Component]:
	var out: Array[Component] = []
	for component in source:
		if is_wearable(component):
			out.append(component.duplicate() as Component)
	return out
