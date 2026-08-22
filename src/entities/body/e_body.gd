# res://src/entities/body/e_body.gd
## Инертное тело/труп — первая цель захвата БФЖ. ИИ нет: тело статично, его задача —
## дать S_BodySnatch что вселить. Характеристики (C_Health, C_BodyDecay, C_Walk,
## C_Jump) настраиваются через component_resources в сцене/инспекторе, а не в
## коде, чтобы пресеты тел тюнились дизайнером. Эталонный набор лежит в
## e_body.tscn — новое тело делается копией этой сцены (или шаблоном «Труп
## (захват)» в доке «Шаблоны»), а не набором компонентов из выпадашки.
##
## Коллайдер лежит на слое enemies (layer_3, collision_layer = 1 << 2), куда смотрит
## луч S_SnatchTargetDetector; в игрока и интерактивы луч не попадает.
##
## СОГЛАШЕНИЕ О ТОЧКЕ ОТСЧЁТА: origin тела — его ПОДОШВА. Так авторены модели
## (и меш, и арматура), так тела стоят в комнатах — на y = 0. Игрок живёт по
## другому соглашению (origin в ЦЕНТРЕ его коллайдера), и оба перехода между ними —
## посадка рига при вселении и посадка облика — идут через E_Player.foot_offset.
@tool
class_name E_Body
extends Entity


## Облик тела: меш, переопределение материала и трансформ его основной геометрии.
##
## Источник правды о внешности — СЦЕНА тела, а не отдельно объявленные данные:
## меш, который игрок видел в мире, и меш, который он получает при вселении,
## обязаны быть одним и тем же, иначе первая же правка сцены их разведёт. Какой
## узел считается геометрией, решает RS_EntityVisuals — то же правило, по
## которому O_BodyVisual потом надевает этот облик на риг.
##
## Трансформ берём относительно КОРНЯ тела — он же «относительно подошвы» (см.
## соглашение выше). Собственный поворот тела в комнате сюда не попадает:
## направление ригу задаёт мышь игрока, а не поза трупа.
##
## null — у тела нет визуала (переносить нечего).
static func visual_of(body: Node) -> C_BodyVisual:
	var entity := body as Entity
	if entity == null:
		return null
	var geo := RS_EntityVisuals.primary(entity) as MeshInstance3D
	if geo == null or geo.mesh == null:
		return null

	var visual := C_BodyVisual.new()
	visual.mesh = geo.mesh
	visual.material_override = geo.material_override
	visual.mesh_transform = RS_EntityVisuals.transform_relative_to(geo, entity)
	return visual


## То же, но по пути сцены — для восстановления облика из сейва, где инстанса
## тела уже нет: захват его поглотил, а комплекс не сериализуется покомнатно.
## Инстанцируем, читаем, освобождаем; ресурсы меша переживают освобождение узла,
## они считаются по ссылкам.
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


## Имя узла-маркера, задающего уровень глаз тела. Ищется на любой глубине —
## чтобы маркер можно было повесить дочерним к BoneAttachment3D на кость head,
## когда тела станут анимированными, не меняя ни контракта, ни этого кода.
const EYES_MARKER := "Eyes"


## Физическая форма тела: габарит коллизии и уровень глаз. Всё, чем тело
## упирается в мир и откуда смотрит.
##
## Габарит берём с коллайдера, лежащего ПРЯМО НА корне тела, а не с любого
## CollisionShape3D в поддереве: у ригов их десятки на костях
## (PhysicalBoneSimulator3D), и «первый попавшийся» дал бы душе форму
## предплечья. Корневой коллайдер — тот самый, по которому в тело бьёт луч
## захвата, так что подсвеченный игроку габарит и надетый им — одно и то же.
##
## null — тело формы не несёт (переносить нечего, риг остаётся призрачным).
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


## То же, но по пути сцены — для восстановления после загрузки, где инстанса тела
## уже нет (захват его поглотил). Тот же приём, что visual_of_scene.
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


## Форма коллизии с коллайдера самого тела. Только прямые дети корня — см.
## form_of про то, почему поддерево не годится.
static func _root_shape(entity: Entity) -> Shape3D:
	for child in entity.get_children():
		var collision := child as CollisionShape3D
		if collision and collision.shape:
			return collision.shape
	return null


## Высота глаз над подошвой, или -1, если маркера нет.
##
## Берём Y относительно КОРНЯ тела, а не global_position: форму читают в том
## числе с detached-инстанса сцены (form_of_scene), а Node3D узнаёт свою
## глобальную позицию только внутри SceneTree. Та же причина, что у
## RS_EntityVisuals.transform_relative_to — им и считаем.
static func _eye_height(entity: Entity) -> float:
	var found := entity.find_children(EYES_MARKER, "Node3D", true, false)
	if found.is_empty():
		return -1.0
	return RS_EntityVisuals.transform_relative_to(found[0], entity).origin.y


## Что тело отдаёт душе при вселении: все его компоненты-характеристики
## (C_BodyTrait) плюс C_Health.
##
## Прочность перечислена отдельно, потому что C_Health — общий компонент всего
## живого, а не характеристика именно тела: стена с прочностью не трейт. Это
## единственное исключение, и оно одно на весь проект — остальное расширяется
## наследованием от C_BodyTrait, без правки этого файла.
##
## Возвращаются КОПИИ: компонент в сцене — ресурс, общий для всех инстансов
## пресета, и надеть оригинал значило бы, что урон по одному телу правит числа
## всех остальных.
static func traits_of(body: Node) -> Array[Component]:
	var entity := body as Entity
	if entity == null:
		return []
	return _wearable(entity.components.values())


## То же, но по пути сцены — для восстановления после загрузки, где инстанса тела
## уже нет: захват его поглотил, а комплекс не сериализуется покомнатно.
##
## Читаем component_resources, а не components: detached-инстанс компоненты ещё
## «не разложил» (это делает мир при add_entity), но @export-массив доступен
## сразу после instantiate — тот же приём, что в RS_RoomLayout.has_door_slot.
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


static func _wearable(source: Array) -> Array[Component]:
	var out: Array[Component] = []
	for component in source:
		if component is C_BodyTrait or component is C_Health:
			out.append(component.duplicate() as Component)
	return out
