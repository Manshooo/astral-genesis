# res://src/systems/gameplay/s_body_snatch.gd
# Группа: "physics" — рядом с S_SnatchTargetDetector, чья метка нужна ему в том
# же физкадре.
# Ядро игры — захват тела. По запросу захвата (действие "snatch_body", по умолчанию
# ЛКМ; E_Player._input ставит C_BodySnatch.capture_requested) берёт тело, помеченное
# C_SnatchTargeted (его непрерывно держит S_SnatchTargetDetector — он же рисует
# крестик в прицеле), бросает кубик на capture_success_chance и при успехе
# «вселяется»:
#   - перенимает характеристики тела — ВСЕ его C_BodyTrait (запас распада
#     C_BodyDecay, подвижность C_Walk/C_Jump, …) плюс прочность C_Health,
#     не перечисляя их поимённо;
#   - помечает себя C_Embodied;
#   - переносит точку присутствия в тело;
#   - поглощает исходную сущность-тело.
#
# Здесь же обрабатывается обратное действие — ДОБРОВОЛЬНЫЙ выход из тела
# (leave_body). Он живёт рядом с захватом не для симметрии: выход забирает
# остаток запаса тела себе, и правило этого перетекания одно на все выходы
# (O_ExpelFromBody.expel).
class_name S_BodySnatch
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_BodySnatch]).with_none([C_UIBlocked])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for soul in entities:
		var bs := soul.get_component(C_BodySnatch) as C_BodySnatch

		if bs.leave_requested:
			bs.leave_requested = false
			# Отложенно: развоплощение снимает компоненты, а мы внутри прохода
			# системы (см. правило v9 в CLAUDE.md). Проверку «а есть ли тело»
			# делает сам expel — там же, где живёт остальная защита от двойного
			# выхода в одном кадре.
			O_ExpelFromBody.expel.call_deferred(soul, true)
			continue

		if not bs.capture_requested:
			continue
		bs.capture_requested = false
		_try_capture(soul, bs)


func _try_capture(soul: Entity, bs: C_BodySnatch) -> void:
	# Луч тут больше не кастуем: цель под крестиком непрерывно держит
	# S_SnatchTargetDetector (он же рисует крестик в HUD) и объявлен Runs.Before,
	# так что метка на этот кадр уже проставлена. Один каст вместо двух и один
	# источник правды: во что целимся — ровно то, что подсвечено игроку.
	var body := ECS.world.query.with_all([C_SnatchTargeted]).execute_one()
	if body == null:
		return

	if randf() > bs.capture_success_chance:
		ECS.world.emit_event(&"body_snatch_failed", soul)
		return

	_embody(soul, body)


## Структурные правки идут через командный буфер (cmd), а не напрямую: с GECS v9
## System.safe_iteration = false по умолчанию — системы обходят массивы архетипов
## zero-copy, и add/remove прямо в process() может пропустить сущности (swap-remove)
## и роняет push_error в debug_mode. Буфер применяется сразу после process() этой
## системы (FlushMode.PER_SYSTEM), коалесцируя remove+add в один переезд архетипа.
func _embody(soul: Entity, body: Entity) -> void:
	# 1. Перенять ХАРАКТЕРИСТИКИ тела — прочность, запас распада, подвижность.
	# Ни одна из них здесь не названа: тело отдаёт всё, что объявило компонентами
	# (C_BodyTrait + C_Health), и новая характеристика не потребует правки этого
	# файла. Раньше перенос был расписан покомпонентно И ЗДЕСЬ, И в
	# RunManager._restore_embodiment — две копии одного правила.
	#
	# remove+add, а не «добавить, если нет»: при пересадке из тела в тело трейт
	# уже висит, и остались бы числа прошлого тела. Буфер коалесцирует пару в
	# один переезд архетипа, так что лишней цены нет.
	for worn in E_Body.traits_of(body):
		cmd.remove_component(soul, worn.get_script())
		if worn is C_BodyTrait:
			# Характеристика становится состоянием: C_BodyDecay так открывает
			# полный карман времени. См. C_BodyTrait.on_worn.
			(worn as C_BodyTrait).on_worn()
		cmd.add_component(soul, worn)

	# 2. Отметить состояние «во плоти» и то, ЧЬЮ плоть заняли: путь сцены тела
	# переживает сохранение, и по нему загрузка восстанавливает облик.
	# Не «добавить, если нет»: при пересадке из тела в тело компонент уже висит,
	# и путь остался бы от прошлого тела. remove+add буфер коалесцирует в один
	# переезд архетипа, так что лишней цены нет.
	if soul.has_component(C_Embodied):
		cmd.remove_component(soul, C_Embodied)
	var embodied := C_Embodied.new()
	embodied.body_scene_path = (body as Node).scene_file_path
	cmd.add_component(soul, embodied)

	# 2.1. Перенять облик тела. Сам меш надевает O_BodyVisual — система захвата
	# про геометрию ничего не знает, только просит.
	var visual := E_Body.visual_of(body)
	if visual:
		var previous := soul.get_component(C_BodyVisual) as C_BodyVisual
		if previous:
			# Пересадка из тела в тело: возвращаться при развоплощении нужно всё
			# равно к облику БФЖ, а не к прошлому телу. Переносим цель отката
			# руками и не полагаемся на то, что наблюдатель успеет увидеть снятие
			# старого компонента: remove+add одного типа буфер коалесцирует в
			# один переезд архетипа.
			visual.restore_mesh = previous.restore_mesh
			visual.restore_material = previous.restore_material
			visual.restore_transform = previous.restore_transform
			cmd.remove_component(soul, C_BodyVisual)
		cmd.add_component(soul, visual)

	# 3. Перенести точку присутствия в тело (Entity extends Node → двойной каст).
	#
	# Только позицию и только с поправкой E_Player.foot_offset: у тела origin —
	# подошва, у игрока — центр его коллайдера, так что копирование
	# global_transform целиком сажало игрока на полроста в пол («провалился сквозь
	# пол» — коллайдер, утопленный в односторонний тримеш-пол, физика выталкивала
	# вниз).
	#
	# Поворот не трогаем: yaw живёт на E_Player, pitch — на его камере, и
	# развернуть игрока в позу трупа так же дезориентирует, как разворот при
	# входе в дверь (см. RunManager._arrival_point — там ровно то же правило).
	var soul_node := soul as Node as Node3D
	var body_node := body as Node as Node3D
	if soul_node and body_node:
		var player := soul as E_Player
		var lift := player.foot_offset() if player else Vector3.ZERO
		soul_node.global_position = body_node.global_position + lift

	# 4. Поглотить исходное тело. Съедено оно насовсем, поэтому помечаем его в
	# сейве сразу, а не на ближайшей контрольной точке: комплекс восстанавливается
	# из сида покомнатно-заново, и без пометки тело возродилось бы дубликатом
	# того, в ком игрок сидит. Между захватом и сменой комнаты можно выйти в меню.
	var origin := body.get_component(C_BodyOrigin) as C_BodyOrigin
	if origin:
		WorldSave.mark_body_consumed(origin.body_id)
	cmd.remove_entity(body)

	# Событие — тоже в буфер: иначе оно ушло бы ДО применения C_Embodied/C_Health,
	# и наблюдатель "body_snatched" увидел бы душу ещё не воплощённой.
	# add_custom исполняется в порядке постановки, т.е. после правок выше.
	cmd.add_custom(func(): ECS.world.emit_event(&"body_snatched", soul))
