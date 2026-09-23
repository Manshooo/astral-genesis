extends Node
## Проверка задела под Архитектора (карточка «Артефакт «Архитектор»»): второе
## дерево прокачки на общей машинерии, эссенция за встречу, комната Архитектора
## как уникальная комната генератора.
##
## Всё здесь ломается тихо. Улучшение, крутящее стат души, а не мира, ничего не
## меняет — ArchitectManager его никуда не применяет. Награда без отметки в сейве
## забега выдаётся заново после каждой загрузки. Ключ перевода с опечаткой
## показывает игроку «ARCHITECT_MAP» вместо названия. Комната, выпавшая на слой
## хаба или не выпавшая вовсе, выглядит просто неудачным сидом.
##
## Сейвы подменяются на время прогона и возвращаются: встреча пишет и в сейв
## забега, и в сейв Архитектора, а проверка не должна оставлять следов.
##
## Запускать: godot --headless dev/architect_check.tscn

const SEEDS := 30
const CONFIG_PATH := "res://data/world_gen_config.tres"
const ROOM_SCENE := "res://src/levels/procedural/rooms/architect/architect_room.tscn"
## Глубины, на которых Архитектор обязан встречаться: все, кроме хаба и поверхности.
const EXPECTED_DEPTHS: Array[int] = [1, 2, 4]
const NODE_ID := &"L2_F0_room_3"
## Лучи по полу — только статика, как у игрока под ногами.
const GEOMETRY_MASK := 1
## Сколько ассертов обязано отработать до сторожевого (см. _ready).
const EXPECTED_ASSERTS := 27

var _ok := 0
var _fail := 0

var _world_bytes := PackedByteArray()
var _world_save: RS_WorldSave
var _architect_save: PlayerSkillSave
var _skill_save: PlayerSkillSave
var _node_id: StringName
var _locale: String


func _ready() -> void:
	# Встреча открывает экран в корень дерева, а корень занят, пока идёт _ready
	# сцены. В игре так не бывает: касание приходит отложенно из S_InteractInput.
	await get_tree().process_frame
	_world_bytes = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_world_save = WorldSave.save
	_architect_save = ArchitectManager.save
	_skill_save = SkillManager.save
	_node_id = RunManager.current_node_id
	_locale = TranslationServer.get_locale()

	_check_progression()
	_check_texts()
	_check_encounter()
	_check_generation()
	await _check_scene()

	_restore()

	# SCRIPT ERROR внутри блока обрывает только этот блок, а не прогон: итог
	# печатается, провалов ноль — и сломанное выглядит зелёным (так однажды прошёл
	# первый прогон corridor_graph_check). Поэтому число ассертов сверяется.
	var ran := _ok + _fail
	_check("все блоки дошли до конца", ran == EXPECTED_ASSERTS,
		"ассертов %d из %d — какой-то блок упал на ошибке скрипта" % [ran, EXPECTED_ASSERTS])

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# --- 1. Прокачка ------------------------------------------------------------


func _check_progression() -> void:
	var tree := ArchitectManager.SKILL_TREE
	_check(
		"у Архитектора своё дерево и свой файл сейва",
		tree != null and tree != SkillManager.SKILL_TREE
			and ArchitectManager._save_path != SkillManager._save_path,
		"дерево или сейв общие с навыками",
	)

	# Модификатор, нацеленный на стат души, у Архитектора — мёртвая строка:
	# ArchitectManager ничего не кладёт в C_StatModifiers.
	var foreign: Array[String] = []
	var covered := {}
	for def in tree.skills:
		for mod in def.modifiers:
			if not ArchitectStats.ALL.has(mod.stat):
				foreign.append("%s → %s" % [def.id, mod.stat])
			covered[mod.stat] = true
	_check("улучшения Архитектора крутят только статы мира", foreign.is_empty(), ", ".join(foreign))
	var idle: Array[String] = []
	for stat in ArchitectStats.ALL:
		if not covered.has(stat):
			idle.append(String(stat))
	_check("каждый стат мира занят улучшением", idle.is_empty(), ", ".join(idle))

	ArchitectManager.save = ArchitectManager._fresh_save()
	SkillManager.save = SkillManager._fresh_save()
	SkillManager.save.skill_points = 3
	_check("без улучшений экрана карты нет", ArchitectManager.map_level() == 0,
		"уровень %d" % ArchitectManager.map_level())

	ArchitectManager.save.skill_points = 100
	var levels: Array[int] = []
	for i in ArchitectStats.MAP_LEVEL_MAX:
		ArchitectManager.unlock(ArchitectStats.MAP_LEVEL)
		levels.append(ArchitectManager.map_level())
	_check("каждый ранг открывает следующий уровень карты", levels == [1, 2, 3, 4], str(levels))
	_check(
		"покупка у Архитектора не трогает навыки",
		SkillManager.save.skill_points == 3 and SkillManager.save.ranks.is_empty(),
		"очки %d, ранги %s" % [SkillManager.save.skill_points, SkillManager.save.ranks],
	)

	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = 7
	_check("лишний ранг в данных не открывает несуществующий уровень",
		ArchitectManager.map_level() == ArchitectStats.MAP_LEVEL_MAX,
		"уровень %d" % ArchitectManager.map_level())


