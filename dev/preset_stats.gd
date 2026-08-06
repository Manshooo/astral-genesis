## res://dev/preset_stats.gd
## Диагностика подбора пресетов: почему одни комнаты не появляются в генерации.
## Запуск: godot --headless --script res://dev/preset_stats.gd
## Гоняет генератор по N сидам и считает, какой пресет сколько раз выбран,
## плюс распределение степеней узлов и теги exit-узлов. Дополняет gen_verifier
## (тот проверяет достижимость/двери, этот — статистику выбора пресетов).
extends SceneTree

const SEEDS := 30


func _init() -> void:
	var library: RS_RoomPresetLibrary = load("res://data/room_preset_library.tres")

	print("=== validate() ===")
	for problem in library.validate():
		print("  ! ", problem)

	var scene_hits := {}   # room_scene_path -> count
	var degree_hist := {}  # degree -> count
	var exit_tag_hist := {}
	var exit_degree_hist := {}
	var total_nodes := 0

	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, library)
		for node in graph.nodes.values():
			total_nodes += 1
			var path: String = node.room_scene_path
			scene_hits[path] = scene_hits.get(path, 0) + 1
			var deg: int = node.connections.size()
			degree_hist[deg] = degree_hist.get(deg, 0) + 1
			if node.tags.has(&"level_exit"):
				var key := str(node.tags)
				exit_tag_hist[key] = exit_tag_hist.get(key, 0) + 1
				exit_degree_hist[deg] = exit_degree_hist.get(deg, 0) + 1

	print("\n=== выбранные сцены (%d сидов, %d узлов) ===" % [SEEDS, total_nodes])
	var paths := scene_hits.keys()
	paths.sort()
	for p in paths:
		print("  %5d  %s" % [scene_hits[p], p])

	print("\n=== распределение степеней узлов (число рёбер) ===")
	var degrees := degree_hist.keys()
	degrees.sort()
	for d in degrees:
		print("  degree=%d : %d" % [d, degree_hist[d]])

	print("\n=== узлы с тегом level_exit: наборы тегов ===")
	for k in exit_tag_hist:
		print("  %5d  %s" % [exit_tag_hist[k], k])

	print("\n=== узлы level_exit: степени ===")
	var ed := exit_degree_hist.keys()
	ed.sort()
	for d in ed:
		print("  degree=%d : %d" % [d, exit_degree_hist[d]])

	quit()
