## res://src/levels/procedural/rooms/rs_room_preset_library.gd
## Библиотека пресетов комнат + селектор. Генератор зовёт select_preset() для
## каждой обычной комнаты ДО того, как у неё появятся рёбра: рёбер будет ровно
## столько, сколько дверей в выбранной сцене («сначала комната, потом рёбра», см.
## RS_LevelGraph). Уникальные комнаты (хаб, выход) сюда не ходят — их ставит
## конфиг генерации.
##
## Критерии подбора:
##   1. Портал (жёстко): у комнаты портал ровно тогда, когда узлу нужен
##      вертикальный переход (тег vertical_hub). Лишний — мёртвый портал посреди
##      пола, недостающий — оборванный переход.
##   2. Прочие теги узла ⊆ теги пресета (жёстко).
##   3. Тип помещения (мягко): среди прошедших — те, чей room_type совпал с
##      загаданным узлу. Совпавших нет — группа идёт дальше как есть. Именно
##      ПРЕДПОЧТЕНИЕ, а не фильтр: тип не несёт структурных обязательств, и
##      забег не должен становиться несобираемым из-за того, что арсенала ещё не
##      нарисовали.
##   4. Авторские веса.
##
## Вместимости и смещения «впритык по дверям» нет: степень выводится из сцены, а
## не сцена подбирается под степень. Специфичности нет тоже — она существовала
## только потому, что в tags сидела структура, из-за чего комнаты с «лишними»
## тегами проигрывали безликим.
##
## Шаги 2 и 3 — РАЗНЫЕ оси, и держать их врозь обязательно: теги отвечают «что
## комната умеет структурно», тип — «что это за помещение». Общий массив сделал
## бы тип жёстким требованием (см. RS_RoomPreset.room_type).
## @tool — иначе в редакторе ресурс грузится ПЛЕЙСХОЛДЕРОМ и его методы позвать
## нельзя («Attempt to call a method on a placeholder instance»). «Редактор
## пресетов» зовёт validate, «Генератор мира» — explain_selection, всё прямо из
## редактора.
@tool
class_name RS_RoomPresetLibrary
extends Resource

@export var presets: Array[RS_RoomPreset] = []

## Каталог типов помещений — вторая ось подбора. null = типов нет вовсе, подбор
## работает ровно как до их появления. Лежит здесь, а не отдельным аргументом
## generate_run: см. шапку RS_RoomTypeCatalog.
@export var type_catalog: RS_RoomTypeCatalog

## Словарь структурных тегов — ОПИСАНИЯ, а не список разрешённых. На подбор не
## влияет вовсе (_tags_cover сравнивает сырые StringName), нужен только
## инструментам: показать дизайнеру, что значит `vertical_hub`, и отличить
## настоящий тег от опечатки. null = описаний нет, облака тегов работают как
## раньше. См. RS_RoomTagCatalog.
@export var tag_catalog: RS_RoomTagCatalog

## Запасной пресет, когда ни один не подошёл (напр. портальной комнаты с нужными
## тегами нет вовсе). Может быть null — тогда select_preset вернёт null и
## генератор оставит узлу заранее проставленный placeholder.
@export var fallback: RS_RoomPreset

## Пресет домашнего узла (hub.tscn) — данные для инструментов (Room Wizard,
## инлайн-редактор «Генератора мира»), НЕ участник автоподбора. Намеренно вне
## presets: хаб ставит уникальная комната конфига генерации
## (data/world_gen_config.tres), а попади он сюда, обычные узлы получали бы
## вторые хабы — у него пустые tags и нет портала, то есть он проходит все
## жёсткие фильтры.
@export var hub: RS_RoomPreset


## Причины отсева/прохода пресета — ключи протокола explain_selection.
const REASON_NO_SCENE := "нет сцены"
const REASON_TAGS := "теги"
const REASON_ROOM_TYPE := "тип комнаты"
## Пресет прошёл все жёсткие фильтры и участвовал во взвешенном броске.
const REASON_CANDIDATE := "дошёл до весов"
const REASON_SELECTED := "выбран"
const REASON_FALLBACK := "fallback"

## Портал комнаты не совпал с нуждой узла.
const REASON_PORTAL := "портал"
## Пресет занят уникальной комнатой.
const REASON_UNIQUE := "уникальная"
## Тег, которым пресет объявляет портал, а узел — нужду в нём. Единственный
## структурный тег, который подбор сверяет: level_exit на пресетах остался от
## прежней генерации (выход теперь уникальная комната), и сверять его значило
## бы вернуть специфичность, от которой подбор ушёл.
const PORTAL_TAG := &"vertical_hub"
const IGNORED_STRUCTURAL: Array[StringName] = [&"level_exit"]


## Комната для узла или fallback/null. rng должен быть тем же, что и во всей
## генерации, — иначе подстановка перестанет быть детерминированной по сиду.
## [param excluded] — пресеты уникальных комнат: выход, стоящий в пуле, иначе
## выпадал бы обычным узлам вторым и третьим финишем.
func select_preset(
	node: RS_LevelNode, rng: RandomNumberGenerator, excluded: Array[RS_RoomPreset] = []
) -> RS_RoomPreset:
	return _select(node, rng, excluded, null)


