## Система: рисует обводку выделенного объекта постэффектом по экранной маске.
##
## Схема из трёх шагов. (1) Меши выделенной сущности стоят на отдельном слое
## видимости — их туда переводит O_OutlineVisual. (2) Здесь этот слой рендерится
## в маску: SubViewport с камерой-двойником, у которой cull_mask ровно один бит,
## поэтому в кадр не попадает вообще ничего, кроме выделенного объекта. (3) По
## маске полноэкранный шейдер считает контур (outline_mask.gdshader).
##
## Почему не material_overlay, как было раньше: контур, выдавленный из самой
## геометрии, наследует её толщину (у мелких деталей тоньше, на плоскости
## пропадает), обводит составной объект по частям и мерцает без material_override.
## Маска ничего этого не знает — она плоская.
##
## Цена ограничена с двух сторон, потому что полноэкранный проход ради подсветки
## одного объекта — главный риск этого подхода. Пока ничего не выделено, маска
## переведена в UPDATE_DISABLED и не рендерится вовсе, а оверлей скрыт. Когда
## выделено — шейдер гоняется не по всему экрану, а по прямоугольнику, в который
## объект проецируется (плюс запас на толщину).
class_name S_OutlineMask
extends System

## Слой холста для оверлея. Ниже HUD (у него layer = -1), но выше 3D: обводка
## относится к миру, а не к интерфейсу, и подсказка над ней перекрывать её не
## должна наоборот.
const OVERLAY_CANVAS_LAYER := -2

const OVERLAY_MATERIAL: ShaderMaterial = preload(
	"res://assets/shared/materials/outline_mask.tres"
)

## Запас вокруг проекции объекта, px. Прямоугольник ножниц обязан быть шире самой
## толстой обводки, иначе она обрежется ровно по краю силуэта.
const RECT_MARGIN := 8.0

var _mask: SubViewport
var _mask_camera: Camera3D
var _overlay: ColorRect


## process_empty — не оптимизация, а условие работы: гасить обводку надо ровно
## тогда, когда выделенного объекта не осталось, то есть когда выборка пуста.
## Без этого флага GECS в такой кадр систему не зовёт, и последний контур завис
## бы на экране навсегда.
func setup() -> void:
	process_empty = true
	_build_nodes()


func query() -> QueryBuilder:
	return q.with_all([C_Highlighted])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if entities.is_empty() or camera == null or _mask == null:
		_set_active(false)
		return

	var rect := _screen_rect(entities, camera)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		# Объект есть, но на экране его нет (весь за спиной или за краем кадра) —
		# рисовать нечего, и маску гонять незачем.
		_set_active(false)
		return

	_sync_camera(camera)
	_sync_size()
	_overlay.position = rect.position
	_overlay.size = rect.size
	_set_active(true)


## Узлы строятся кодом, а не сценой: это механизм, а не авторский контент —
## настраивать в редакторе тут нечего, кроме цвета и толщины, а они лежат в
## outline_mask.tres. Сцена же требовала бы держать её в актуальном состоянии
## руками (размер вьюпорта, cull_mask, окружение), причём любая её правка ломала
## бы маску молча.
func _build_nodes() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "OutlineCanvas"
	canvas.layer = OVERLAY_CANVAS_LAYER
	add_child(canvas)

	_overlay = ColorRect.new()
	_overlay.name = "OutlineOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	# Копия, а не сам ресурс: в материал пишется ViewportTexture конкретного
	# прогона, и правка общего .tres из рантайма утащила бы её в файл.
	var material := OVERLAY_MATERIAL.duplicate() as ShaderMaterial
	_overlay.material = material
	canvas.add_child(_overlay)

	_mask = SubViewport.new()
	_mask.name = "OutlineMask"
	_mask.transparent_bg = true
	# Маска читается порогом по альфе, поэтому сглаживание ей не нужно, а стоит
	# оно как обычный кадр. Мягкий край контура делает уже шейдер.
	_mask.msaa_3d = Viewport.MSAA_DISABLED
	_mask.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_mask.use_debanding = false
	_mask.positional_shadow_atlas_size = 0
	# Свет на маску не влияет — важен только факт попадания меша в кадр.
	_mask.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask)

	# own_world_3d НЕ включаем: вложенный SubViewport по умолчанию рендерит мир
	# родительского вьюпорта — тот же самый, что и игрок. Свой мир был бы пустым.
	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.cull_mask = O_OutlineVisual.OUTLINE_LAYER
	_mask_camera.environment = _blank_environment()
	_mask_camera.current = true
	_mask.add_child(_mask_camera)

	material.set_shader_parameter("mask_tex", _mask.get_texture())


## Окружение маски: пустой фон и никакого неба. Без него SubViewport взял бы
## WorldEnvironment сцены и залил бы маску небом — то есть единицами альфы на
## весь экран, и «контуром» стала бы рамка вокруг кадра.
func _blank_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	return env


## Камера-двойник обязана совпадать с игровой по ВСЕМ параметрам проекции, а не
## только по положению: FOV — настройка игрока (RS_Settings), и разъехавшись на
## пару градусов, маска дала бы контур со смещением в несколько пикселей.
func _sync_camera(camera: Camera3D) -> void:
	_mask_camera.global_transform = camera.global_transform
	_mask_camera.projection = camera.projection
	_mask_camera.fov = camera.fov
	_mask_camera.size = camera.size
	_mask_camera.frustum_offset = camera.frustum_offset
	_mask_camera.keep_aspect = camera.keep_aspect
	_mask_camera.near = camera.near
	_mask_camera.far = camera.far


func _sync_size() -> void:
	var size := Vector2i(get_viewport().get_visible_rect().size)
	if _mask.size != size:
		_mask.size = size


## Прямоугольник на экране, за пределами которого контура заведомо нет: габарит
## всех мешей сущности, спроецированный камерой, плюс запас на толщину.
##
## Пустой прямоугольник значит «рисовать нечего». Угол ЗА камерой ломает
## unproject_position (точка за спиной проецируется как зеркальная), поэтому
## частично зашедший за камеру объект честно обводится по всему экрану — это
## редкий кадр, и ошибиться в нём дешевле, чем обрезать контур.
func _screen_rect(entities: Array[Entity], camera: Camera3D) -> Rect2:
	var screen := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var box := Rect2()
	var has_point := false
	var any_behind := false

	for entity in entities:
		for geometry in RS_EntityVisuals.geometries(entity):
			var aabb: AABB = geometry.global_transform * geometry.get_aabb()
			for i in 8:
				var corner := aabb.get_endpoint(i)
				if camera.is_position_behind(corner):
					any_behind = true
					continue
				var point := camera.unproject_position(corner)
				if has_point:
					box = box.expand(point)
				else:
					box = Rect2(point, Vector2.ZERO)
					has_point = true

	if not has_point:
		return Rect2()
	if any_behind:
		return screen
	return box.grow(RECT_MARGIN).intersection(screen)


func _set_active(active_now: bool) -> void:
	if _overlay == null or _overlay.visible == active_now:
		return
	_overlay.visible = active_now
	_mask.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if active_now else SubViewport.UPDATE_DISABLED
	)
