extends "res://dev/check_harness.gd"
## Свет по слоям (RS_DepthLighting, data/depth_lighting.tres): чем глубже, тем
## темнее — фоновый свет, лампы, туман и доля погасших ламп коридора.
##
## Ломается это тихо со всех сторон: лампа, не услышавшая сигнал слоя, светит
## авторской энергией; погасшая лампа, которую стример не нашёл в тайле, просто
## горит; окружение в режиме фонового света, отличном от «цвета», принимает цвет
## и энергию и ничего с ними не делает. Поэтому слои грузятся настоящим
## RunManager, а лампы и тайлы считаются в дереве, а не по данным.
##
## Запускать: godot --headless dev/depth_lighting_check.tscn

const RUN_SEED := 424242
const WORLD_SCENE := "res://src/world/world.tscn"

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _base_config: RS_WorldGenConfig


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save
	_base_config = GameConfig.config.world_gen

	_check_data()
	_check_world_scene()

	_new_world()
	GameConfig.config.world_gen = _base_config.duplicate() as RS_WorldGenConfig
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	var authored := Environment.new()
	authored.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	authored.ambient_light_color = Color(0.9, 0.1, 0.1)
	authored.ambient_light_energy = 0.5
	authored.fog_light_color = Color(0.3, 0.3, 0.3)
	var with_depth := _environment(authored, true)
	var without_depth := _environment(authored, false)

	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame

	var surface: int = RS_LevelGraph.DEPTHS.min()
	var deepest: int = RS_LevelGraph.DEPTHS.max()
	var top := await _load_layer(surface)
	var top_ambient := with_depth.environment.ambient_light_energy
	var top_fog := with_depth.environment.fog_light_color.get_luminance()
	var bottom := await _load_layer(deepest)
	var bottom_ambient := with_depth.environment.ambient_light_energy
	var bottom_fog := with_depth.environment.fog_light_color.get_luminance()
	var bottom_again := await _load_layer(deepest)

	_check_lamps(top, bottom, bottom_again, surface, deepest)
	_check_fixtures(top, bottom)
	await _check_sdfgi_restart(surface)
	_check("окружение мира на дне темнее, чем у поверхности: фоновый свет и туман",
		bottom_ambient < top_ambient and bottom_fog <= top_fog,
		"фон %.3f → %.3f, туман %.3f → %.3f" % [top_ambient, bottom_ambient, top_fog, bottom_fog])
	_check("окружение без флага свет слоя не слушает",
		without_depth.environment.ambient_light_color == authored.ambient_light_color
			and is_equal_approx(without_depth.environment.ambient_light_energy, authored.ambient_light_energy),
		"%s × %.3f" % [without_depth.environment.ambient_light_color,
			without_depth.environment.ambient_light_energy])

	RunManager._end_run()
	_check("снятый слой возвращает окружению авторский свет",
		with_depth.environment.ambient_light_color == authored.ambient_light_color
			and is_equal_approx(with_depth.environment.ambient_light_energy, authored.ambient_light_energy)
			and with_depth.environment.fog_light_color == authored.fog_light_color,
		"%s × %.3f" % [with_depth.environment.ambient_light_color, with_depth.environment.ambient_light_energy])
	_check("общий ресурс окружения не задет",
		is_equal_approx(authored.ambient_light_energy, 0.5), "%.3f" % authored.ambient_light_energy)

	with_depth.queue_free()
	without_depth.queue_free()
	_restore()
	_finish()


# ---------------------------------------------------------------------------