# --- 2. Тексты ----------------------------------------------------------------


func _check_texts() -> void:
	TranslationServer.set_locale("ru")
	var tree := ArchitectManager.SKILL_TREE
	var keys: Array[String] = [tree.points_format, "ARCHITECT_PROMPT"]
	keys.append_array(tree.currency_forms)
	for def in tree.skills:
		keys.append(def.display_name)
		keys.append(def.description)
	for branch in tree.branches:
		keys.append(branch.display_name)
	var missing: Array[String] = []
	for key in keys:
		if String(TranslationServer.translate(key)) == key:
			missing.append(key)
	_check("ключи Архитектора есть в переводе", missing.is_empty(), ", ".join(missing))

	_check("счётчик называет эссенцию", tree.points_text(3) == "Эссенция: 3", tree.points_text(3))
	var costs: Array[String] = []
	for amount in [1, 2, 5, 11, 21, 22]:
		costs.append(tree.cost_text(amount))
	_check(
		"цена склоняется по числу",
		costs == ["1 эссенция", "2 эссенции", "5 эссенций", "11 эссенций", "21 эссенция", "22 эссенции"],
		", ".join(costs),
	)

	var skills := SkillManager.SKILL_TREE
	var skill_texts := [skills.points_text(5), skills.cost_text(1), skills.cost_text(3), skills.cost_text(12)]
	_check(
		"у навыков по-прежнему очки",
		skill_texts == ["Очки: 5", "1 очко", "3 очка", "12 очков"],
		", ".join(skill_texts),
	)


# --- 3. Встреча -----------------------------------------------------------------


func _check_encounter() -> void:
	var reward := GameConfig.config.architect_essence_reward
	_check("встреча вообще что-то даёт", reward > 0, "architect_essence_reward = %d" % reward)

	WorldSave.save = RS_WorldSave.new()
	ArchitectManager.save = ArchitectManager._fresh_save()
	var action := A_ArchitectEncounter.new()

	RunManager.current_node_id = NODE_ID
	action.execute(null)
	_check("первое касание даёт эссенцию", ArchitectManager.save.skill_points == reward,
		"эссенции %d" % ArchitectManager.save.skill_points)
	var screen := _open_tree_screen()
	_check(
		"и открывает улучшения Архитектора, а не навыки",
		screen != null and screen._skill_manager == ArchitectManager
			and screen._tree_data == ArchitectManager.SKILL_TREE,
		"экран %s" % screen,
	)
	UIManager.close_all()

	action.execute(null)
	UIManager.close_all()
	_check("повторное касание в том же забеге не даёт ничего",
		ArchitectManager.save.skill_points == reward,
		"эссенции %d" % ArchitectManager.save.skill_points)
	_check("отметка лежит в сейве забега, а не на сущности",
		WorldSave.save.rewarded_node_ids.has(NODE_ID), str(WorldSave.save.rewarded_node_ids))

	WorldSave.save.clear_run()
	action.execute(null)
	UIManager.close_all()
	_check("новый забег — новая награда", ArchitectManager.save.skill_points == reward * 2,
		"эссенции %d" % ArchitectManager.save.skill_points)

	RunManager.current_node_id = &""
	action.execute(null)
	var outside := _open_tree_screen()
	UIManager.close_all()
	_check("вне забега награды нет, а экран есть",
		ArchitectManager.save.skill_points == reward * 2 and outside != null,
		"эссенции %d, экран %s" % [ArchitectManager.save.skill_points, outside])


func _open_tree_screen() -> SkillTreeUI:
	for child in get_tree().root.get_children():
		if child is SkillTreeUI and not child.is_queued_for_deletion():
			return child
	return null


# --- 4. Генерация -----------------------------------------------------------------


