## res://src/levels/procedural/rooms/rs_room_preset_library.gd
## Библиотека пресетов комнат + селектор. Генератор на финальном
## проходе зовёт select_preset() для каждого узла, когда его connections уже
## полностью проставлены, и подставляет узлу сцену комнаты.
##
## Критерии подбора:
##   1. Вместимость (жёстко): preset.slot_count >= node.connections.size().
##   2. Теги (жёстко): node.tags ⊆ preset.tags.
##   3. Специфичность (мягко): среди кандидатов — с минимумом лишних тегов.
##      Не даёт «богатым» пресетам (напр. с порталом) протекать в узлы, которым
##      это не нужно.
##   4. Впритык по дверям (мягко): взвешенный рандом внутри группы из шага 3
##      смещён в пользу пресетов с МИНИМАЛЬНЫМ избытком слотов над нужным числом
##      рёбер (EXCESS_SLOT_DECAY) — иначе комната на 4 двери, где реально
##      используются 2, а остальные заварены, выбиралась бы так же часто, как
##      комната впритык на 2.
## @tool — иначе в редакторе ресурс грузится ПЛЕЙСХОЛДЕРОМ и его методы позвать
## нельзя («Attempt to call a method on a placeholder instance»). Док «Генератор»
## зовёт select_preset/explain_selection/validate прямо из редактора.
@tool
class_name RS_RoomPresetLibrary
extends Resource

@export var presets: Array[RS_RoomPreset] = []

## Запасной пресет, когда ни один не подошёл (напр. у узла рёбер больше, чем
## слотов у любой комнаты). Может быть null — тогда select_preset вернёт null и
## генератор оставит узлу заранее проставленный placeholder.
@export var fallback: RS_RoomPreset

## Пресет домашнего узла (hub.tscn) — данные для инструментов (Room Wizard,
## инлайн-редактор «Генератора мира»), НЕ участник автоподбора. Намеренно вне
## presets: RS_LevelGraph.generate_run ставит хабу сцену напрямую по пути
## (HUB_ROOM_SCENE), в обход select_preset, — а попади hub сюда, у него пустые
## tags и slot_count=1 сделали бы его пресетом-победителем для ЛЮБОГО
## непомеченного узла-тупика во всём графе (пустой node.tags — подмножество
## чего угодно, а меньше лишних тегов не бывает: специфичность выбрала бы hub
## раньше остальных однодверных комнат). weight=0 здесь не спасает — если hub
## окажется единственным кандидатом группы, _weighted_pick трактует «все веса
## нулевые» как равновероятный выбор и всё равно его вернёт.
@export var hub: RS_RoomPreset


## Причины отсева/прохода пресета — ключи протокола explain_selection.
const REASON_NO_SCENE := "нет сцены"
const REASON_CAPACITY := "вместимость"
const REASON_TAGS := "теги"
const REASON_SPECIFICITY := "специфичность"
## Пресет прошёл все жёсткие фильтры и участвовал во взвешенном броске.
const REASON_CANDIDATE := "дошёл до весов"
const REASON_SELECTED := "выбран"
const REASON_FALLBACK := "fallback"

## Насколько урезается вес пресета за каждый ЛИШНИЙ дверной слот сверх нужного
## узлу числа рёбер (preset.slot_count - needed). Вес домножается на эту дробь
## В СТЕПЕНИ избытка — один лишний слот делает пресет на порядок менее
## вероятным, два лишних — почти невероятным. Число можно свободно крутить:
## ближе к 0 — избыточные комнаты почти не выбираются, ближе к 1.0 — подбор
## безразличен к размеру (как было до этой правки). Подобрано так, чтобы при
## конкуренции «впритык» vs «на 1 больше» с равными author-весами впритык
## выпадал с вероятностью ~85-90%, как и просили в задаче на завареные двери.
const EXCESS_SLOT_DECAY := 0.15


## Возвращает подходящий пресет для узла или fallback/null. rng должен быть тем
## же, что и во всей генерации, — иначе подстановка перестанет быть
## детерминированной по сиду.
func select_preset(node: RS_LevelNode, rng: RandomNumberGenerator) -> RS_RoomPreset:
	return _select(node, rng, null)


## Тот же отбор, но с протоколом: на каком шаге отсеялся каждый пресет.
## Для редакторского инструмента — правки весов часто ни на что не влияют, потому
## что конкуренты отсеялись раньше, по вместимости или тегам.
## Возвращает { "preset": RS_RoomPreset|null, "reasons": { display_name: причина } }.
func explain_selection(node: RS_LevelNode, rng: RandomNumberGenerator) -> Dictionary:
	var reasons := {}
	var preset := _select(node, rng, reasons)
	return {"preset": preset, "reasons": reasons}