## Данные — направление, а не числа: числа подбирают на глаз, а «глубже не
## светлее» — требование.
func _check_data() -> void:
	var lighting := load(RS_DepthLighting.PATH) as RS_DepthLighting
	_check("свет по слоям лежит в data/ и загружается", lighting != null, RS_DepthLighting.PATH)
	if lighting == null:
		return
	var deepest: int = RS_LevelGraph.DEPTHS.max()
	_check("у каждого слоя генератора свой свет",
		lighting.layers.size() == deepest + 1, "%d слоёв света на %d слоёв" % [lighting.layers.size(), deepest + 1])
	_check("глубже последнего слоя — свет последнего",
		lighting.for_depth(deepest + 3) == lighting.layers.back(), "")

	var problems: Array[String] = []
	for depth in range(1, lighting.layers.size()):
		var upper := lighting.layers[depth - 1]
		var lower := lighting.layers[depth]
		if lower.ambient_energy > upper.ambient_energy:
			problems.append("фоновый свет %d ярче %d" % [depth, depth - 1])
		if lower.lamp_energy_scale > upper.lamp_energy_scale:
			problems.append("лампы %d ярче %d" % [depth, depth - 1])
		if lower.dead_lamp_chance < upper.dead_lamp_chance:
			problems.append("погасших на %d меньше, чем на %d" % [depth, depth - 1])
		if lower.fog_color.get_luminance() > upper.fog_color.get_luminance():
			problems.append("туман %d светлее %d" % [depth, depth - 1])
	_check("глубже — не светлее: фон, лампы и туман не ярче, погасших не меньше",
		problems.is_empty(), ", ".join(problems))
	_check("у поверхности погасших ламп нет", is_zero_approx(lighting.layers[0].dead_lamp_chance),
		"%.2f" % lighting.layers[0].dead_lamp_chance)


## Окружение мира слушает свет слоя и держит фоновый свет «цветом» — в другом
## режиме цвет и энергия, которые ставит слой, ничего не значат.
func _check_world_scene() -> void:
	var state := (load(WORLD_SCENE) as PackedScene).get_state()
	var flagged := false
	var source := -1
	for i in state.get_node_count():
		if state.get_node_type(i) != &"WorldEnvironment":
			continue
		for p in state.get_node_property_count(i):
			match state.get_node_property_name(i, p):
				&"apply_depth_lighting":
					flagged = state.get_node_property_value(i, p)
				&"environment":
					source = (state.get_node_property_value(i, p) as Environment).ambient_light_source
	_check("окружение мира слушает свет слоя", flagged, "")
	_check("фоновый свет окружения мира — «цвет»", source == Environment.AMBIENT_SOURCE_COLOR,
		"режим %d" % source)


## SDFGI строит поле расстояний один раз, а слои раскладываются от одной клетки:
## без перезапуска отражённый свет нового слоя считался бы по стенам прошлого.
## Перезапуск — выключение на кадр и возврат по настройке.
func _check_sdfgi_restart(depth: int) -> void:
	var before := SettingsManager.settings
	var ultra := before.copy()
	ultra.screen_effects = &"ultra"
	SettingsManager.settings = ultra
	var authored := Environment.new()
	authored.sdfgi_enabled = true
	var node := _environment(authored, false)
	var was_on := node.environment.sdfgi_enabled
	RunManager._despawn_layer()
	RunManager._spawn_layer(depth)
	var off_after_swap := not node.environment.sdfgi_enabled
	await get_tree().process_frame
	await get_tree().process_frame
	_check("смена слоя перезапускает SDFGI: выключен на кадр, затем снова включён",
		was_on and off_after_swap and node.environment.sdfgi_enabled,
		"до %s, после смены %s, через кадр %s" % [was_on, not off_after_swap, node.environment.sdfgi_enabled])
	SettingsManager.settings = before
	node.queue_free()


func _environment(authored: Environment, depth_lighting: bool) -> WorldEnvironment:
	var node := WorldEnvironment.new()
	node.environment = authored
	node.set_script(LevelEnvironment)
	node.set(&"apply_depth_lighting", depth_lighting)
	add_child(node)
	return node


## Грузит слой тем же путём, что портал: снять прежний, заспавнить новый — сигнал
## слоя шлёт RunManager. Возвращает тайлы коридоров: позиция → энергии его ламп
## и его плафоны (светится ли, сила свечения, дотянулся ли тросик до потолка).
## Тросик меряется лучом в физкадре — отсюда ожидание.
func _load_layer(depth: int) -> Dictionary:
	RunManager._despawn_layer()
	RunManager._spawn_layer(depth)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tiles := {}
	for branch: Array in RunManager.layer.corridor_tiles.values():
		for tile: Node3D in branch:
			var energies: Array[float] = []
			var fixtures: Array[Dictionary] = []
			for node in tile.find_children("*", "", true, false):
				if node is LevelLight:
					energies.append((node as Light3D).light_energy)
				elif node is LampFixture:
					var panel := (node as Node).get_node("Panel") as MeshInstance3D
					var material := panel.material_override as StandardMaterial3D
					fixtures.append({
						lit = material != null and material.emission_enabled,
						emission = material.emission_energy_multiplier if material else 0.0,
						cable = ((node as Node).get_node("Cable") as Node3D).visible,
					})
			tiles[tile.global_position.snapped(Vector3.ONE * 0.1)] = {energies = energies, fixtures = fixtures}
	return tiles


