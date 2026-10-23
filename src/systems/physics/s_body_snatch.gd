# res://src/systems/physics/s_body_snatch.gd
# Группа "physics", рядом с S_SnatchTargetDetector (его метка нужна в том же физкадре). Захват тела: по capture_requested берёт тело с C_SnatchTargeted, бросает кубик на
# capture_success_chance и вселяется — перенимает ВСЕ C_BodyTrait и C_Health (поимённо не перечисляя), метит C_Embodied, переносит позицию, поглощает тело. Здесь же ДОБРОВОЛЬНЫЙ
# выход (leave_body): он забирает остаток запаса, правило одно на все выходы (O_ExpelFromBody.expel). Вики: [[Захват тела]].
class_name S_BodySnatch
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for soul in entities:
		var bs := soul.get_component(C_BodySnatch) as C_BodySnatch

		# Надетое тело добито ЭТИМ тиком, но смерть ещё не объявлена (S_Health вешает C_Dead в "gameplay" после физпрохода): захват снял бы смертельный C_Health, а выход забрал бы остаток
		# как награду. Гибель побеждает — оба нажатия гасим, а не откладываем, чтобы не выстрелили в следующем теле.
		if _worn_body_dying(soul):
			bs.leave_requested = false
			bs.capture_requested = false
			continue

		if bs.leave_requested:
			bs.leave_requested = false
			# Отложенно: развоплощение снимает компоненты посреди прохода (правило v9); «есть ли тело» проверяет сам expel.
			O_ExpelFromBody.expel.call_deferred(soul, true)
			continue

		if not bs.capture_requested:
			continue
		bs.capture_requested = false
		_try_capture(soul, bs)


func _try_capture(soul: Entity, bs: C_BodySnatch) -> void:
	# Луч не кастуем: цель под крестиком держит S_SnatchTargetDetector (Runs.Before) — один каст и один источник правды.
	var body := ECS.world.query.with_all([C_SnatchTargeted]).execute_one()
	if body == null:
		return

	# Габарит проверяем ДО броска: отказ по месту — не «не повезло», попытку тратить нечестно.
	var form := E_Body.form_of(body)
	if not _fits(soul, body, form):
		C_ScreenMessage.show_on(soul, "HUD_MSG_NO_ROOM", cmd)
		return

	var chance := C_StatModifiers.of(soul, C_StatModifiers.CAPTURE_CHANCE, bs.capture_success_chance)
	if randf() > chance:
		ECS.world.emit_event(&"body_snatch_failed", soul)
		return

	_embody(soul, body, form)
	# Только удавшийся захват: воплощение загрузкой сейва идёт мимо _try_capture и звучать не должно.
	var soul_node := soul as Node as Node3D
	AudioManager.play_event_3d(bs.capture_event, soul_node.global_position if soul_node else Vector3.ZERO)


