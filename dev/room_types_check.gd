extends Node
## Проверка ВТОРОЙ оси подбора комнат — типа помещения (`RS_RoomTypeCatalog`,
## `RS_RoomPreset.room_type`, `RS_LevelNode.room_type`).
## Запуск: godot --headless dev/room_types_check.tscn
##
## Инвариант, ради которого проверка написана, ломается тихо и уже ломался
## однажды на тегах: тип и структурные `tags` — РАЗНЫЕ оси. Стоит типу начать
## работать как тег — фильтром и слагаемым специфичности, — и комнаты с типом
## либо перестанут выпадать вовсе, либо начнут требоваться жёстко. Ни то, ни
## другое не бросает ошибку: генератор просто выдаёт другой комплекс.
##
## Библиотека для отбора собирается ЗДЕСЬ, из настоящих сцен реальных пресетов:
## поведение подбора нужно поставить в заранее известные условия («в группе есть
## ровно два кандидата, один типизированный»), а на живой библиотеке такие
## условия зависят от контента и разъедутся при первой же новой комнате.

## Сцена, которой хватает на любой пресет проверки: важен не её вид, а то, что
## `select_preset` отсеивает пресеты без сцены раньше всех прочих правил.
const PROBE_SCENE := "res://src/levels/procedural/rooms/default/default_room.tscn"

const SEED_COUNT := 10

var _ok := 0
var _fail := 0


func _ready() -> void:
	_run()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	var library := GameConfig.config.room_preset_library as RS_RoomPresetLibrary
	if library == null:
		_check("библиотека пресетов назначена в game_config", false, "room_preset_library == null")
		return

	_check_catalog(library.type_catalog)
	_check_depth_rolls()
	_check_selection()
	_check_generation(library)


# ---------------------------------------------------------------------------
# 1. Каталог
# ---------------------------------------------------------------------------


func _check_catalog(catalog: RS_RoomTypeCatalog) -> void:
	_check("каталог типов назначен библиотеке", catalog != null, "type_catalog == null")
	if catalog == null:
		return

	var problems := catalog.validate()
	_check("каталог без расхождений", problems.is_empty(), "; ".join(problems))
	_check("в каталоге есть типы", not catalog.types.is_empty(), "types пуст")

	# Тип, чей отрезок глубин не пересекается с DEPTHS, не выпадет никогда —
	# validate() этого не ловит (сам по себе отрезок корректен), а комната
	# «есть в каталоге, но не встречается» выглядит как баг подбора.
	var reachable := 0
	for type: RS_RoomType in catalog.types:
		for depth: int in RS_LevelGraph.DEPTHS:
			if type.covers_depth(depth):
				reachable += 1
				break
	_check(
		"каждый тип достижим хотя бы на одном слое комплекса",
		reachable == catalog.types.size(),
		"%d типов из %d не попадают ни в один слой DEPTHS" % [
			catalog.types.size() - reachable, catalog.types.size()],
	)


# ---------------------------------------------------------------------------
# 2. Розыгрыш типа по глубине
# ---------------------------------------------------------------------------


func _check_depth_rolls() -> void:
	var catalog := RS_RoomTypeCatalog.new()
	catalog.untyped_weight = 0.0  # чтобы «без типа» не съедало всю выборку
	catalog.types = [
		_make_type(&"deep", 3, 4),
		_make_type(&"shallow", 0, 1),
	]

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var out_of_range := 0
	var seen := {}
	for i in 400:
		var depth: int = RS_LevelGraph.DEPTHS[i % RS_LevelGraph.DEPTHS.size()]
		var picked := catalog.pick_for_depth(depth, rng)
		if picked == &"":
			continue
		seen[picked] = true
		var type := catalog.by_id(picked)
		if type == null or not type.covers_depth(depth):
			out_of_range += 1
	_check(
		"выпавший тип всегда покрывает глубину узла",
		out_of_range == 0,
		"%d выпадений мимо своего отрезка глубин" % out_of_range,
	)
	_check("оба типа хоть раз выпали", seen.size() == 2, "выпало типов: %d" % seen.size())

	# Слой 2 не покрывает ни один из двух типов — здесь обязан быть «без типа».
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	var non_empty := 0
	for i in 100:
		if catalog.pick_for_depth(2, rng2) != &"":
			non_empty += 1
	_check(
		"на глубине без подходящих типов выпадает «без типа»",
		non_empty == 0,
		"%d выпадений типа там, где ни один не подходит" % non_empty,
	)

	# Бросок обязан тратить rng ОДИНАКОВО независимо от исхода: генератор гоняет
	# один rng на всю генерацию, и пропуск броска на «пустой» глубине сдвинул бы
	# всё, что разыгрывается после, — граф перестал бы быть функцией сида.
	var a := RandomNumberGenerator.new()
	a.seed = 42
	for i in 20:
		catalog.pick_for_depth(2, a)  # глубина без подходящих типов
	var b := RandomNumberGenerator.new()
	b.seed = 42
	for i in 20:
		catalog.pick_for_depth(4, b)  # глубина с подходящим типом
	_check(
		"бросок тратит rng одинаково при любом исходе",
		is_equal_approx(a.randf(), b.randf()),
		"состояния rng разошлись — генерация перестанет быть функцией сида",
	)


