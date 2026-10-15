extends "res://dev/check_harness.gd"
## Проверка эвакуационных табличек (ExitSign): текст зависит от слоя и от того,
## куда ведёт портал, а номер слоя спавн проставляет по УЗЛУ комнаты — в настоящем
## забеге, на каждом слое.
##
## Главное, что здесь можно сломать молча: номер, взятый из RunManager.
## current_depth, на спавне нового слоя указывает на старый (стример ставит свою
## глубину в самом конце), и табличка врала бы ровно на переходе между слоями.
## Поэтому номера сверяются в живом спавне, а не только на сцене знака.
##
## Запускать: godot --headless dev/exit_sign_check.tscn

const SIGN_SCENE := "res://src/levels/props/exit_sign.tscn"
const RUN_SEED := 424242

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save

	_check_text()
	await _check_spawn()

	RunManager.current_graph = null
	WorldSave.save = _save_object
	_restore_save()
	_finish()


func _new_sign() -> ExitSign:
	return (load(SIGN_SCENE) as PackedScene).instantiate() as ExitSign


func _check_text() -> void:
	var surface := ExitSign.surface_depth()
	_check("поверхность — самый верхний слой", surface == 0, str(surface))

	# Номер приходит до входа в дерево — так его ставит спавн.
	var route := _new_sign()
	ExitSign.stamp_depth(route, 3)
	add_child(route)
	_check("на стене: маршрут к выходу наверх",
		route.exit_line() == tr("EXIT_SIGN_ROUTE") % surface, route.exit_line())
	_check("на стене: номер слоя", route.layer_line() == tr("EXIT_SIGN_LAYER") % 3, route.layer_line())
	route.layer_depth = 4
	_check("номер обновляется и после входа в дерево", route.layer_line() == tr("EXIT_SIGN_LAYER") % 4, route.layer_line())

	var top := _new_sign()
	ExitSign.stamp_depth(top, surface)
	add_child(top)
	_check("на самой поверхности стрелка наверх не пишется",
		top.exit_line() == tr("EXIT_SIGN_DOOR"), top.exit_line())

	var up := _new_sign()
	up.billboard = true
	ExitSign.stamp_depth(up, 3)
	ExitSign.stamp_destination(up, 2)
	add_child(up)
	_check("портал вверх: маршрут и слой назначения",
		up.exit_line() != "" and up.layer_line() == tr("EXIT_SIGN_PORTAL_UP") % 2, up.layer_line())

	var down := _new_sign()
	down.billboard = true
	ExitSign.stamp_depth(down, 3)
	ExitSign.stamp_destination(down, 4)
	add_child(down)
	_check("портал вниз: слой назначения, а «выход наверх» не пишется",
		down.exit_line() == "" and down.layer_line() == tr("EXIT_SIGN_PORTAL_DOWN") % 4,
		"%s | %s" % [down.exit_line(), down.layer_line()])

	var between := _new_sign()
	ExitSign.stamp_depth(between, 3)
	ExitSign.stamp_destination(between, 3)
	add_child(between)
	_check("портал между этажами слоя: просто номер слоя",
		between.layer_line() == tr("EXIT_SIGN_LAYER") % 3, between.layer_line())

	var door := _new_sign()
	door.kind = ExitSign.Kind.DOOR
	ExitSign.stamp_depth(door, 0)
	add_child(door)
	_check("над дверью наружу — одно слово «ВЫХОД»",
		door.exit_line() == tr("EXIT_SIGN_DOOR") and door.layer_line() == "", "%s | %s" % [door.exit_line(), door.layer_line()])

	var bare := _new_sign()
	add_child(bare)
	_check("без номера от спавна строка слоя не врёт «L?»", bare.layer_line() == "", bare.layer_line())

	for node in [route, top, up, down, between, door, bare]:
		(node as Node).queue_free()


func _check_spawn() -> void:
	var world := _new_world()
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var graph := RunManager.current_graph
	var signs_seen := 0
	var portal_signs := 0
	var wrong := PackedStringArray()
	var wrong_portal := PackedStringArray()
	for depth: int in RS_LevelGraph.DEPTHS:
		var entry: RS_LevelNode = null
		for node_data in graph.get_nodes_by_depth(depth):
			if node_data.role == RS_LevelNode.Role.ROOM:
				entry = node_data
				break
		if entry == null:
			continue
		RunManager.travel_to(entry.id)
		await get_tree().process_frame
		await get_tree().process_frame
		if RunManager.current_depth != depth:
			wrong.append("L%d: слой не загрузился" % depth)
			continue

		for node in world.find_children("*", "ExitSign", true, false):
			var board := node as ExitSign
			if not board.is_inside_tree():
				continue
			signs_seen += 1
			if board.layer_depth != depth:
				wrong.append("L%d: знак %s показывает L%d" % [depth, board.get_path(), board.layer_depth])

		for spawned: LayerStreamer.SpawnedRoom in RunManager.layer.rooms.values():
			for portal in spawned.portals:
				var link := portal.get_component(C_DoorPortal) as C_DoorPortal
				if link == null or link.target_node_id == &"":
					continue
				var target := graph.get_node_data(link.target_node_id)
				for node in portal.find_children("*", "ExitSign", true, false):
					portal_signs += 1
					if (node as ExitSign).destination_depth != target.depth:
						wrong_portal.append("%s: L%d вместо L%d" % [portal.name, (node as ExitSign).destination_depth, target.depth])

	_check("на каждом слое номер на табличках — слой их комнаты", wrong.is_empty(), "; ".join(wrong))
	_check("в забеге есть таблички (лестницы, выход)", signs_seen > 0, "знаков: %d" % signs_seen)
	_check("у порталов табличка знает слой назначения", wrong_portal.is_empty(), "; ".join(wrong_portal))
	_check("в забеге есть таблички у порталов", portal_signs > 0, "знаков у порталов: %d" % portal_signs)


func _restore_save() -> void:
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	WorldSave.has_save_file = _had_save
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")
