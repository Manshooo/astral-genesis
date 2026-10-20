## res://src/levels/procedural/rooms/rs_room_preset_library.gd
## Библиотека пресетов комнат + селектор: select_preset() для каждой обычной комнаты ДО рёбер (рёбер ровно столько, сколько
## дверей в сцене). Подбор: портал (жёстко, тег vertical_hub) → теги узла ⊆ теги пресета (жёстко) → room_type (мягко,
## предпочтение) → веса. Теги и тип — РАЗНЫЕ оси. @tool: иначе в редакторе ресурс грузится плейсхолдером без методов.
## Вики: [[Цикл забега]] (Две оси подбора комнаты).
@tool
class_name RS_RoomPresetLibrary
extends Resource

@export var presets: Array[RS_RoomPreset] = []

## Каталог типов помещений — вторая ось подбора; null = типов нет.
@export var type_catalog: RS_RoomTypeCatalog

## Словарь структурных тегов — ОПИСАНИЯ для инструментов, подбор их не читает (RS_RoomTagCatalog).
@export var tag_catalog: RS_RoomTagCatalog

## Запасной пресет, когда ни один не подошёл; null — узел остаётся с placeholder.
@export var fallback: RS_RoomPreset

## Пресет домашнего узла — для инструментов, НЕ участник автоподбора: у него пустые tags и нет портала, в presets он дал бы обычным узлам вторые хабы.
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
## Тег портала на пресете и нужды в нём на узле — единственный структурный тег, который сверяет подбор (level_exit остался от прежней генерации).
const PORTAL_TAG := &"vertical_hub"
const IGNORED_STRUCTURAL: Array[StringName] = [&"level_exit"]


## Комната для узла или fallback/null; rng тот же, что во всей генерации (детерминизм по сиду). [param excluded] — пресеты уникальных комнат.
func select_preset(
	node: RS_LevelNode, rng: RandomNumberGenerator, excluded: Array[RS_RoomPreset] = []
) -> RS_RoomPreset:
	return _select(node, rng, excluded, null)


## Тот же отбор с протоколом: на каком шаге отсеялся каждый пресет. Возвращает { "preset": ..., "reasons": { display_name: причина } }.
func explain_selection(
	node: RS_LevelNode, rng: RandomNumberGenerator, excluded: Array[RS_RoomPreset] = []
) -> Dictionary:
	var reasons := {}
	var preset := _select(node, rng, excluded, reasons)
	return {"preset": preset, "reasons": reasons}


## Общий код отбора для select_preset и explain_selection. [param reasons] — Dictionary протокола или null; протокол глушит push_warning.
func _select(
	node: RS_LevelNode, rng: RandomNumberGenerator, excluded: Array[RS_RoomPreset], reasons: Variant
) -> RS_RoomPreset:
	var needs_portal := node.has_tag(PORTAL_TAG)
	var candidates: Array[RS_RoomPreset] = []
	for p: RS_RoomPreset in presets:
		if p == null:
			continue
		if p.scene == null or not _has_doors(p):
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
		# Fallback фильтров не проходит. С тегами может разойтись, с порталом — нет: оборванный переход или мёртвый портал — сломанный забег, поэтому ошибка; validate() ловит заранее.
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


## Теги узла, которые подбор требует от пресета (без структурных).
func _required_tags(node: RS_LevelNode) -> Array[StringName]:
	var required: Array[StringName] = []
	for tag in node.tags:
		if tag != PORTAL_TAG and not IGNORED_STRUCTURAL.has(tag):
			required.append(tag)
	return required


## Сужает группу до пресетов загаданного типа, но только если такие есть (предпочтение, не фильтр). Пустой тип — полноценный случай: безликий узел предпочитает безликие пресеты.
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


## Каждый тег узла присутствует в тегах пресета.
func _tags_cover(preset_tags: Array, node_tags: Array) -> bool:
	for t in node_tags:
		if not preset_tags.has(t):
			return false
	return true