# ---------------------------------------------------------------------------
# 3. Подбор пресета: тип — предпочтение, а не фильтр
# ---------------------------------------------------------------------------


func _check_selection() -> void:
	var plain := _make_preset("Безликая", &"", [])
	var arsenal := _make_preset("Арсенал", &"arsenal", [])
	var library := _make_library([plain, arsenal])

	var rng := RandomNumberGenerator.new()
	rng.seed = 3

	# Узел загадал арсенал, арсенал в группе есть — предпочтение работает.
	var wants_arsenal := _make_node(&"arsenal", [])
	_check(
		"узел с типом получает пресет своего типа",
		_always_picks(library, wants_arsenal, rng, arsenal),
		"выбор ушёл к безликому пресету, хотя типизированный подходил",
	)

	# Узел без типа предпочитает безликое: иначе тематическая комната лезла бы
	# в каждый непомеченный узел и перестала бы читаться как особенная.
	var wants_nothing := _make_node(&"", [])
	_check(
		"узел без типа предпочитает безликий пресет",
		_always_picks(library, wants_nothing, rng, plain),
		"типизированный пресет протёк в узел без типа",
	)

	# Тип, которого нет ни у одного пресета: ПРЕДПОЧТЕНИЕ, а не фильтр —
	# комната всё равно должна встать, иначе забег стал бы несобираемым, стоит
	# завести в каталоге тип раньше, чем нарисовать под него комнату.
	var wants_missing := _make_node(&"proving_ground", [])
	var fell_through := library.select_preset(wants_missing, rng)
	_check(
		"тип без единого пресета не оставляет узел без комнаты",
		fell_through != null and fell_through != library.fallback,
		"вернулся %s" % ("null" if fell_through == null else "fallback"),
	)

	# Тип не должен подменять собой жёсткие фильтры: пресет своего типа, но
	# слишком маленький, обязан отсеяться по вместимости, как и любой другой.
	var small_arsenal := _make_preset("Арсенал-каморка", &"arsenal", [])
	small_arsenal.slot_count = 1
	var big_plain := _make_preset("Большая безликая", &"", [])
	big_plain.slot_count = 4
	var library2 := _make_library([small_arsenal, big_plain])
	var wide_node := _make_node(&"arsenal", [])
	for i in 3:
		wide_node.connections.append(RS_LevelConnection.new())
	_check(
		"тип не пробивает фильтр вместимости",
		library2.select_preset(wide_node, rng) == big_plain,
		"узлу с 3 рёбрами достался пресет на 1 слот — тип обошёл вместимость",
	)

	# Специфичность считается по ТЕГАМ и только по ним: типизированный пресет не
	# должен становиться «богаче» и проигрывать безликому там, где тип совпал.
	var typed_hub := _make_preset("Хаб-арсенал", &"arsenal", [&"floor_hub"])
	var plain_hub := _make_preset("Хаб безликий", &"", [&"floor_hub"])
	var library3 := _make_library([typed_hub, plain_hub])
	var hub_node := _make_node(&"arsenal", [&"floor_hub"])
	_check(
		"тип не участвует в специфичности по тегам",
		_always_picks(library3, hub_node, rng, typed_hub),
		"типизированный пресет проиграл безликому при равных тегах",
	)


# ---------------------------------------------------------------------------
# 4. Настоящая генерация
# ---------------------------------------------------------------------------


