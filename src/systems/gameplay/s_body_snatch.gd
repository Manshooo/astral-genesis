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
			# системы (см. правило v9 в docs/.../GECS и правила движка.md). Проверку «а есть ли тело»
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

	# Габарит проверяем ДО броска кубика: отказ по месту — это не «не повезло», а
	# «сюда это тело не влезет», и тратить на него попытку нечестно.
	var form := E_Body.form_of(body)
	if not _fits(soul, body, form):
		_notify(soul, "Тело здесь не поместится")
		return

	var chance := C_StatModifiers.of(soul, C_StatModifiers.CAPTURE_CHANCE, bs.capture_success_chance)
	if randf() > chance:
		ECS.world.emit_event(&"body_snatch_failed", soul)
		return

	_embody(soul, body, form)


## Структурные правки идут через командный буфер (cmd), а не напрямую: с GECS v9
## System.safe_iteration = false по умолчанию — системы обходят массивы архетипов
## zero-copy, и add/remove прямо в process() может пропустить сущности (swap-remove)
## и роняет push_error в debug_mode. Буфер применяется сразу после process() этой
## системы (FlushMode.PER_SYSTEM), коалесцируя remove+add в один переезд архетипа.
func _embody(soul: Entity, body: Entity, form: C_BodyForm) -> void:
	# 1. Перенять ХАРАКТЕРИСТИКИ тела — прочность, запас распада, подвижность.
	# Ни одна из них здесь не названа: тело отдаёт всё, что объявило компонентами
	# (C_BodyTrait + C_Health), и новая характеристика не потребует правки этого
	# файла. Раньше перенос был расписан покомпонентно И ЗДЕСЬ, И в
	# RunManager._restore_embodiment — две копии одного правила.
	#
	# СНАЧАЛА СНИМАЕМ ВСЁ НАДЕТОЕ, а не только то, что даёт новое тело: снятие
	# «по списку нового» оставляло на душе характеристики, которых у новой плоти
	# нет вовсе. Пересадка из прыгучего тела в безногое давала прыгающего
	# безногого — ровно тот случай, ради которого возможность и сделана
	# компонентом. Симметрия с O_ExpelFromBody держится сама: снимаем тем же
	# правилом «C_BodyTrait + C_Health», каким надеваем.
	for shed in _worn_traits(soul):
		cmd.remove_component(soul, shed.get_script())

	for worn in E_Body.traits_of(body):
		if worn is C_BodyTrait:
			# Характеристика становится состоянием: C_BodyDecay так открывает
			# полный карман времени. См. C_BodyTrait.on_worn.
			(worn as C_BodyTrait).on_worn(soul)
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

	# 2.2. Перенять ФОРМУ тела: габарит коллизии и уровень глаз. Надевает её
	# O_BodyForm — захват, как и с обликом, только просит. Перенос restore_* при
	# пересадке из тела в тело — та же ловушка, что у C_BodyVisual: вернуться надо
	# к призрачной форме, а не к форме прошлого тела.
	if form:
		var worn_form := soul.get_component(C_BodyForm) as C_BodyForm
		if worn_form:
			form.restore_shape = worn_form.restore_shape
			form.restore_camera = worn_form.restore_camera
			cmd.remove_component(soul, C_BodyForm)
		cmd.add_component(soul, form)

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
		# Офсет — по форме, которую риг НАДЕВАЕТ, а не по той, что на нём сейчас:
		# компонент ещё лежит в буфере, и player.foot_offset() ответил бы
		# призрачным габаритом — рослое тело село бы по пояс в пол. Тела без
		# формы оставляют ригу его собственный габарит, и офсет считает он сам.
		var player := soul as E_Player
		var lift := form.foot_offset() if form else Vector3.ZERO
		if lift == Vector3.ZERO and player:
			lift = player.foot_offset()
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


## Характеристики тела, надетые на душу прямо сейчас.
##
## Собираем список заранее, отдельным проходом: снятие правит тот самый словарь
## components, по которому мы бы шли (та же осторожность, что в
## O_ExpelFromBody.expel).
static func _worn_traits(soul: Entity) -> Array[Component]:
	var found: Array[Component] = []
	for component in soul.components.values():
		if component is C_BodyTrait or component is C_Health:
			found.append(component as Component)
	return found


## На столько приподнимаем проверяемую капсулу над подошвой — см. ниже.
const _FLOOR_CLEARANCE := 0.05


## Влезает ли риг в новую форму на месте тела.
##
## Пробуем форму ТАМ, где риг окажется, и с маской ВОПЛОЩЁННОГО игрока: призрак
## проходит сквозь permeable-геометрию (S_Phasing снимает этот бит из маски,
## пока на душе висит C_Phasing), а тело — нет, так что проверять призрачной
## маской значит разрешить вселение в решётку.
##
## Исключаем себя и само тело: риг стоит вплотную к трупу, в который целится, а
## тело через кадр будет поглощено — упереться в них значило бы отказывать всегда.
static func _fits(soul: Entity, body: Entity, form: C_BodyForm) -> bool:
	if form == null or form.shape == null:
		return true  # габарит не меняется — проверять нечего

	var soul_node := soul as Node as CollisionObject3D
	var body_node := body as Node as Node3D
	if soul_node == null or body_node == null:
		return true

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = form.shape
	# Подошва тела ВСЕГДА касается пола, на котором оно стоит — это не тесное
	# место, а нормальная посадка (см. соглашение о точке отсчёта в E_Body).
	# Без зазора капсула ровно на границе с полом регулярно засчитывалась как
	# «пересечение» — не везде: в хабе тела оказались случайно приподняты над
	# полом, а тела в заспавненных комнатах стоят на нём вплотную (y=0, полу-
	# соглашение E_Body), и там нулевой зазор `intersect_shape` против пола-
	# трисетки стабильно давал ложное «не помещается». 5 см — на порядок больше
	# любого физического допуска и на порядок меньше высоты препятствия,
	# которое эта проверка обязана ловить (низкий потолок, стена).
	params.transform = Transform3D(
		Basis.IDENTITY,
		body_node.global_position + form.foot_offset() + Vector3.UP * _FLOOR_CLEARANCE
	)
	params.collision_mask = soul_node.collision_mask | C_Phasing.PERMEABLE_BIT

	# Исключаем не только корень тела, а весь его поддерево коллайдеров: у рига
	# рэгдолла кости стоят на static_colliders (нужно, чтобы падать на пол), труп
	# оседает недалеко от своего корня, и без этого проверка регулярно натыкалась
	# бы на собственные кости — тело не влезало бы само в себя никогда.
	var skip: Array[RID] = [soul_node.get_rid()]
	var body_collider := body_node as CollisionObject3D
	if body_collider:
		skip.append(body_collider.get_rid())
	for descendant in body_node.find_children("*", "CollisionObject3D", true, false):
		skip.append((descendant as CollisionObject3D).get_rid())
	params.exclude = skip

	var space := soul_node.get_world_3d().direct_space_state
	return space.intersect_shape(params, 1).is_empty()


## Короткая строка поверх HUD. Через буфер, потому что мы внутри прохода системы
## (правило v9); пересоздаём компонент, а не правим поля — прямая запись миру не
## сигналится, и HUD не увидел бы новый текст (см. A_TravelThroughDoor._notify).
func _notify(soul: Entity, text: String) -> void:
	if soul.has_component(C_ScreenMessage):
		cmd.remove_component(soul, C_ScreenMessage)
	var message := C_ScreenMessage.new()
	message.text = text
	cmd.add_component(soul, message)
