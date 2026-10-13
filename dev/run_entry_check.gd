extends "res://dev/check_harness.gd"
## Вход в забег с генерацией в фоне (RunManager.enter_complex_async) и шторка
## загрузки (UI_LoadingScreen).
##
## Ломается это тихо со всех сторон. Фоновый вход, который строит не тот мир,
## что синхронный, не падает — просто сид перестаёт значить комплекс, и сейв
## грузится в чужой. Генерация, ушедшая из потока назад в кадр, выглядит
## рабочей — только фриз возвращается. Сцена комнаты, инстанцированная в
## рабочем потоке (промах прогрева кэшей, RS_RoomLayout.warm_scene_cache),
## headless сходит с рук, а в игре рендер небезопасен. Отменённый вход,
## дописавший старый граф поверх нового, даёт мир не того сида.
##
## Запускать: godot --headless dev/run_entry_check.tscn

const RUN_SEED := 424242
const OTHER_SEED := 777

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _frames := 0


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save

	_new_world()
	get_tree().process_frame.connect(func() -> void: _frames += 1)

	await _check_same_world()
	await _check_layer_in_portions()
	await _check_cancelled_entry()
	await _check_loading_screen()

	RunManager._end_run()
	_restore_save()
	_finish()


# --- 1. Фоновый вход строит тот же мир, что синхронный ---------------------


func _check_same_world() -> void:
	_fresh_save()
	RunManager.enter_complex(RUN_SEED)
	var sync_world := _world_signature()
	await get_tree().process_frame

	_fresh_save()
	# Сброс кэшей: синхронный вход уже наполнил их на главном потоке, и без
	# сброса фону было бы нечего промахнуться — ассерт ниже зеленел бы зря.
	RS_RoomLayout.clear_scene_cache()
	RS_RoomLayout.off_main_thread_instances = 0
	var frames_before := _frames
	var ok: bool = await RunManager.enter_complex_async(RUN_SEED)
	var frames_waited := _frames - frames_before

	_check("фоновый вход завершился", ok, "")
	_check("фоновый вход строит тот же мир и ставит в тот же узел, что синхронный",
		_world_signature() == sync_world, "%s\n— против —\n%s" % [_world_signature().left(300), sync_world.left(300)])
	_check("пока строился граф, кадры шли — генерация не в кадре",
		frames_waited > 0, "кадров за ожидание: %d" % frames_waited)
	_check("в рабочем потоке не инстанцировано ни одной сцены — всё взято из прогрева",
		RS_RoomLayout.off_main_thread_instances == 0,
		"промахов: %d (RS_LevelGraph.scene_paths не знает сцены)" % RS_RoomLayout.off_main_thread_instances)
	_check("душа в мире одна", _player_count() == 1, "душ: %d" % _player_count())


# --- 1б. Слой порциями — тот же слой, но не в одном кадре ------------------


func _check_layer_in_portions() -> void:
	var depth := RunManager.current_depth
	# Эталон — синхронный спавн: слой фонового входа и сам собран порциями.
	RunManager._despawn_layer()
	await get_tree().process_frame
	RunManager._spawn_layer(depth)
	var whole := _layer_signature()

	RunManager._despawn_layer()
	await get_tree().process_frame
	var frames_before := _frames
	var ok: bool = await RunManager.layer.spawn_async(depth, get_tree(), func() -> bool: return true)
	var frames_spent := _frames - frames_before
	_check("слой порциями встаёт тем же, что за один кадр: те же узлы, комнаты на тех же местах, те же тайлы",
		ok and RunManager.current_depth == depth and _layer_signature() == whole,
		"%s\n— против —\n%s" % [_layer_signature().left(300), whole.left(300)])
	_check("слой собирается за несколько кадров, а не в одном",
		frames_spent > 1, "кадров: %d" % frames_spent)

	# Обрыв после первой же порции: слой не должен считаться загруженным.
	RunManager._despawn_layer()
	await get_tree().process_frame
	var stopped: bool = await RunManager.layer.spawn_async(depth, get_tree(), func() -> bool: return false)
	_check("оборванный спавн не объявляет слой загруженным",
		not stopped and RunManager.current_depth == RunManager.NO_DEPTH,
		"вернул %s, глубина %d" % [stopped, RunManager.current_depth])
	RunManager._despawn_layer()


# --- 2. Отменённый вход не дописывает мир ----------------------------------


