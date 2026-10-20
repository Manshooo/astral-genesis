## Обводка выделенного объекта постэффектом по экранной маске: меши на отдельном слое (O_OutlineVisual) рендерятся в SubViewport камерой-двойником
## (cull_mask — один бит), по маске шейдер считает контур (outline_mask.gdshader). Не material_overlay: тот наследует толщину геометрии и обводит
## составное по частям. Цена: без выделения маска в UPDATE_DISABLED, оверлей скрыт; иначе шейдер идёт по прямоугольнику проекции. Вики: [[Взаимодействие]].
class_name S_OutlineMask
extends System

## Слой холста для оверлея: ниже HUD (-1), выше 3D — обводка относится к миру.
const OVERLAY_CANVAS_LAYER := -2

const OVERLAY_MATERIAL: ShaderMaterial = preload(
	"res://assets/shared/materials/outline_mask.tres"
)

## Запас вокруг проекции объекта, px: шире самой толстой обводки, иначе обрежется по краю.
const RECT_MARGIN := 8.0

var _mask: SubViewport
var _mask_camera: Camera3D
var _overlay: ColorRect


## process_empty — условие работы: гасить обводку надо, когда выборка пуста; без флага GECS систему в такой кадр не зовёт.
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
		# Объект есть, но на экране его нет — маску гонять незачем.
		_set_active(false)
		return

	_sync_camera(camera)
	_sync_size()
	_overlay.position = rect.position
	_overlay.size = rect.size
	_set_active(true)


## Узлы строятся кодом: механизм, не авторский контент (цвет и толщина — в outline_mask.tres); сцену пришлось бы держать актуальной руками.
func _build_nodes() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "OutlineCanvas"
	canvas.layer = OVERLAY_CANVAS_LAYER
	add_child(canvas)

	_overlay = ColorRect.new()
	_overlay.name = "OutlineOverlay"
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	# Копия: в материал пишется ViewportTexture прогона, правка общего .tres утащила бы её в файл.
	var material := OVERLAY_MATERIAL.duplicate() as ShaderMaterial
	_overlay.material = material
	canvas.add_child(_overlay)

	_mask = SubViewport.new()
	_mask.name = "OutlineMask"
	_mask.transparent_bg = true
	# Маска читается порогом по альфе — сглаживание не нужно; мягкий край делает шейдер.
	_mask.msaa_3d = Viewport.MSAA_DISABLED
	_mask.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_mask.use_debanding = false
	_mask.positional_shadow_atlas_size = 0
	# Свет на маску не влияет.
	_mask.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_mask)

	# own_world_3d НЕ включаем: вложенный SubViewport рендерит мир родителя; свой был бы пустым.
	_mask_camera = Camera3D.new()
	_mask_camera.name = "MaskCamera"
	_mask_camera.cull_mask = O_OutlineVisual.OUTLINE_LAYER
	_mask_camera.environment = _blank_environment()
	_mask_camera.current = true
	_mask.add_child(_mask_camera)

	material.set_shader_parameter("mask_tex", _mask.get_texture())


## Окружение маски: пустой фон, без неба — иначе SubViewport залил бы маску альфой всего экрана.
func _blank_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	return env


## Камера-двойник совпадает с игровой по ВСЕМ параметрам проекции (FOV — настройка игрока), иначе контур сместится.
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


## Прямоугольник, за пределами которого контура нет (габарит мешей, спроецированный камерой, плюс запас). Пустой — рисовать нечего. Угол ЗА камерой ломает unproject_position,
## поэтому зашедший за камеру объект обводится по всему экрану — ошибиться дешевле, чем обрезать.
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