## Общий код отбора для select_preset и explain_selection: разъезд между «как
## выбирается на самом деле» и «как объясняет инструмент» был бы хуже дублирования.
## [param reasons] Dictionary для протокола или null. Протокол заодно глушит
## push_warning: инструмент гоняет сотни узлов, редактор утонул бы в предупреждениях.
func _select(node: RS_LevelNode, rng: RandomNumberGenerator, reasons: Variant) -> RS_RoomPreset:
	var explaining := reasons != null
	var needed := node.connections.size()
	var candidates: Array[RS_RoomPreset] = []
	for p: RS_RoomPreset in presets:
		if p == null:
			continue
		if p.scene == null:
			_note(reasons, p, REASON_NO_SCENE)
		elif p.slot_count < needed:
			_note(reasons, p, REASON_CAPACITY)
		elif not _tags_cover(p.tags, node.tags):
			_note(reasons, p, REASON_TAGS)
		else:
			candidates.append(p)

	if candidates.is_empty():
		if not explaining:
			push_warning(
				"RS_RoomPresetLibrary: нет пресета для узла '%s' (рёбер=%d, теги=%s) — fallback"
				% [node.id, needed, str(node.tags)]
			)
		_note(reasons, fallback, REASON_FALLBACK)
		return fallback

	# Специфичность: меньше всего лишних тегов сверх требуемых узлом.
	# node.tags ⊆ p.tags гарантировано фильтром, теги уникальны → лишних = разница размеров.
	# Инициализация от первого кандидата (список непустой), а не от 0/size — иначе
	# для узла без тегов min_extra залипнет на 0 и best может оказаться пустым.
	var min_extra: int = candidates[0].tags.size() - node.tags.size()
	for p in candidates:
		min_extra = min(min_extra, p.tags.size() - node.tags.size())

	var best: Array[RS_RoomPreset] = []
	for p in candidates:
		if p.tags.size() - node.tags.size() == min_extra:
			best.append(p)
			_note(reasons, p, REASON_CANDIDATE)
		else:
			_note(reasons, p, REASON_SPECIFICITY)

	var chosen := _weighted_pick(best, rng, needed)
	_note(reasons, chosen, REASON_SELECTED)
	return chosen


func _note(reasons: Variant, preset: RS_RoomPreset, reason: String) -> void:
	if reasons == null or preset == null:
		return  # обычный прогон генерации — протокол не ведём
	(reasons as Dictionary)[_preset_label(preset)] = reason


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


## [param needed] — число рёбер узла: если >= 0, вес каждого пресета
## домножается на EXCESS_SLOT_DECAY в степени избытка его slot_count над
## needed (см. константу), смещая бросок в пользу пресетов впритык по дверям.
## -1 отключает смещение (author-вес как есть) — используется, если понадобится
## взвешенный пик вне контекста подбора по узлу.
func _weighted_pick(pool: Array, rng: RandomNumberGenerator, needed: int = -1) -> RS_RoomPreset:
	var effective: Array[float] = []
	var total := 0.0
	for p: RS_RoomPreset in pool:
		var w := maxf(p.weight, 0.0)
		if needed >= 0:
			w *= pow(EXCESS_SLOT_DECAY, maxi(p.slot_count - needed, 0))
		effective.append(w)
		total += w
	if total <= 0.0:  # все веса нулевые — равновероятно
		return pool[rng.randi_range(0, pool.size() - 1)]

	var roll := rng.randf() * total
	var acc := 0.0
	for i in pool.size():
		acc += effective[i]
		if roll <= acc:
			return pool[i]
	return pool[pool.size() - 1]


## Отладочная проверка сцен пресетов: сверяет заявленный slot_count с фактическим
## числом дверей, ловит двери на одной стене (вторая никогда не получит ребро при
## раскладке слоя) и дубли slot_id (тот всё ещё служит детерминированным ключом
## сортировки). Возвращает список расхождений — пусто, если всё сходится.
## Зовите из теста/инструмента, не в горячем пути генерации.
func validate() -> Array[String]:
	var problems: Array[String] = []
	for p in presets:
		if p == null:
			problems.append("null-пресет в списке")
			continue
		problems.append_array(validate_preset(p))
	return problems


## Проверка одного пресета — вынесена, чтобы редакторский инструмент мог
## показывать проблемы построчно, рядом с самим пресетом.
func validate_preset(preset: RS_RoomPreset) -> Array[String]:
	var problems: Array[String] = []
	var label := _preset_label(preset)
	if preset.scene == null:
		problems.append("'%s': не назначена scene" % label)
		return problems

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
				"'%s': %d двери на стене «%s» — лишние не получат ребра при раскладке"
				% [label, by_direction[direction], direction]
			)
	for slot_id: StringName in by_slot_id:
		if by_slot_id[slot_id] > 1:
			problems.append("'%s': slot_id «%s» повторяется %d раз" % [label, slot_id, by_slot_id[slot_id]])

	room.free()
	return problems