func _check_generation() -> void:
	var library := GameConfig.config.room_preset_library as RS_RoomPresetLibrary
	var config := (load(CONFIG_PATH) as RS_WorldGenConfig).duplicate() as RS_WorldGenConfig
	var architect: RS_UniqueRoom = null
	for unique in config.unique_rooms:
		if unique and unique.preset and unique.preset.scene and unique.preset.scene.resource_path == ROOM_SCENE:
			architect = unique
	_check("Архитектор разыгрывается на всех слоях, кроме хаба и поверхности",
		architect != null and architect.allowed_depths() == EXPECTED_DEPTHS,
		str(architect.allowed_depths()) if architect else "нет записи")
	if architect == null:
		return

	var wrong_count: Array[String] = []
	var wrong_depth: Array[String] = []
	var wrong_wiring: Array[String] = []
	var seen_depths := {}
	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, library, config)
		var found: Array[RS_LevelNode] = []
		for node: RS_LevelNode in graph.nodes.values():
			if node.room_scene_path == ROOM_SCENE:
				found.append(node)
		if found.size() != 1:
			wrong_count.append("сид %d: %d" % [s, found.size()])
		for node in found:
			seen_depths[node.depth] = true
			if not EXPECTED_DEPTHS.has(node.depth):
				wrong_depth.append("сид %d: слой %d" % [s, node.depth])
			var vertical := false
			for conn: RS_LevelConnection in node.connections:
				var target := graph.get_node_data(conn.target_node_id)
				vertical = vertical or target.depth != node.depth or target.floor_index != node.floor_index
			if node.connections.size() != 1 or vertical or node.id == graph.entry_node_id \
					or graph.exit_node_ids.has(node.id):
				wrong_wiring.append("сид %d: %s" % [s, node.id])
	_check("Архитектор в каждом забеге ровно один", wrong_count.is_empty(), ", ".join(wrong_count))
	_check("и никогда на слое хаба или поверхности", wrong_depth.is_empty(), ", ".join(wrong_depth))
	var seen: Array[int] = []
	for depth: int in seen_depths:
		seen.append(depth)
	seen.sort()
	_check("за %d сидов он побывал на каждой допустимой глубине" % SEEDS, seen == EXPECTED_DEPTHS, str(seen))
	_check("одна дверь в коридор, без портала, не вход и не выход", wrong_wiring.is_empty(),
		", ".join(wrong_wiring.slice(0, 4)))

	var broken := architect.duplicate() as RS_UniqueRoom
	broken.excluded_depths = [1, 2, 3, 4]
	config.unique_rooms = config.unique_rooms.duplicate()
	config.unique_rooms.append(broken)
	var problems := config.validate()
	_check("вычеркнуть все глубины — конфиг невалиден", not problems.is_empty(), "validate() молчит")


# --- 5. Сцена -----------------------------------------------------------------


func _check_scene() -> void:
	var sides := RS_RoomLayout.door_directions_of_scene(ROOM_SCENE)
	_check("у комнаты одна дверь, на юг — куда смотрит проём в арте",
		sides.size() == 1 and sides[0] == &"south", str(sides))

	var room := (load(ROOM_SCENE) as PackedScene).instantiate() as Node3D
	add_child(room)
	var wired := false
	for entity in room.find_children("*", "E_InteractableObject", true, false):
		var interactable := _interactable_of(entity)
		var body := entity.get_node_or_null("InteractBody") as CollisionObject3D
		for action in entity.actions:
			if action is A_ArchitectEncounter and interactable != null \
					and interactable.prompt_text == "ARCHITECT_PROMPT" \
					and body != null and body.collision_layer & 8 != 0:
				wired = true
	_check("артефакт — интерактив со встречей, подсказкой и телом на слое interactives", wired, "")

	for i in 3:
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	# Порог двери и пятачок у точки появления: без пола на пороге стык с тайлом
	# коридора — провал под мир (как у B-комнат без коллизии).
	var holes: Array[String] = []
	for z: float in [5.5, 8.6]:
		var from := Vector3(0.0, 1.0, z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 2.0, GEOMETRY_MASK))
		if hit.is_empty():
			holes.append("z=%.1f" % z)
	_check("под порогом и у точки появления пол", holes.is_empty(), ", ".join(holes))

	# Не ассерт: геометрия за гранью клетки у двери (±9 м) сидит в тайле коридора.
	# Правило стыка — подрезать в арте; опустеет — стать ассертом, как в
	# corridor_spawn_check.
	var from := Vector3(0.0, 1.5, RS_LayerPlan.CELL_SIZE)
	var intrusion := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, Vector3(0.0, 1.5, 9.0), GEOMETRY_MASK))
	if not intrusion.is_empty():
		print("  арт  рамка двери выходит за грань клетки: до z=%.2f" % intrusion.position.z)
	room.queue_free()


func _interactable_of(entity: Node) -> C_Interactable:
	for component in entity.component_resources:
		if component is C_Interactable:
			return component
	return null


# ---------------------------------------------------------------------------


func _restore() -> void:
	TranslationServer.set_locale(_locale)
	RunManager.current_node_id = _node_id
	ArchitectManager.save = _architect_save
	ArchitectManager._save()
	SkillManager.save = _skill_save
	WorldSave.save = _world_save
	if _world_bytes.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	else:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(_world_bytes)
		file.close()


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