## Тот же отбор, но с протоколом: на каком шаге отсеялся каждый пресет. Для
## редакторского инструмента — правки весов часто ни на что не влияют, потому что
## конкуренты отсеялись раньше, по порталу или тегам.
## Возвращает { "preset": RS_RoomPreset|null, "reasons": { display_name: причина } }.
func explain_selection(
	node: RS_LevelNode, rng: RandomNumberGenerator, excluded: Array[RS_RoomPreset] = []
) -> Dictionary:
	var reasons := {}
	var preset := _select(node, rng, excluded, reasons)
	return {"preset": preset, "reasons": reasons}


## Общий код отбора для select_preset и explain_selection: разъезд между «как
## выбирается на самом деле» и «как объясняет инструмент» был бы хуже дублирования.
## [param reasons] Dictionary для протокола или null. Протокол заодно глушит
## push_warning: инструмент гоняет сотни узлов, редактор утонул бы в предупреждениях.
func _select(
	node: RS_LevelNode, rng: RandomNumberGenerator, excluded: Array[RS_RoomPreset], reasons: Variant
) -> RS_RoomPreset:
	var needs_portal := node.has_tag(PORTAL_TAG)
	var candidates: Array[RS_RoomPreset] = []
	for p: RS_RoomPreset in presets:
		if p == null:
			continue
		if p.scene == null or RS_RoomLayout.door_count_of_scene(p.scene.resource_path) == 0:
			_note(reasons, p, REASON_NO_SCENE)
		elif excluded.has(p):
			_note(reasons, p, REASON_UNIQUE)
		elif p.tags.has(PORTAL_TAG) != needs_portal:
			_note(reasons, p, REASON_PORTAL)
		elif not _tags_cover(p.tags, _required_tags(node)):
			_note(reasons, p, REASON_TAGS)
		else:
			candidates.append(p)
			_note(reasons, p, REASON_CANDIDATE)

	if candidates.is_empty():
		# Fallback фильтров не проходит — это запасной выход, а не кандидат. С
		# тегами он может разойтись без последствий, с порталом — нет: портальный
		# узел без портала в сцене оставляет переход оборванным (сосед по ребру
		# получит портал сюда, а обратного не будет), лишний портал — мёртвый
		# посреди пола. Такое уже не деградация, а сломанный забег, поэтому ошибка,
		# а не предупреждение; validate() ловит это заранее.
		var fallback_portal := fallback != null and fallback.tags.has(PORTAL_TAG)
		if reasons == null:
			if fallback_portal != needs_portal:
				push_error(
					"RS_RoomPresetLibrary: нет комнаты для узла '%s' (портал=%s, теги=%s), а fallback «%s» %s портала — переход оборвётся"
					% [node.id, needs_portal, str(node.tags), _fallback_label(), "без" if needs_portal else "с лишним"]
				)
			else:
				push_warning(
					"RS_RoomPresetLibrary: нет комнаты для узла '%s' (портал=%s, теги=%s) — fallback"
					% [node.id, needs_portal, str(node.tags)]
				)
		_note(reasons, fallback, REASON_FALLBACK)
		return fallback

	var chosen := _weighted_pick(_prefer_room_type(candidates, node.room_type, reasons), rng)
	_note(reasons, chosen, REASON_SELECTED)
	return chosen


## Теги узла, которые подбор требует от пресета: всё, кроме структурных, которые
## он сверяет сам (портал) или не сверяет вовсе.
func _required_tags(node: RS_LevelNode) -> Array[StringName]:
	var required: Array[StringName] = []
	for tag in node.tags:
		if tag != PORTAL_TAG and not IGNORED_STRUCTURAL.has(tag):
			required.append(tag)
	return required


## Сужает группу до пресетов загаданного узлу типа — но ТОЛЬКО если такие в ней
## есть; иначе возвращает группу нетронутой. Отсюда и «предпочтение, а не
## фильтр»: пока арсеналов нужного размера не нарисовали, узел-арсенал спокойно
## получает обычную комнату, а не остаётся на placeholder.
##
## Пустой загаданный тип — полноценный случай, а не «всё равно»: безликий узел
## предпочитает безликие пресеты. Иначе тематическая комната лезла бы в каждый
## непомеченный узел и перестала бы читаться как особенная.
func _prefer_room_type(
	pool: Array[RS_RoomPreset], wanted: StringName, reasons: Variant
) -> Array[RS_RoomPreset]:
	var matching: Array[RS_RoomPreset] = []
	for p in pool:
		if p.room_type == wanted:
			matching.append(p)
	if matching.is_empty():
		return pool

	for p in pool:
		if p.room_type != wanted:
			_note(reasons, p, REASON_ROOM_TYPE)
	return matching