## Взвешенный бросок; все веса нулевые — равновероятно.
func _weighted_pick(pool: Array, rng: RandomNumberGenerator) -> RS_RoomPreset:
	var weights: Array[float] = []
	for p: RS_RoomPreset in pool:
		weights.append(p.weight)
	if WeightedPick.total(weights) <= 0.0:  # все веса нулевые — равновероятно
		return pool[rng.randi_range(0, pool.size() - 1)]
	return pool[WeightedPick.index(weights, rng.randf())]


## Отладочная проверка сцен: slot_count против числа дверей, двери на одной стене, дубли slot_id. Пусто — всё сходится.
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

	# Портальные и обычные узлы есть в каждом забеге, и оба вида кто-то обязан закрыть (fallback фильтры не проходит, см. _select).
	if not has_portal:
		problems.append("нет ни одного пресета с тегом «%s» — переходы между этажами и слоями оборвутся" % PORTAL_TAG)
	if not has_plain:
		problems.append("нет ни одного пресета без портала — обычные узлы получат мёртвые порталы")

	# fallback и hub в автоподбор не ходят — их сцены не проверил бы никто.
	for extra: RS_RoomPreset in [fallback, hub]:
		if extra:
			problems.append_array(validate_preset(extra))
	return problems


## Проверка одного пресета — построчно, для редакторского инструмента.
func validate_preset(preset: RS_RoomPreset) -> Array[String]:
	var problems: Array[String] = []
	var label := _preset_label(preset)
	if preset.scene == null:
		problems.append("'%s': не назначена scene" % label)
		return problems

	# Тип вне каталога ломается тихо: пресет валиден, но никому не предпочитается.
	if preset.room_type != &"" and type_catalog and type_catalog.by_id(preset.room_type) == null:
		problems.append(
			"'%s': тип «%s» отсутствует в каталоге — пресет не будет предпочтён никогда"
			% [label, preset.room_type]
		)

	var room := preset.scene.instantiate()
	var doors := RS_RoomLayout.door_entities(room)

	var shell := RS_RoomLayout.shell_of(room)
	if shell:
		problems.append_array(_validate_shell(label, preset, shell, doors.size()))
		room.free()
		return problems

	if doors.size() != preset.slot_count:
		problems.append(
			"'%s': slot_count=%d, но в сцене %d дверей с C_DoorSlot"
			% [label, preset.slot_count, doors.size()]
		)

	var by_direction := {}
	var by_slot_id := {}
	for door in doors:
		var direction := RS_RoomLayout.side_name(RS_RoomLayout.door_side(door as Node as Node3D, room))
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


