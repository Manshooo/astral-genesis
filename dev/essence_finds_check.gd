extends "res://dev/check_harness.gd"
## Проверка находок и тайников эссенции (карточка «Источники эссенции»):
## расстановка по сиду, взятие, память о взятом, навык «Сбор эссенции».
##
## Всё здесь ломается тихо. Находка, расставленная от общего rng, не ломает
## ничего — только сдвигает мир при каждой правке шанса. Награда без отметки
## выдаётся заново после каждой загрузки слоя. Тайник не в тупике — просто
## «лежит где-то». Навык, который не доезжает до множителя, выглядит как
## честный минимум.
##
## Бросок проверяется функцией (LayerFinds.roll — чистая функция сида и ключа), а
## расстановка — настоящим RunManager: тупики и маркеры берутся из плана и сцен.
## Сейвы забега, навыков и Архитектора снимаются байтами и возвращаются: взятие
## пишет во все три.
##
## Запускать: godot --headless dev/essence_finds_check.tscn

const RUN_SEED := 424242
const FIND_SCENE := "res://src/entities/essence_find/e_essence_find.tscn"
const SKILL_ID := &"essence_gathering"
## Сколько ключей бросать при проверке частоты: на 400 разброс доли шанса около
## 2.5 %, допуск 10 % — со многократным запасом, но «всегда» и «никогда» не пройдут.
const SAMPLE := 400

var _world_bytes := PackedByteArray()
var _skills_bytes := PackedByteArray()
var _architect_bytes := PackedByteArray()
var _world_save: RS_WorldSave
var _skill_save: PlayerSkillSave
var _architect_save: PlayerSkillSave
var _find_chance: float
var _cache_chance: float


func _ready() -> void:
	# Сначала бэкап: взятие находки пишет на диск, и снятый позже застал бы
	# файлы уже испорченными.
	_world_bytes = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_skills_bytes = FileAccess.get_file_as_bytes(SkillManager._save_path)
	_architect_bytes = FileAccess.get_file_as_bytes(ArchitectManager._save_path)
	_world_save = WorldSave.save
	_skill_save = SkillManager.save
	_architect_save = ArchitectManager.save
	_find_chance = GameConfig.config.essence_find_chance
	_cache_chance = GameConfig.config.essence_cache_chance

	var world := _new_world()
	_add_systems(world, "gameplay", [S_RoomPresence.new()])
	_add_systems(world, "physics", [S_DoorMotion.new()])
	world.add_observer(O_ApplySkillEffects.new())

	_check_roll()
	_check_data()
	await _check_world()

	_restore()
	_finish()


# --- 1. Бросок ----------------------------------------------------------------


func _keys(prefix: String) -> Array[StringName]:
	var keys: Array[StringName] = []
	for i in SAMPLE:
		keys.append(LayerFinds.cache_key(StringName("%s_%d" % [prefix, i]), Vector3i(i, 0, -i)))
	return keys


func _rolls(seed_value: int, depth: int, keys: Array[StringName], chance: float) -> Array[int]:
	var config := GameConfig.config
	var result: Array[int] = []
	for key in keys:
		result.append(
			LayerFinds.roll(seed_value, depth, key, chance, config.essence_cache_min, config.essence_cache_max)
		)
	return result


func _check_roll() -> void:
	var config := GameConfig.config
	var keys := _keys("corridor")
	var first := _rolls(RUN_SEED, 1, keys, config.essence_cache_chance)
	_check("бросок — функция сида, слоя и ключа: тот же вход, тот же результат",
		first == _rolls(RUN_SEED, 1, keys, config.essence_cache_chance), "")
	_check("другой сид раскладывает находки иначе",
		first != _rolls(RUN_SEED + 1, 1, keys, config.essence_cache_chance), "")
	_check("и другой слой — иначе: клетки всех слоёв начинаются с одной точки",
		first != _rolls(RUN_SEED, 2, keys, config.essence_cache_chance), "")

	var out_of_range: Array[String] = []
	var present := 0
	for amount in first:
		if amount == 0:
			continue
		present += 1
		if amount < config.essence_cache_min or amount > config.essence_cache_max:
			out_of_range.append(str(amount))
	_check("сумма тайника в диапазоне из данных", out_of_range.is_empty(), ", ".join(out_of_range.slice(0, 4)))
	var share := float(present) / SAMPLE
	_check("тайник бывает не всегда и не никогда: доля %.2f при шансе %.2f" % [share, config.essence_cache_chance],
		absf(share - config.essence_cache_chance) < 0.1, "доля %.2f" % share)
	_check("шанс 0 — ни одной находки", _rolls(RUN_SEED, 1, keys, 0.0).count(0) == SAMPLE, "")
	_check("шанс 1 — находка в каждом месте", _rolls(RUN_SEED, 1, keys, 1.0).count(0) == 0, "")

	# Правка шанса в данных не должна перемешивать суммы тех находок, что остались.
	var always := _rolls(RUN_SEED, 1, keys, 1.0)
	var half := _rolls(RUN_SEED, 1, keys, 0.5)
	var shifted := 0
	for i in SAMPLE:
		if half[i] != 0 and half[i] != always[i]:
			shifted += 1
	_check("сумма находки не зависит от шанса", shifted == 0, "сдвинулось %d" % shifted)

	var find_rolls: Array[int] = []
	for key in keys:
		find_rolls.append(
			LayerFinds.roll(RUN_SEED, 1, key, 1.0, config.essence_find_min, config.essence_find_max)
		)
	_check("находка в комнате — в своём диапазоне",
		find_rolls.min() >= config.essence_find_min and find_rolls.max() <= config.essence_find_max,
		"%d..%d" % [find_rolls.min(), find_rolls.max()])