func _note(reasons: Variant, preset: RS_RoomPreset, reason: String) -> void:
	if reasons == null or preset == null:
		return  # обычный прогон генерации — протокол не ведём
	(reasons as Dictionary)[_preset_label(preset)] = reason


func _fallback_label() -> String:
	return _preset_label(fallback) if fallback else "null"


func _preset_label(preset: RS_RoomPreset) -> String:
	if preset.display_name != "":
		return preset.display_name
	return preset.resource_path.get_file().get_basename()


## Каждый тег узла должен присутствовать в тегах пресета (node ⊆ preset).
func _tags_cover(preset_tags: Array, node_tags: Array) -> bool:
	for t in node_tags:
		if not preset_tags.has(t):
			return false
	return true


## Взвешенный бросок по авторским весам. Все веса нулевые — равновероятно:
## пресет с весом 0 всё ещё кандидат, если больше некому.
func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> RS_RoomPreset:
	var weights: Array[float] = []
	for p: RS_RoomPreset in pool:
		weights.append(p.weight)
	if WeightedPick.total(weights) <= 0.0:  # все веса нулевые — равновероятно
		return pool[rng.randi_range(0, pool.size() - 1)]
	return pool[WeightedPick.index(weights, rng.randf())]


## Отладочная проверка сцен пресетов: сверяет заявленный slot_count с фактическим
## числом дверей, ловит двери на одной стене (вторая никогда не получит ребро при
## раскладке слоя) и дубли slot_id (тот всё ещё служит детерминированным ключом
## сортировки). Возвращает список расхождений — пусто, если всё сходится.
## Зовите из теста/инструмента, не в горячем пути генерации.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if type_catalog:
		problems.append_array(type_catalog.validate())
	var has_portal := false
	var has_plain := false
	for p in presets:
		if p == null:
			problems.append("null-пресет в списке")
			continue
		problems.append_array(validate_preset(p))
		if p.tags.has(PORTAL_TAG):
			has_portal = true
		else:
			has_plain = true

	# Портальные и обычные узлы есть в каждом забеге, и оба вида обязан кто-то
	# закрыть: иначе всё уходит в fallback, который фильтры не проходит (см.
	# _select) и у которого портал есть только одним способом из двух.
	if not has_portal:
		problems.append("нет ни одного пресета с тегом «%s» — переходы между этажами и слоями оборвутся" % PORTAL_TAG)
	if not has_plain:
		problems.append("нет ни одного пресета без портала — обычные узлы получат мёртвые порталы")

	# fallback и hub в автоподбор не ходят, поэтому их сцены не проверил бы никто:
	# fallback встаёт на узел, когда подбор пуст, hub берут инструменты. Разошедшийся
	# с дверями сцены slot_count у них тот же тихий обрыв, что у обычного пресета.
	for extra: RS_RoomPreset in [fallback, hub]:
		if extra:
			problems.append_array(validate_preset(extra))
	return problems


## Проверка одного пресета — вынесена, чтобы редакторский инструмент мог
## показывать проблемы построчно, рядом с самим пресетом.
func validate_preset(preset: RS_RoomPreset) -> Array[String]:
	var problems: Array[String] = []
	var label := _preset_label(preset)
	if preset.scene == null:
		problems.append("'%s': не назначена scene" % label)
		return problems

	# Тип из-за пределов каталога ломается тихо: пресет остаётся валидным,
	# просто его никогда никому не предпочтут — узлам такой тип не загадывается.
	if preset.room_type != &"" and type_catalog and type_catalog.by_id(preset.room_type) == null:
		problems.append(
			"'%s': тип «%s» отсутствует в каталоге — пресет не будет предпочтён никогда"
			% [label, preset.room_type]
		)

	var room := preset.scene.instantiate()
	var doors := RS_RoomLayout.door_entities(room)

	if doors.size() != preset.slot_count:
		problems.append(
			"'%s': slot_count=%d, но в сцене %d дверей с C_DoorSlot"
			% [label, preset.slot_count, doors.size()]
		)

	var by_direction := {}
	var by_slot_id := {}
	for door in doors:
		var direction := RS_RoomLayout.door_direction(door as Node as Node3D, room)
		by_direction[direction] = by_direction.get(direction, 0) + 1
		var slot_id := RS_RoomLayout.slot_id_of(door)
		if slot_id == &"":
			problems.append("'%s': у двери «%s» пустой slot_id" % [label, door.name])
		else:
			by_slot_id[slot_id] = by_slot_id.get(slot_id, 0) + 1

	for direction: StringName in by_direction:
		if by_direction[direction] > 1:
			problems.append(
				"'%s': %d двери на стене «%s» — к стене подходит один тайл коридора, лишние не получат ребра"
				% [label, by_direction[direction], direction]
			)
	for slot_id: StringName in by_slot_id:
		if by_slot_id[slot_id] > 1:
			problems.append("'%s': slot_id «%s» повторяется %d раз" % [label, slot_id, by_slot_id[slot_id]])

	room.free()
	return problems
