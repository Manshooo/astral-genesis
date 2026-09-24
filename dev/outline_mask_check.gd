extends Node
## Проверка обводки силуэтом (`O_OutlineVisual` + `S_OutlineMask`).
## Запуск: godot --headless dev/outline_mask_check.tscn
##
## Вся эта область ломается ТИХО. Ошибка в бите слоя, в cull_mask камеры-двойника
## или в фоне её окружения не бросает ничего — просто вместо контура вокруг
## объекта получается либо пустой экран, либо рамка по краю кадра. Ни то, ни
## другое headless не «увидит» глазами, зато каждое из них однозначно читается по
## состоянию узлов, и именно оно здесь и сверяется.
##
## Пиксели не проверяются вовсе: в headless рендера нет. Проверяется ВХОД
## постэффекта — что в маску попадает ровно выделенный объект и ничего кроме, что
## камера маски смотрит туда же, куда игрок, и что ножницы оверлея накрывают
## проекцию объекта. Как выглядит сам контур — вопрос живого прогона.

const OUTLINE_BIT := O_OutlineVisual.OUTLINE_LAYER

## Куда ставится тестовый объект: прямо перед камерой, в нескольких метрах.
const TARGET_POS := Vector3(0.0, 0.0, -3.0)

var _ok := 0
var _fail := 0