## Проверка комнаты по маске сокетов: ломается пустой кит стен, диапазон дверей шире сокетов, C_DoorSlot в коробке.
func _validate_shell(label: String, preset: RS_RoomPreset, shell: C_RoomShell, scene_doors: int) -> Array[String]:
	var problems: Array[String] = []
	if shell.size.x < 1 or shell.size.y < 1 or shell.size.z < 1:
		problems.append("'%s': footprint коробки %s — нужна хотя бы клетка по каждой оси" % [label, shell.size])
		return problems
	if scene_doors > 0:
		problems.append(
			"'%s': в коробке %d дверей с C_DoorSlot — двери сборной комнаты ставит спавн" % [label, scene_doors]
		)
	# Коробке со стенами в меше без сокетов достались бы все грани — коридор повёл бы в глухую стену.
	if shell.walls_in_shell and shell.door_sockets.is_empty():
		problems.append(
			"'%s': стены в коробке, но сокеты не объявлены (C_RoomShell.door_sockets) — проёмы в меше и есть сокеты"
			% label
		)
	if shell.walls == null:
		problems.append("'%s': у коробки не назначен кит стен (C_RoomShell.walls)" % label)
	else:
		# Стены в меше берут из кита только полотно и заглушку.
		var needed: Array[String] = ["door", "plug"]
		if not shell.walls_in_shell:
			needed = ["door_wall", "blank_wall", "door"]
			if shell.size.y > 1:
				needed.append("upper_wall")
		var missing: Array[String] = []
		for field in needed:
			if shell.walls.get(field) == null:
				missing.append(field)
		if not missing.is_empty():
			problems.append("'%s': в ките стен нет %s" % [label, ", ".join(missing)])
	# Сокет не на наружной грани: раскладка найдёт место, спавн стены — нет (RS_RoomWallKit.assemble).
	var box := SquareGridTopology.box(Vector3i.ZERO, shell.size)
	var topology := SquareGridTopology.new()
	for face in shell.door_sockets:
		var cell := GridTopology.face_cell(face)
		var outward := face.w >= 0 and face.w < SquareGridTopology.SIDE_COUNT
		if not box.has(cell) or not outward or box.has(topology.neighbour(cell, face.w)):
			problems.append("'%s': сокет %s — не наружная грань footprint %s" % [label, face, shell.size])
	problems.append_array(_validate_exits(label, shell, box, topology))
	var sockets := RS_RoomLayout.socket_count_of_scene(preset.scene.resource_path)
	if preset.doors_min < 1 or preset.doors_min > preset.doors_max or preset.doors_max > sockets:
		problems.append(
			"'%s': дверей %d..%d, а сокетов у footprint %s — %d; нужно 1 ≤ min ≤ max ≤ сокетов"
			% [label, preset.doors_min, preset.doors_max, shell.size, sockets]
		)
	# Не больше одной двери на сторону (RS_CorridorPlanner._pick_sockets): вторая — коридор вдоль стены, обволакивание.
	var sides := _socket_sides(RS_RoomLayout.sockets_of_shell(shell))
	if preset.doors_max > sides:
		problems.append(
			"'%s': дверей до %d, а сторон с сокетами %d — дверь ставится по одной на сторону"
			% [label, preset.doors_max, sides]
		)
	return problems


## Грань выхода ломается тихо: не на периметре, совпала с сокетом, без door_sockets, без exit_door в ките.
func _validate_exits(label: String, shell: C_RoomShell, box: Array[Vector3i], topology: SquareGridTopology) -> Array[String]:
	var problems: Array[String] = []
	if shell.exit_sockets.is_empty():
		return problems
	if shell.door_sockets.is_empty():
		problems.append("'%s': у коробки есть выход наружу, но сокеты не объявлены (C_RoomShell.door_sockets)" % label)
	if shell.walls and shell.walls.exit_door == null:
		problems.append("'%s': у коробки есть выход наружу, а в ките стен нет exit_door" % label)
	for face in shell.exit_sockets:
		var cell := GridTopology.face_cell(face)
		var outward := face.w >= 0 and face.w < SquareGridTopology.SIDE_COUNT
		if not box.has(cell) or not outward or box.has(topology.neighbour(cell, face.w)):
			problems.append("'%s': выход %s — не наружная грань footprint %s" % [label, face, shell.size])
		elif shell.door_sockets.has(face):
			problems.append("'%s': выход %s совпадает с сокетом двери" % [label, face])
	return problems


## Сколько сторон с сокетами — каждая сторона на каждом уровне отдельно.
static func _socket_sides(sockets: Array[Vector4i]) -> int:
	var sides := {}
	for face in sockets:
		sides[Vector2i(face.y, face.w)] = true
	return sides.size()


## Может ли комната получить хотя бы одну дверь: у сборной обещает диапазон пресета, у остальных C_DoorSlot в сцене.
static func _has_doors(preset: RS_RoomPreset) -> bool:
	var path := preset.scene.resource_path
	if RS_RoomLayout.shell_of_scene(path):
		return preset.doors_max >= 1 and RS_RoomLayout.socket_count_of_scene(path) > 0
	return RS_RoomLayout.door_count_of_scene(path) > 0