# --- 2. Данные ------------------------------------------------------------------


func _check_data() -> void:
	var config := GameConfig.config
	_check("диапазоны сумм заданы от меньшего к большему",
		config.essence_find_min <= config.essence_find_max and config.essence_cache_min <= config.essence_cache_max
			and config.essence_find_min > 0 and config.essence_cache_min > 0, "")
	_check("шансы — доли, база навыка — честный минимум, а не ноль и не всё",
		config.essence_find_chance > 0.0 and config.essence_find_chance <= 1.0
			and config.essence_cache_chance > 0.0 and config.essence_cache_chance <= 1.0
			and config.essence_gain_base > 0.0 and config.essence_gain_base < 1.0, "")

	var tree := SkillManager.SKILL_TREE
	var problems := tree.validate()
	_check("дерево навыков без ошибок данных", problems.is_empty(), "; ".join(problems))
	var def := tree.get_definition(SKILL_ID)
	_check("навык «Сбор эссенции» заведён и крутит стат essence_gain",
		def != null and def.modifiers.size() == 1 and def.modifiers[0].stat == C_StatModifiers.ESSENCE_GAIN
			and C_StatModifiers.ALL.has(C_StatModifiers.ESSENCE_GAIN), "")
	if def != null:
		var gains: Array[float] = []
		for rank in range(1, def.max_rank + 1):
			var flat := {}
			var mult := {}
			RS_StatModifier.fold(def.modifiers, rank, flat, mult)
			gains.append(RS_StatModifier.resolve(C_StatModifiers.ESSENCE_GAIN, config.essence_gain_base, flat, mult))
		var rising := gains[0] > config.essence_gain_base
		for i in range(1, gains.size()):
			rising = rising and gains[i] > gains[i - 1]
		_check("каждый ранг поднимает долю, и выше номинала она не уходит",
			rising and gains.back() <= 1.0 + 0.0001, str(gains))
		TranslationServer.set_locale("ru")
		_check("у навыка есть название и описание в переводе",
			TranslationServer.translate(def.display_name) != def.display_name
				and TranslationServer.translate(def.description) != def.description, "")

	var catalog := load("res://data/run_stat_catalog.tres") as RS_RunStatCatalog
	var rows := {}
	for row in catalog.rows:
		rows[row.key] = row
	var missing: Array[String] = []
	for source: StringName in RS_RunStats.SOURCE_TOTALS:
		if RS_RunStats.SOURCE_TOTALS[source] != RS_RunStats.ESSENCE:
			continue
		var row := rows.get(source) as RS_RunStatRow
		if row == null or TranslationServer.translate(row.label_key) == String(row.label_key):
			missing.append(String(source))
	_check("каждый источник эссенции — строка сводки с переводом", missing.is_empty(), ", ".join(missing))

	var scene := (load(FIND_SCENE) as PackedScene).instantiate() as E_EssenceFind
	var prompt := ""
	for resource in scene.component_resources:
		if resource is C_Interactable:
			prompt = (resource as C_Interactable).prompt_text
	var body := scene.get_node_or_null("InteractBody") as CollisionObject3D
	_check("находка — интерактив: подсказка с переводом и тело на слое interactives",
		prompt != "" and TranslationServer.translate(prompt) != prompt
			and body != null and body.collision_layer & 8 != 0, "подсказка «%s»" % prompt)
	_check("брать находку можно и призраком",
		scene.component_resources.all(func(r): return not (r is C_Interactable) or not r.requires_body), "")
	scene.free()

	var library := config.room_preset_library as RS_RoomPresetLibrary
	var markers := 0
	var wrong_type: Array[String] = []
	for preset: RS_RoomPreset in library.presets:
		if preset.scene == null:
			continue
		var room := preset.scene.instantiate()
		for node in room.find_children(LayerFinds.SPOT_PATTERN, "", true, false):
			markers += 1
			if not node is Marker3D:
				wrong_type.append("%s/%s" % [preset.scene.resource_path, node.name])
		room.free()
	_check("в сценах комнат есть маркеры находок (%d)" % markers, markers > 0, "")
	_check("и все они Marker3D — иначе расстановка их не увидит", wrong_type.is_empty(), ", ".join(wrong_type))