var _camera: Camera3D


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	world.add_observer(O_OutlineVisual.new())

	var mask_system := S_OutlineMask.new()
	mask_system.group = "gameplay"
	world.add_system(mask_system)

	# Камера игрока: система ищет её через get_viewport().get_camera_3d(), то
	# есть ровно так же, как в игре — чья это камера, ей знать незачем.
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)

	await _run(world, mask_system)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World, mask_system: S_OutlineMask) -> void:
	# --- 1. Наблюдатель: слой обводки -------------------------------------
	var entity := _make_entity(TARGET_POS)
	world.add_entity(entity)
	await get_tree().process_frame

	var meshes := RS_EntityVisuals.geometries(entity)
	_check(
		"у составного объекта найдены оба меша",
		meshes.size() == 2,
		"мешей: %d" % meshes.size(),
	)
	# Посторонний слой на одном из мешей: снимая обводку, наблюдатель обязан
	# вернуть ровно то, что было, а не обнулить маску слоёв целиком.
	meshes[0].layers = 1 | 2

	_check(
		"до выделения бит обводки не стоит",
		not _any_lit(meshes),
		"слои: %s" % _layers_of(meshes),
	)

	entity.add_component(C_Highlighted.new())
	await get_tree().process_frame

	_check(
		"выделение переводит на слой обводки ВСЕ меши объекта",
		_all_lit(meshes),
		"слои: %s — часть меша осталась вне маски, силуэт вышел бы дырявым"
		% _layers_of(meshes),
	)
	_check(
		"прочие слои меша не тронуты",
		meshes[0].layers & 3 == 3,
		"слои первого меша: %d" % meshes[0].layers,
	)
	_check(
		"material_overlay не трогается",
		meshes[0].material_overlay == null and meshes[1].material_overlay == null,
		"вернулся старый подход с выдавленной геометрией вместо маски",
	)

	entity.remove_component(C_Highlighted)
	await get_tree().process_frame

	_check(
		"снятие выделения убирает бит обводки",
		not _any_lit(meshes),
		"слои: %s" % _layers_of(meshes),
	)
	_check(
		"и возвращает слои меша ровно к прежним",
		meshes[0].layers == 3 and meshes[1].layers == 1,
		"слои: %s" % _layers_of(meshes),
	)

	# --- 2. Наблюдатель: границы ------------------------------------------
	var narrowed := _make_entity(TARGET_POS)
	var root := C_VisualRoot.new()
	root.path = "Второй"
	narrowed.add_component(root)
	world.add_entity(narrowed)
	await get_tree().process_frame

	narrowed.add_component(C_Highlighted.new())
	await get_tree().process_frame

	var narrowed_meshes := narrowed.find_children("*", "GeometryInstance3D", true, false)
	var lit_count := 0
	for mesh in narrowed_meshes:
		if (mesh as GeometryInstance3D).layers & OUTLINE_BIT != 0:
			lit_count += 1
	_check(
		"C_VisualRoot сужает силуэт до указанного узла",
		lit_count == 1,
		"на слое обводки мешей: %d из %d" % [lit_count, narrowed_meshes.size()],
	)
	world.remove_entity(narrowed)
	await get_tree().process_frame

	var bare := Entity.new()
	bare.name = "БезГеометрии"
	world.add_entity(bare)
	await get_tree().process_frame
	bare.add_component(C_Highlighted.new())
	await get_tree().process_frame
	_check("сущность без единого меша не роняет наблюдатель", true, "")
	world.remove_entity(bare)
	await get_tree().process_frame

	# --- 3. Система: из чего собрана маска ---------------------------------
	var mask := mask_system.get_node_or_null("OutlineMask") as SubViewport
	var overlay := mask_system.get_node_or_null("OutlineCanvas/OutlineOverlay") as ColorRect
	_check("система собрала SubViewport маски", mask != null, "узла OutlineMask нет")
	_check("система собрала оверлей контура", overlay != null, "узла OutlineOverlay нет")
	if mask == null or overlay == null:
		return

	var mask_camera := mask.get_node_or_null("MaskCamera") as Camera3D
	_check("у маски есть своя камера", mask_camera != null, "узла MaskCamera нет")
	if mask_camera == null:
		return

	_check(
		"камера маски снимает РОВНО слой обводки",
		mask_camera.cull_mask == OUTLINE_BIT,
		"cull_mask=%d — в маску попадёт посторонняя геометрия, и контур обведёт её"
		% mask_camera.cull_mask,
	)
	_check(
		"фон маски пустой, а не небо",
		(
			mask_camera.environment != null
			and mask_camera.environment.background_mode == Environment.BG_COLOR
			and mask_camera.environment.background_color.a == 0.0
		),
		"с небом маска залита целиком, и «контуром» станет рамка по краю кадра",
	)
	_check("маска прозрачна", mask.transparent_bg, "иначе фон засчитается силуэтом")

	var material := overlay.material as ShaderMaterial
	_check(
		"маска подана в шейдер оверлея",
		material != null and material.get_shader_parameter("mask_tex") != null,
		"без mask_tex шейдер рисует по пустоте — контура нет, ошибки тоже",
	)
	_check(
		"материал оверлея — копия, а не общий ресурс",
		material != null and material != S_OutlineMask.OVERLAY_MATERIAL,
		"ViewportTexture этого прогона утекла бы в .tres проекта",
	)

	# --- 4. Система: цена, когда обводить нечего ---------------------------
	ECS.process(0.016, "gameplay")
	_check(
		"без выделения маска не рендерится вовсе",
		mask.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"полноэкранный проход крутится вхолостую каждый кадр",
	)
	_check("без выделения оверлей скрыт", not overlay.visible, "")

	# --- 5. Система: выделенный объект перед камерой -----------------------
	entity.add_component(C_Highlighted.new())
	await get_tree().process_frame
	_camera.global_position = Vector3.ZERO
	_camera.look_at_from_position(Vector3.ZERO, TARGET_POS, Vector3.UP)
	_camera.fov = 70.0
	ECS.process(0.016, "gameplay")

	_check("выделение включает маску", mask.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "")
	_check("выделение показывает оверлей", overlay.visible, "")
	_check(
		"камера-двойник встала на игровую",
		mask_camera.global_transform.is_equal_approx(_camera.global_transform),
		"маска снимает объект с другой точки — контур уедет от объекта",
	)
	_check(
		"и повторила её проекцию",
		is_equal_approx(mask_camera.fov, _camera.fov) and mask_camera.projection == _camera.projection,
		"fov маски %.1f против %.1f у игрока" % [mask_camera.fov, _camera.fov],
	)

	var screen := get_viewport().get_visible_rect().size
	_check(
		"размер маски равен экрану",
		mask.size == Vector2i(screen),
		"%s против %s — шейдер читает маску по SCREEN_UV и промахнётся" % [mask.size, screen],
	)

	var center := _camera.unproject_position(TARGET_POS)
	var rect := Rect2(overlay.position, overlay.size)
	_check(
		"ножницы оверлея накрывают проекцию объекта",
		rect.has_point(center),
		"объект проецируется в %s, оверлей %s" % [center, rect],
	)
	_check(
		"и заметно меньше экрана",
		rect.get_area() < screen.x * screen.y * 0.5,
		"оверлей %s при экране %s — ножницы не работают, и цена та же полноэкранная"
		% [rect.size, screen],
	)

	# --- 6. Система: объект вне кадра --------------------------------------
	_move_entity(entity, Vector3(0.0, 0.0, 5.0))
	ECS.process(0.016, "gameplay")
	_check(
		"объект за спиной обводки не даёт",
		not overlay.visible,
		"контур рисуется поверх кадра, хотя объекта в кадре нет",
	)

	# Часть углов за камерой: unproject_position там врёт зеркальной проекцией,
	# и единственный честный ответ — обводить по всему экрану.
	_move_entity(entity, Vector3(0.0, 0.0, -0.1))
	ECS.process(0.016, "gameplay")
	rect = Rect2(overlay.position, overlay.size)
	_check(
		"объект в упор обводится по всему экрану, а не по вранью проекции",
		overlay.visible and rect.size == screen,
		"оверлей %s при экране %s" % [rect.size, screen],
	)

	# --- 7. Снятие выделения гасит всё -------------------------------------
	_move_entity(entity, TARGET_POS)
	entity.remove_component(C_Highlighted)
	await get_tree().process_frame
	ECS.process(0.016, "gameplay")
	_check("снятие выделения гасит оверлей", not overlay.visible, "")
	_check(
		"и останавливает маску",
		mask.render_target_update_mode == SubViewport.UPDATE_DISABLED,
		"маска продолжает рендериться после того, как обводить стало нечего",
	)


## Составной объект: два меша под общим корнем — ровно тот случай, ради которого
## обводка переехала на маску (раньше каждый меш получал свой контур).
func _make_entity(at: Vector3) -> Entity:
	var entity := Entity.new()
	entity.name = "Составной"
	for mesh_name in ["Первый", "Второй"]:
		var mesh := MeshInstance3D.new()
		mesh.name = mesh_name
		mesh.mesh = BoxMesh.new()
		mesh.position = at
		entity.add_child(mesh)
	return entity


func _move_entity(entity: Entity, to: Vector3) -> void:
	for geometry in RS_EntityVisuals.geometries(entity):
		(geometry as Node3D).global_position = to


func _all_lit(meshes: Array[GeometryInstance3D]) -> bool:
	for mesh in meshes:
		if mesh.layers & OUTLINE_BIT == 0:
			return false
	return true


func _any_lit(meshes: Array[GeometryInstance3D]) -> bool:
	for mesh in meshes:
		if mesh.layers & OUTLINE_BIT != 0:
			return true
	return false


func _layers_of(meshes: Array[GeometryInstance3D]) -> String:
	var parts: Array[String] = []
	for mesh in meshes:
		parts.append(str(mesh.layers))
	return ", ".join(parts)


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
