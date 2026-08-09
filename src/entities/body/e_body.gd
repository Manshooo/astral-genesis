# res://src/entities/body/e_body.gd
## Инертное тело/труп — первая цель захвата БФЖ. ИИ нет: тело статично, его задача —
## дать S_BodySnatch что вселить. Характеристики (C_Health, C_BodySnatchable)
## настраиваются через component_resources в сцене/инспекторе, а не в коде, чтобы
## пресеты тел тюнились дизайнером.
##
## Коллайдер лежит на слое enemies (layer_3, collision_layer = 1 << 2), куда смотрит
## луч захвата S_BodySnatch; в игрока и интерактивы луч не попадает.
##
## СОГЛАШЕНИЕ О ТОЧКЕ ОТСЧЁТА: origin тела — его ПОДОШВА. В сценах комнат тела
## ставятся на y = 0, а капсула коллайдера поднята на полроста; меш тоже растёт
## от origin вверх. Игрок живёт по другому соглашению (origin в центре капсулы),
## и вселение переводит одно в другое через E_Player.foot_offset — сдвинув
## коллайдер тела в центр, вы сломаете именно это место.
@tool
class_name E_Body
extends Entity


## Облик тела: меш и переопределение материала его основной геометрии.
##
## Источник правды о внешности — СЦЕНА тела, а не отдельно объявленные данные:
## меш, который игрок видел в мире, и меш, который он получает при вселении,
## обязаны быть одним и тем же, иначе первая же правка сцены их разведёт. Какой
## узел считается геометрией, решает RS_EntityVisuals — то же правило, по
## которому O_BodyVisual потом надевает этот облик на риг.
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


## Характеристики тела из его сцены — для восстановления после загрузки, где
## инстанса тела уже нет. Читаем component_resources, а не get_component:
## detached-инстанс компоненты ещё «не разложил», но @export-массив доступен
## сразу после instantiate (тот же приём, что в RS_RoomLayout.has_door_slot).
##
## null — в сцене нет C_BodySnatchable, то есть это не тело.
static func snatchable_of_scene(path: String) -> C_BodySnatchable:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null

	var probe := scene.instantiate()
	var found: C_BodySnatchable = null
	var entity := probe as Entity
	if entity:
		found = entity.get_component(C_BodySnatchable) as C_BodySnatchable
		if found == null:
			for component in entity.component_resources:
				if component is C_BodySnatchable:
					found = component as C_BodySnatchable
					break
	# Компонент — Resource и переживёт освобождение узла, но это ЧУЖОЙ ресурс из
	# сцены: дублируем, чтобы правки статов не утекли в общий для всех тел пресет.
	var copy := found.duplicate() as C_BodySnatchable if found else null
	probe.free()
	return copy