func _check_cancelled_entry() -> void:
	_fresh_save()
	var result := {}
	var pending := func() -> void: result.ok = await RunManager.enter_complex_async(RUN_SEED)
	pending.call()
	# Пока первый вход ждёт поток, начат второй — на другом сиде.
	RunManager.enter_complex(OTHER_SEED)
	var other_world := _world_signature()
	while not result.has("ok"):
		await get_tree().process_frame

	_check("вход, перебитый новым, сообщает об отмене", result.ok == false, str(result))
	_check("отменённый вход не перезаписал мир нового",
		_world_signature() == other_world and RunManager.current_graph.run_seed == OTHER_SEED,
		"сид графа %d" % RunManager.current_graph.run_seed)
	_check("душа в мире по-прежнему одна", _player_count() == 1, "душ: %d" % _player_count())


# --- 3. Шторка загрузки -------------------------------------------------------


func _check_loading_screen() -> void:
	var hud := (load("res://src/ui/hud/hud.tscn") as PackedScene).instantiate()
	var overlay := (load(load("res://src/world/main.gd").DEBUG_OVERLAY_PATH) as PackedScene).instantiate()
	var hud_top := -INF
	for node in [hud] + hud.find_children("*", "CanvasLayer", true, false):
		if node is CanvasLayer:
			hud_top = maxf(hud_top, (node as CanvasLayer).layer)
	var overlay_layer := (overlay as CanvasLayer).layer
	hud.free()
	overlay.free()
	_check("шторка выше всех слоёв HUD и ниже отладочного оверлея",
		UI_LoadingScreen.LAYER > hud_top and UI_LoadingScreen.LAYER < overlay_layer,
		"шторка %d, HUD до %d, оверлей %d" % [UI_LoadingScreen.LAYER, hud_top, overlay_layer])

	var screen := UI_LoadingScreen.new()
	add_child(screen)
	await screen.dismiss()
	await get_tree().process_frame
	_check("dismiss убирает шторку", not is_instance_valid(screen), "")


# --- Помощники ---------------------------------------------------------------


## Мир так, как его видит игрок: узлы графа с их сценами, поворотами и рёбрами,
## узел, где стоит душа, и что заспавнено на слое. Сортировка по строке: имена
## узлов — StringName, а их sort() сравнивает адреса, не текст.
func _world_signature() -> String:
	var graph := RunManager.current_graph
	var ids: Array = graph.nodes.keys()
	ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	var parts: PackedStringArray = []
	for id in ids:
		var node: RS_LevelNode = graph.nodes[id]
		var links: PackedStringArray = []
		for conn: RS_LevelConnection in node.connections:
			links.append("%s:%d:%s" % [conn.target_node_id, conn.type, conn.locked_by])
		links.sort()
		parts.append("%s|%s|%d|%d|%s" % [id, node.room_scene_path, node.turns, node.socket_doors, ",".join(links)])
	var tiles := 0
	for list: Array in RunManager.layer.corridor_tiles.values():
		tiles += list.size()
	parts.append("узел %s, слой %d, комнат %d, тайлов %d" % [
		RunManager.current_node_id, RunManager.current_depth, RunManager.layer.rooms.size(), tiles])
	return "\n".join(parts)


## Что стоит в дереве слоя: комнаты с их местом и поворотом, тайлы коридоров
## по клеткам. Узлы — по строке (см. _world_signature).
func _layer_signature() -> String:
	var parts: PackedStringArray = []
	var ids: Array = RunManager.layer.rooms.keys()
	ids.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for id in ids:
		var root := RunManager.layer.rooms[id].entity as Node as Node3D
		parts.append("%s %s" % [id, root.global_transform if is_instance_valid(root) else "—"])
	var corridors: Array = RunManager.layer.corridor_tiles.keys()
	corridors.sort_custom(func(a, b) -> bool: return String(a) < String(b))
	for id in corridors:
		var cells: PackedStringArray = []
		for tile in RunManager.layer.corridor_tiles[id]:
			cells.append(str((tile as Node3D).position) if is_instance_valid(tile) else "—")
		cells.sort()
		parts.append("%s: %s" % [id, ", ".join(cells)])
	return "\n".join(parts)


func _player_count() -> int:
	return ECS.world.query.with_all([C_PlayerInput]).execute().size()


## Свежий сейв без начатого забега: иначе вход пошёл бы с узла разработчика.
func _fresh_save() -> void:
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh


## Вход ставит контрольные точки в памяти, а автосохранение — на диск: чужой
## забег прогон ронять не должен.
func _restore_save() -> void:
	WorldSave.save = _save_object
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")