func _check_lamps(top: Dictionary, bottom: Dictionary, bottom_again: Dictionary, surface: int, deepest: int) -> void:
	_check("на обоих слоях есть тайлы коридора", not top.is_empty() and not bottom.is_empty(),
		"%d и %d" % [top.size(), bottom.size()])
	if top.is_empty() or bottom.is_empty():
		return
	var top_dark := _dark(top)
	var bottom_dark := _dark(bottom)
	var chance := RS_DepthLighting.layer(deepest).dead_lamp_chance
	var share := float(bottom_dark.size()) / bottom.size()
	_check("у поверхности все лампы коридора горят", top_dark.is_empty(), "погасло %d" % top_dark.size())
	# Допуск — с запасом на разброс броска по сотне-другой тайлов.
	_check("на дне погасла доля ламп около заданной",
		absf(share - chance) < 0.12 and not bottom_dark.is_empty(),
		"погасло %d из %d (%.2f при заданной %.2f)" % [bottom_dark.size(), bottom.size(), share, chance])
	var dark_again := _dark(bottom_again)
	dark_again.sort()
	bottom_dark.sort()
	_check("тот же мир гасит те же лампы", dark_again == bottom_dark,
		"%d против %d" % [dark_again.size(), bottom_dark.size()])

	var top_mean := _mean_energy(top)
	var bottom_mean := _mean_energy(bottom)
	var expected := RS_DepthLighting.layer(deepest).lamp_energy_scale / RS_DepthLighting.layer(surface).lamp_energy_scale
	_check("лампы на дне тусклее во столько, во сколько велит слой",
		bottom_mean < top_mean and absf(bottom_mean / top_mean - expected) < 0.01,
		"%.3f → %.3f, отношение %.3f при заданном %.3f" % [top_mean, bottom_mean, bottom_mean / top_mean, expected])


## Плафон — на каждом тайле ровно один и остаётся у погасшей лампы тёмным:
## мёртвый светильник, а не дыра в потолке. Светится он силой своей лампы —
## на дне тусклее, — и тросик дотягивается до потолка коридора.
func _check_fixtures(top: Dictionary, bottom: Dictionary) -> void:
	var problems: Array[String] = []
	var no_cable := 0
	for tiles: Dictionary in [top, bottom]:
		for key: Vector3 in tiles:
			var tile: Dictionary = tiles[key]
			var fixtures: Array = tile.fixtures
			if fixtures.size() != 1:
				problems.append("%s: плафонов %d" % [key, fixtures.size()])
				continue
			var has_lamp := not (tile.energies as Array).is_empty()
			if fixtures[0].lit != has_lamp:
				problems.append("%s: лампа %s, плафон %s" % [key,
					"горит" if has_lamp else "погасла", "светится" if fixtures[0].lit else "тёмный"])
			if not fixtures[0].cable:
				no_cable += 1
	_check("на каждом тайле один плафон, светится ровно у горящей лампы",
		problems.is_empty(), ", ".join(problems.slice(0, 5)))
	_check("тросик плафона нашёл потолок коридора", no_cable == 0, "без потолка %d" % no_cable)
	_check("плафоны на дне светятся тусклее, чем у поверхности",
		_mean_emission(bottom) < _mean_emission(top),
		"%.3f → %.3f" % [_mean_emission(top), _mean_emission(bottom)])


func _dark(tiles: Dictionary) -> Array:
	return tiles.keys().filter(func(key: Vector3) -> bool: return (tiles[key].energies as Array).is_empty())


func _mean_energy(tiles: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for tile: Dictionary in tiles.values():
		for energy: float in tile.energies:
			total += energy
			count += 1
	return total / count if count > 0 else 0.0


func _mean_emission(tiles: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for tile: Dictionary in tiles.values():
		for fixture: Dictionary in tile.fixtures:
			if fixture.lit:
				total += fixture.emission
				count += 1
	return total / count if count > 0 else 0.0


func _restore() -> void:
	GameConfig.config.world_gen = _base_config
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