# --- 3. Мир -----------------------------------------------------------------------


func _finds() -> Array[E_EssenceFind]:
	var result: Array[E_EssenceFind] = []
	for node in get_tree().root.find_children("*", "E_EssenceFind", true, false):
		if not node.is_queued_for_deletion():
			result.append(node as E_EssenceFind)
	return result


func _signature(finds: Array[E_EssenceFind]) -> Array[String]:
	var lines: Array[String] = []
	for find in finds:
		lines.append("%s:%d:%s" % [find.claim_key, find.amount, find.source])
	lines.sort()
	return lines


func _of_source(source: StringName) -> Array[E_EssenceFind]:
	return _finds().filter(func(f: E_EssenceFind): return f.source == source)


func _reload_layer() -> void:
	# Глубина слоя берётся ДО сноса: despawn() сбрасывает её, и current_depth после
	# него — «ничего не загружено».
	var depth := RunManager.current_depth
	RunManager.layer.despawn()
	# Старый слой освобождается в конце кадра, а новый встаёт в те же клетки.
	await get_tree().process_frame
	RunManager.layer.spawn(depth)
	await get_tree().process_frame


func _check_world() -> void:
	var config := GameConfig.config
	config.essence_find_chance = 1.0
	config.essence_cache_chance = 1.0
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh
	SkillManager.save = SkillManager._fresh_save()
	ArchitectManager.save = ArchitectManager._fresh_save()

	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	_check_placement(plan)

	var before := _signature(_finds())
	await _reload_layer()
	_check("повторный спавн слоя кладёт те же находки в те же места с теми же суммами",
		before == _signature(_finds()) and not before.is_empty(), "было %d, стало %d" % [before.size(), _finds().size()])

	await _check_claim(before)
	await _check_skill()
	await _check_architect()

	config.essence_find_chance = 0.0
	config.essence_cache_chance = 0.0
	await _reload_layer()
	_check("шансы 0 — на слое нет ни одной находки", _finds().is_empty(), "находок %d" % _finds().size())

	RunManager._end_run()


## Тайники — только в тупиках и во всех, находки — ровно на маркерах комнат
## (шансы выставлены в 1: проверяется место, а не бросок).
func _check_placement(plan: RS_LayerPlan) -> void:
	var caches := _of_source(RS_RunStats.ESSENCE_CACHE)
	var stray: Array[String] = []
	var cells := {}
	for cache in caches:
		var cell := plan.embedding.cell_at((cache as Node as Node3D).global_position)
		cells[cell] = true
		if not plan.dead_ends.has(cell) \
				or cache.claim_key != LayerFinds.cache_key(plan.node_by_cell.get(cell, &""), cell):
			stray.append(str(cell))
	_check("тайники стоят только в тупиках", stray.is_empty() and not caches.is_empty(), ", ".join(stray.slice(0, 4)))
	_check("при шансе 1 тайник в каждом тупике слоя",
		cells.size() == plan.dead_ends.size() and caches.size() == plan.dead_ends.size(),
		"тупиков %d, тайников %d" % [plan.dead_ends.size(), caches.size()])

	var markers := 0
	var misplaced: Array[String] = []
	for spawned: LayerStreamer.SpawnedRoom in RunManager.layer.rooms.values():
		var room := spawned.entity
		for marker in room.find_children(LayerFinds.SPOT_PATTERN, "Marker3D", true, false):
			markers += 1
			var find := room.get_node_or_null("EssenceFind_%s" % marker.name) as Node3D
			if find == null or find.global_position.distance_to((marker as Node3D).global_position) > 0.01:
				misplaced.append("%s/%s" % [spawned.node_id, marker.name])
	_check("находка стоит ровно на каждом маркере комнат слоя (%d)" % markers,
		markers > 0 and misplaced.is_empty() and _of_source(RS_RunStats.ESSENCE_PICKUP).size() == markers,
		", ".join(misplaced.slice(0, 4)))


func _points() -> int:
	return ArchitectManager.save.skill_points