## Структурные правки — через cmd (правило v9); буфер применяется после process() (PER_SYSTEM), remove+add коалесцируются в один переезд архетипа.
func _embody(soul: Entity, body: Entity, form: C_BodyForm) -> void:
	# 1. Перенять ХАРАКТЕРИСТИКИ: тело отдаёт всё, что объявило (C_BodyTrait + C_Health), новая не требует правки здесь. СНАЧАЛА СНИМАЕМ ВСЁ НАДЕТОЕ: снятие по списку нового
	# оставило бы прыгающего безногого. Симметрия с O_ExpelFromBody — тем же правилом.
	for shed in E_Body.worn_by(soul):
		cmd.remove_component(soul, shed.get_script())

	for worn in E_Body.traits_of(body):
		if worn is C_BodyTrait:
			# Характеристика становится состоянием (C_BodyDecay открывает полный карман; C_BodyTrait.on_worn).
			(worn as C_BodyTrait).on_worn(soul)
		cmd.add_component(soul, worn)

	# 2. Состояние «во плоти» и ЧЬЮ плоть заняли (путь сцены переживает сохранение). Не «добавить, если нет»: при пересадке путь остался бы от прошлого тела.
	if soul.has_component(C_Embodied):
		cmd.remove_component(soul, C_Embodied)
	var embodied := C_Embodied.new()
	embodied.body_scene_path = (body as Node).scene_file_path
	cmd.add_component(soul, embodied)

	# 2.1. Облик: меш надевает O_BodyVisual, захват только просит.
	var visual := E_Body.visual_of(body)
	if visual:
		var previous := soul.get_component(C_BodyVisual) as C_BodyVisual
		if previous:
			# Пересадка тело→тело: вернуться надо к облику БФЖ, а не прошлого тела — откат переносим руками (буфер коалесцирует remove+add).
			visual.restore_mesh = previous.restore_mesh
			visual.restore_material = previous.restore_material
			visual.restore_transform = previous.restore_transform
			cmd.remove_component(soul, C_BodyVisual)
		cmd.add_component(soul, visual)

	# 2.2. ФОРМА (габарит, уровень глаз) — O_BodyForm; restore_* переносим так же, как у облика.
	if form:
		var worn_form := soul.get_component(C_BodyForm) as C_BodyForm
		if worn_form:
			form.restore_shape = worn_form.restore_shape
			form.restore_camera = worn_form.restore_camera
			cmd.remove_component(soul, C_BodyForm)
		cmd.add_component(soul, form)

	# 3. Позиция в тело — только позиция и с поправкой E_Player.foot_offset (у тела origin — подошва, у игрока — центр коллайдера: иначе по пояс в пол). Поворот не трогаем:
	# yaw на E_Player, pitch на камере (см. PlayerPlacement.arrival_point).
	var soul_node := soul as Node as Node3D
	var body_node := body as Node as Node3D
	if soul_node and body_node:
		# Офсет по форме, которую риг НАДЕВАЕТ: компонент ещё в буфере, foot_offset() ответил бы призрачным габаритом.
		var player := soul as E_Player
		var lift := form.foot_offset() if form else Vector3.ZERO
		if lift == Vector3.ZERO and player:
			lift = player.foot_offset()
		soul_node.global_position = body_node.global_position + lift

	# 4. Поглотить тело насовсем: помечаем в сейве сразу — комплекс из сида, без пометки возродился бы дубликатом.
	var origin := body.get_component(C_BodyOrigin) as C_BodyOrigin
	if origin:
		WorldSave.mark_body_consumed(origin.body_id)
	cmd.remove_entity(body)

	# Событие — в буфер, после правок выше (add_custom по порядку): иначе наблюдатель "body_snatched" увидел бы душу невоплощённой. Тем же вызовом — контрольная точка ПОСЛЕ применения буфера:
	# mark_body_consumed уже записал тело съеденным на диск, а вылет до смены комнаты дал бы сейв «тело поглощено, игрок призрак».
	cmd.add_custom(
		func():
			ECS.world.emit_event(&"body_snatched", soul)
			RunManager.save_progress()
	)


## Надетое тело на нуле, но смерть ещё не объявлена (см. process); бестелесной душе умирать нечем.
static func _worn_body_dying(soul: Entity) -> bool:
	var health := soul.get_component(C_Health) as C_Health
	return health != null and health.current <= 0.0


## Приподнимаем проверяемую капсулу над подошвой (см. _fits).
const _FLOOR_CLEARANCE := 0.05


## Влезает ли риг в новую форму на месте тела: пробуем ТАМ, где риг окажется, с маской ВОПЛОЩЁННОГО игрока (призрак проходит permeable, тело — нет). Исключаем себя и само тело
## (стоим вплотную, тело через кадр будет поглощено).
static func _fits(soul: Entity, body: Entity, form: C_BodyForm) -> bool:
	if form == null or form.shape == null:
		return true  # габарит не меняется — проверять нечего

	var soul_node := soul as Node as CollisionObject3D
	var body_node := body as Node as Node3D
	if soul_node == null or body_node == null:
		return true

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = form.shape
	# Подошва тела всегда касается пола: без зазора капсула на границе давала ложное «не помещается» против пола-трисетки (тела в заспавненных комнатах стоят на y=0).
	# 5 см — на порядок больше физического допуска и меньше препятствия, которое проверка обязана ловить.
	params.transform = Transform3D(
		Basis.IDENTITY,
		body_node.global_position + form.foot_offset() + Vector3.UP * _FLOOR_CLEARANCE
	)
	params.collision_mask = soul_node.collision_mask | C_Phasing.PERMEABLE_BIT

	# Исключаем всё поддерево коллайдеров тела: кости рэгдолла на static_colliders, иначе тело не влезало бы само в себя.
	var skip: Array[RID] = [soul_node.get_rid()]
	var body_collider := body_node as CollisionObject3D
	if body_collider:
		skip.append(body_collider.get_rid())
	for descendant in body_node.find_children("*", "CollisionObject3D", true, false):
		skip.append((descendant as CollisionObject3D).get_rid())
	params.exclude = skip

	var space := soul_node.get_world_3d().direct_space_state
	return space.intersect_shape(params, 1).is_empty()