func _check_generation(library: RS_RoomPresetLibrary) -> void:
	var catalog := library.type_catalog
	var lying := 0
	var foreign := 0
	var typed_nodes := 0
	var known_ids := catalog.ids() if catalog else ([] as Array[StringName])

	for s in SEED_COUNT:
		var graph := RS_LevelGraph.new().generate_run(s, library)
		for node: RS_LevelNode in graph.nodes.values():
			if node.room_type != &"":
				typed_nodes += 1
			# После генерации в room_type обязан лежать тип ФАКТИЧЕСКИ вставшей
			# комнаты, а не загаданный: карта и игровая логика читают это поле.
			var preset := _preset_of_scene(library, node.room_scene_path)
			if preset != null and preset.room_type != node.room_type:
				lying += 1
			# Оси не смешаны: ключ типа не должен оказаться среди структурных
			# тегов узла — это ровно та ошибка, ради которой поля и разведены.
			for tag: StringName in node.tags:
				if known_ids.has(tag):
					foreign += 1

	_check(
		"тип узла после генерации — тип вставшей комнаты, а не загаданный",
		lying == 0,
		"%d узлов подписаны не тем типом, что у их пресета" % lying,
	)
	_check(
		"ключи типов не протекли в структурные теги узлов",
		foreign == 0,
		"%d тегов узлов совпали с ключами каталога — оси смешались" % foreign,
	)
	_check(
		"типизированные комнаты в комплексе встречаются",
		typed_nodes > 0,
		"ни одной комнаты с типом на %d сидах — предпочтение не работает" % SEED_COUNT,
	)

	# Детерминированность: забег хранит сид, а не комнаты, и второй проход по
	# тому же сиду обязан дать те же типы — иначе загруженная игра окажется в
	# другом комплексе.
	var first := RS_LevelGraph.new().generate_run(0, library)
	var second := RS_LevelGraph.new().generate_run(0, library)
	var mismatched := 0
	for id: StringName in first.nodes:
		if first.nodes[id].room_type != second.nodes[id].room_type:
			mismatched += 1
	_check(
		"типы детерминированы по сиду",
		mismatched == 0,
		"%d узлов получили разный тип на одном сиде" % mismatched,
	)

	# Домашний узел получает сцену хаба в обход отбора — тип обязан описывать
	# именно её, иначе на карте дом подпишется случайным складом.
	var home := first.get_node_data(first.entry_node_id)
	var hub_type: StringName = library.hub.room_type if library.hub else &""
	_check(
		"домашний узел подписан типом хаба, а не загаданным",
		home != null and home.room_type == hub_type,
		"у дома тип «%s», у пресета хаба «%s»" % [
			home.room_type if home else "?", hub_type],
	)


# ---------------------------------------------------------------------------
# Помощники
# ---------------------------------------------------------------------------


## Один и тот же исход подряд: подбор внутри группы — взвешенный бросок, и
## одиночная проба доказала бы разве что везение.
func _always_picks(
	library: RS_RoomPresetLibrary,
	node: RS_LevelNode,
	rng: RandomNumberGenerator,
	expected: RS_RoomPreset,
) -> bool:
	for i in 50:
		if library.select_preset(node, rng) != expected:
			return false
	return true


func _preset_of_scene(library: RS_RoomPresetLibrary, scene_path: String) -> RS_RoomPreset:
	for preset: RS_RoomPreset in library.presets:
		if preset and preset.scene and preset.scene.resource_path == scene_path:
			return preset
	if library.hub and library.hub.scene and library.hub.scene.resource_path == scene_path:
		return library.hub
	return null


func _make_type(id: StringName, depth_min: int, depth_max: int) -> RS_RoomType:
	var type := RS_RoomType.new()
	type.id = id
	type.depth_min = depth_min
	type.depth_max = depth_max
	return type


func _make_preset(label: String, room_type: StringName, tags: Array[StringName]) -> RS_RoomPreset:
	var preset := RS_RoomPreset.new()
	preset.display_name = label
	preset.scene = load(PROBE_SCENE)
	preset.room_type = room_type
	preset.tags = tags
	preset.slot_count = 2
	return preset


func _make_library(presets: Array) -> RS_RoomPresetLibrary:
	var library := RS_RoomPresetLibrary.new()
	for preset: RS_RoomPreset in presets:
		library.presets.append(preset)
	library.fallback = _make_preset("Запасная", &"", [])
	return library


func _make_node(room_type: StringName, tags: Array[StringName]) -> RS_LevelNode:
	var node := RS_LevelNode.new()
	node.id = &"probe"
	node.room_type = room_type
	node.tags = tags
	node.connections.append(RS_LevelConnection.new())
	return node


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