func _check_claim(before: Array[String]) -> void:
	var stats := RunStats.current
	var base := GameConfig.config.essence_gain_base
	_check("без навыка душа берёт базовую долю номинала",
		is_equal_approx(LayerFinds.gain(), base), "доля %f, база %f" % [LayerFinds.gain(), base])

	var find := _of_source(RS_RunStats.ESSENCE_PICKUP)[0]
	var key := find.claim_key
	var amount := find.amount
	var expected := roundi(amount * base)
	var points := _points()
	find.interact()
	_check("взятие находки начисляет номинал × доля душе Архитектора: %d из %d" % [expected, amount],
		_points() - points == expected, "начислено %d" % (_points() - points))
	_check("и записывает её в разбивку под источником «находка», не «тайник» и не «Архитектор»",
		is_equal_approx(stats.value(RS_RunStats.ESSENCE_PICKUP), expected)
			and is_equal_approx(stats.value(RS_RunStats.ESSENCE), expected)
			and stats.value(RS_RunStats.ESSENCE_CACHE) == 0.0 and stats.value(RS_RunStats.ESSENCE_ARCHITECT) == 0.0,
		str(stats.counters))
	_check("отметка лежит в сейве забега", WorldSave.is_node_reward_claimed(key), str(WorldSave.save.rewarded_node_ids))
	var message := E_Player.find().get_component(C_ScreenMessage) as C_ScreenMessage
	_check("игрок видит, сколько получил", message != null and message.text.contains(str(expected)),
		message.text if message else "сообщения нет")

	await get_tree().process_frame
	_check("взятая находка исчезла из мира", not is_instance_valid(find), "")

	# Вторая сущность с тем же ключом — как после загрузки сейва, пока слой ещё не
	# пересобран: награды быть не должно.
	var twin := LayerFinds._make(key, RS_RunStats.ESSENCE_PICKUP, amount)
	twin.interact()
	twin.free()
	_check("повторное взятие той же находки ничего не даёт", _points() - points == expected,
		"начислено %d" % (_points() - points))

	await _reload_layer()
	var after := _signature(_finds())
	var left := before.filter(func(line: String): return not line.begins_with(str(key) + ":"))
	_check("взятая находка не появляется при повторном спавне слоя, остальные на месте",
		after == left and after.size() == before.size() - 1, "было %d, стало %d" % [before.size(), after.size()])


func _check_skill() -> void:
	var def := SkillManager.SKILL_TREE.get_definition(SKILL_ID)
	var base := GameConfig.config.essence_gain_base
	SkillManager.save.ranks[SKILL_ID] = def.max_rank
	SkillManager.reapply_all()
	var gain := LayerFinds.gain()
	_check("навык доезжает до души: доля выросла с %.2f до %.2f" % [base, gain], gain > base, "")

	var cache := _of_source(RS_RunStats.ESSENCE_CACHE)[0]
	var expected := roundi(cache.amount * gain)
	var stats := RunStats.current
	var points := _points()
	var cache_before := stats.value(RS_RunStats.ESSENCE_CACHE)
	cache.interact()
	_check("тайник платит номинал × доля с навыком: %d из %d" % [expected, cache.amount],
		_points() - points == expected, "начислено %d" % (_points() - points))
	_check("и пишется под источником «тайник»",
		is_equal_approx(stats.value(RS_RunStats.ESSENCE_CACHE) - cache_before, expected), str(stats.counters))
	await get_tree().process_frame

	SkillManager.save.ranks.erase(SKILL_ID)
	SkillManager.reapply_all()
	_check("без навыка доля возвращается к базе", is_equal_approx(LayerFinds.gain(), base), "")


## Касание Архитектора навык не множит: гарантированная доля остаётся гарантией
## (решение в карточке «Источники эссенции»).
func _check_architect() -> void:
	var def := SkillManager.SKILL_TREE.get_definition(SKILL_ID)
	SkillManager.save.ranks[SKILL_ID] = def.max_rank
	SkillManager.reapply_all()
	var reward := GameConfig.config.architect_essence_reward
	var points := _points()
	A_ArchitectEncounter.new().execute(null)
	UIManager.close_all()
	_check("касание Архитектора даёт награду без множителя навыка",
		_points() - points == reward, "начислено %d, награда %d" % [_points() - points, reward])
	SkillManager.save.ranks.erase(SKILL_ID)
	SkillManager.reapply_all()


func _restore() -> void:
	var config := GameConfig.config
	config.essence_find_chance = _find_chance
	config.essence_cache_chance = _cache_chance
	WorldSave.save = _world_save
	SkillManager.save = _skill_save
	ArchitectManager.save = _architect_save
	for entry in [
		[WorldSave.SAVE_PATH, _world_bytes],
		[SkillManager._save_path, _skills_bytes],
		[ArchitectManager._save_path, _architect_bytes],
	]:
		var path: String = entry[0]
		var bytes: PackedByteArray = entry[1]
		if bytes.is_empty():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_buffer(bytes)
			file.close()
	_check("сейвы разработчика возвращены на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _world_bytes
			and FileAccess.get_file_as_bytes(SkillManager._save_path) == _skills_bytes
			and FileAccess.get_file_as_bytes(ArchitectManager._save_path) == _architect_bytes, "")
