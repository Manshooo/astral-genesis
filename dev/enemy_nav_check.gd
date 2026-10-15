extends "res://dev/check_harness.gd"
## Проверка навигации и обнаружения врага (S_EnemyAI, LayerNavigation, C_EnemyAI):
## враг замечает игрока только если видит — в конусе, без стены на луче, — помнит,
## где видел его последний раз, и доходит до игрока ПО НАВМЕШУ там, где по прямой
## упрётся в препятствие.
##
## Арена — настоящая коллизия на слое static_colliders (пол и стенки из
## StaticBody3D): навмеш запекается тем же LayerNavigation, что и в игре, из неё же.
## Низкая стенка (1 м) не закрывает обзор (глаза на 1.6 м), но не пускает ногами, —
## это «игрок за углом» с открытой линией видимости: враг его видит и обязан
## обойти. Высокая (3 м) закрывает и то и другое — это «за стеной».
##
## Ломается всё тихо: враг, который «замечает» сквозь стену, и враг, который
## упёрся в угол, выглядят в логе одинаково — просто стоят или идут не туда.
##
## Запускать: godot --headless dev/enemy_nav_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const ENEMY_SCENE := "res://src/entities/enemy/e_enemy.tscn"
const ENEMY_DIR := "res://src/entities/enemy/"

## Биты слоёв физики (project.godot [layer_names]).
const STATIC_LAYER := 1 << 0
const PLAYER_LAYER := 1 << 1

## Высота глаз игрока над полом в арене. У призрака камера стоит в начале узла и
## падение ему не грозит (C_Flight), так что узел просто ставится на эту высоту.
const EYE := 1.6
## Полоса арены под каждый сценарий: враги разных блоков не мешают друг другу.
const OPEN_Z := -20.0
const WALL_Z := 20.0
## Балка в углу арены, вдали от полос сценариев: точка пола под её серединой.
const BEAM_CENTER := Vector3(20.0, 0.0, -27.0)
## Низ балки: выше обычного агента навмеша (2.0), ниже крупного (2.75).
const BEAM_BOTTOM := 2.3

var _world: World
var _player: E_Player
var _player_node: Node3D
var _arena: Node3D
var _nav := LayerNavigation.new()

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _base_config: RS_WorldGenConfig


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save
	_base_config = GameConfig.config.world_gen

	_world = _new_world()
	_add_systems(_world, "physics", [
		S_Gravity.new(), S_EnemyAI.new(), S_Walk.new(), S_Movement.new(),
	])

	await _run()

	_restore()
	_finish()


func _run() -> void:
	_build_arena()
	await _spawn_player()

	await _check_sight_blocked_by_wall()
	await _check_view_cone()
	await _check_ray_rate()
	await _check_memory()
	await _check_path_around_obstacle()
	_check_template_covers_enemies()
	await _check_sizes()
	await _check_real_layer()


# ---------------------------------------------------------------------------
# Арена
# ---------------------------------------------------------------------------


func _build_arena() -> void:
	_arena = Node3D.new()
	_arena.name = "Arena"
	_world.add_child(_arena)
	# Пол 60×60, верх на y=0.
	_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	# Низкая стенка: z от −12 до 4, обход — через z>4.
	_box(Vector3(0.0, 0.5, -4.0), Vector3(0.5, 1.0, 16.0))
	# Высокая стенка в полосе WALL_Z: закрывает и обзор.
	_box(Vector3(0.0, 1.5, WALL_Z), Vector3(0.5, 3.0, 12.0))
	# Балка над полом (низ на BEAM_BOTTOM): обычный враг под ней проходит, крупный — нет.
	_box(BEAM_CENTER + Vector3(0.0, BEAM_BOTTOM + 0.25, 0.0), Vector3(4.0, 0.5, 3.0))


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = STATIC_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_arena.add_child(body)


func _spawn_player() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	_world.add_entity(_player)
	await get_tree().process_frame
	# Цель врага — воплощённый БФЖ: компоненты навешаны в обход захвата, нам нужен
	# только сам факт «есть что терять».
	_player.add_component(C_Embodied.new())
	_player.add_component(C_Health.new(100.0))
	_player_node = _player as Node as Node3D


func _put_player(at: Vector3) -> void:
	_player_node.global_position = Vector3(at.x, EYE, at.z)
	(_player.get_component(C_Velocity) as C_Velocity).velocity = Vector3.ZERO


## Свежий враг на полу в [param at], лицом к [param face_at]. Урон выключен: проверки
## ходьбы не должны зависеть от того, жив ли ещё игрок.
func _spawn_enemy(at: Vector3, face_at: Vector3) -> E_Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as E_Enemy
	(enemy as Node as Node3D).position = Vector3(at.x, 0.05, at.z)
	_world.add_entity(enemy)
	var ai := enemy.get_component(C_EnemyAI) as C_EnemyAI
	ai.aggro_range = 20.0
	ai.attack_damage = 0.0
	var node := enemy as Node as Node3D
	node.look_at(Vector3(face_at.x, node.global_position.y, face_at.z), Vector3.UP)
	return enemy


func _drop(enemy: E_Enemy) -> void:
	_world.remove_entity(enemy)
	if is_instance_valid(enemy):
		(enemy as Node).free()
	await get_tree().process_frame


func _ai(enemy: E_Enemy) -> C_EnemyAI:
	return enemy.get_component(C_EnemyAI) as C_EnemyAI


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ---------------------------------------------------------------------------
# Обнаружение
# ---------------------------------------------------------------------------


## Одна и та же расстановка с высокой стенкой между ними и без неё: без стенки враг
## замечает, со стенкой — нет. Контроль нужен, чтобы «не заметил» значило именно
## «стена закрыла», а не «далеко» или «спиной».
func _check_sight_blocked_by_wall() -> void:
	_put_player(Vector3(6.0, 0.0, OPEN_Z))
	var open_enemy := _spawn_enemy(Vector3(-6.0, 0.0, OPEN_Z), _player_node.global_position)
	await _physics(30)
	_check(
		"без стены враг замечает игрока перед собой на открытом месте",
		_ai(open_enemy).state == C_EnemyAI.State.CHASING,
		"state=%s" % _ai(open_enemy).state
	)
	await _drop(open_enemy)

	_put_player(Vector3(6.0, 0.0, WALL_Z))
	var walled := _spawn_enemy(Vector3(-6.0, 0.0, WALL_Z), _player_node.global_position)
	await _physics(60)
	var ai := _ai(walled)
	_check(
		"игрок за высокой стеной в радиусе и перед глазами — враг его не замечает",
		ai.state == C_EnemyAI.State.IDLE and ai.sight_rays > 0,
		"state=%s лучей=%d" % [ai.state, ai.sight_rays]
	)
	var inp := walled.get_component(C_EnemyInput) as C_EnemyInput
	_check(
		"не заметивший враг стоит, а не идёт на стену по прямой",
		inp.move_direction == Vector3.ZERO,
		"move_direction=%s" % inp.move_direction
	)
	await _drop(walled)


## Конус обзора: за спиной не замечает, лицом — замечает, вплотную — замечает и
## спиной. Луч в обоих случаях чист, так что решает только угол.
func _check_view_cone() -> void:
	_put_player(Vector3(4.0, 0.0, OPEN_Z))
	var enemy := _spawn_enemy(Vector3(-6.0, 0.0, OPEN_Z), Vector3(-30.0, 0.0, OPEN_Z))
	var ai := _ai(enemy)
	await _physics(40)
	_check(
		"игрок за спиной врага (вне конуса, дальше awareness_range) не замечен",
		ai.state == C_EnemyAI.State.IDLE,
		"state=%s" % ai.state
	)
	_check(
		"вне конуса луч даже не бросается — конус дешевле луча",
		ai.sight_rays == 0,
		"лучей=%d" % ai.sight_rays
	)

	(enemy as Node as Node3D).look_at(Vector3(4.0, 0.05, OPEN_Z), Vector3.UP)
	await _physics(30)
	_check("развернулся к игроку — заметил", ai.state == C_EnemyAI.State.CHASING, "state=%s" % ai.state)
	await _drop(enemy)

	_put_player(Vector3(-6.0 + ai.awareness_range * 0.5, 0.0, OPEN_Z))
	var close := _spawn_enemy(Vector3(-6.0, 0.0, OPEN_Z), Vector3(-30.0, 0.0, OPEN_Z))
	await _physics(30)
	_check(
		"вплотную за спиной (ближе awareness_range) враг игрока замечает",
		_ai(close).state != C_EnemyAI.State.IDLE,
		"state=%s" % _ai(close).state
	)
	await _drop(close)


## Лучи не каждый кадр: за две секунды непрерывной погони их порядка десятка, а не
## сто двадцать.
func _check_ray_rate() -> void:
	_put_player(Vector3(0.0, 0.0, OPEN_Z))
	var enemy := _spawn_enemy(Vector3(-8.0, 0.0, OPEN_Z), _player_node.global_position)
	var ai := _ai(enemy)
	ai.attack_range = 0.5
	await _physics(2)
	ai.sight_rays = 0
	var frames := 120
	await _physics(frames)
	# Потолок с запасом на разброс периода (−20 %) и границы окна.
	var ceiling := ceili(frames / 60.0 / (ai.sight_interval * 0.8)) + 2
	_check(
		"за %d физкадров (2 с) лучей обзора не больше %d, но проверка идёт" % [frames, ceiling],
		ai.sight_rays >= 2 and ai.sight_rays <= ceiling,
		"лучей=%d" % ai.sight_rays
	)
	await _drop(enemy)


# ---------------------------------------------------------------------------
# Память
# ---------------------------------------------------------------------------


## Враг видел игрока, тот пропал из виду: враг идёт на место, где видел его
## последний раз, стоит там и сдаётся. Не к новому месту игрока, которого он
## не знает.
func _check_memory() -> void:
	var seen_at := Vector3(4.0, 0.0, OPEN_Z)
	_put_player(seen_at)
	var enemy := _spawn_enemy(Vector3(-6.0, 0.0, OPEN_Z), seen_at)
	var ai := _ai(enemy)
	var node := enemy as Node as Node3D
	ai.linger_time = 0.5
	ai.attack_range = 0.5
	await _physics(20)
	_check("видит игрока — гонится", ai.state == C_EnemyAI.State.CHASING, "state=%s" % ai.state)

	# Игрок исчезает далеко за радиус обзора (на другой край арены).
	var gone := Vector3(25.0, 0.0, 25.0)
	_put_player(gone)
	await _physics(30)
	_check(
		"потерял из виду — ищет, а не стоит и не бросил",
		ai.state == C_EnemyAI.State.SEARCHING,
		"state=%s" % ai.state
	)
	_check(
		"помнит место, где видел игрока последний раз",
		_flat(ai.last_seen_position, seen_at) < 0.5,
		"запомнил %s, видел в %s" % [ai.last_seen_position, seen_at]
	)

	var guard := 0
	while _flat(node.global_position, seen_at) > ai.arrive_distance and guard < 60:
		await _physics(10)
		guard += 1
	_check(
		"дошёл до места, где видел игрока",
		_flat(node.global_position, seen_at) <= ai.arrive_distance + 0.3,
		"осталось %.2f м" % _flat(node.global_position, seen_at)
	)
	_check(
		"в поисках не пошёл к новому месту игрока, которого не знает",
		_flat(node.global_position, gone) > 20.0,
		"до игрока %.1f м" % _flat(node.global_position, gone)
	)

	await _physics(int(ai.linger_time * 60.0) + 30)
	_check(
		"дойдя и не увидев — сдаётся через linger_time",
		ai.state == C_EnemyAI.State.IDLE,
		"state=%s" % ai.state
	)
	await _drop(enemy)


# ---------------------------------------------------------------------------
# Навигация
# ---------------------------------------------------------------------------


## Враг видит игрока над низкой стенкой и идёт на него. Без навмеша — по прямой, то
## есть упирается в стенку; после запекания обходит её и доходит.
func _check_path_around_obstacle() -> void:
	var target := Vector3(6.0, 0.0, 0.0)
	_put_player(target)
	var enemy := _spawn_enemy(Vector3(-6.0, 0.0, 0.0), target)
	var node := enemy as Node as Node3D
	var ai := _ai(enemy)
	await _physics(180)
	_check(
		"без навмеша враг идёт по прямой: дошёл до стенки и стоит перед ней",
		ai.state == C_EnemyAI.State.CHASING and node.global_position.x < -0.3 and node.global_position.x > -3.0,
		"x=%.2f state=%s" % [node.global_position.x, ai.state]
	)
	_check("до готовности навмеша путь пуст", ai.path.size() <= 1, "точек пути %d" % ai.path.size())

	_nav.bake(_world)
	var guard := 0
	while not _nav.is_ready() and guard < 600:
		await _physics(1)
		guard += 1
	_check("навмеш запёкся и применён картой", _nav.is_ready(), "ждали %d физкадров" % guard)
	if not _nav.is_ready():
		return
	print("  замер арены: разбор %.1f мс, запекание %.1f мс" % [_nav.parse_usec / 1000.0, _nav.bake_usec / 1000.0])
	var cell_wrong: Array[String] = []
	for path: String in _nav.regions:
		var region := _nav.regions[path]
		var map := region.get_navigation_map()
		if not is_equal_approx(region.navigation_mesh.cell_size, NavigationServer3D.map_get_cell_size(map)) \
				or not is_equal_approx(region.navigation_mesh.cell_height, NavigationServer3D.map_get_cell_height(map)):
			cell_wrong.append(path.get_file())
	_check("ячейка каждого навмеша совпала со своей картой", cell_wrong.is_empty(), ", ".join(cell_wrong))

	var max_z := -INF
	var reached := false
	for step in 80:
		await _physics(10)
		max_z = maxf(max_z, node.global_position.z)
		if _flat(node.global_position, target) <= ai.attack_range + 0.4:
			reached = true
			break
	_check(
		"после запекания враг обошёл стенку и дошёл до игрока",
		reached,
		"до игрока %.2f м, x=%.2f z=%.2f" % [_flat(node.global_position, target), node.global_position.x, node.global_position.z]
	)
	_check(
		"обход шёл вокруг конца стенки (z > 4), а не сквозь неё",
		max_z > 4.0,
		"max z=%.2f" % max_z
	)
	await _drop(enemy)

	# Навмеш слоя уходит вместе со слоем: снятый регион не остаётся в карте.
	_nav.clear()
	_check("clear() снимает регионы", _nav.regions.is_empty(), "")
	await _physics(2)


## Параметры агента в данных покрывают тела врагов: иначе навмеш прокладывает путь
## там, где капсула врага не пройдёт, и маска геометрии разошлась бы с тем, во что
## враг упирается физически.
func _check_template_covers_enemies() -> void:
	var first := load(LayerNavigation.PROFILES[0]) as NavigationMesh
	var parse_wrong: Array[String] = []
	for path in LayerNavigation.PROFILES:
		var other := load(path) as NavigationMesh
		if other.geometry_parsed_geometry_type != first.geometry_parsed_geometry_type \
				or other.geometry_collision_mask != first.geometry_collision_mask \
				or other.geometry_source_geometry_mode != first.geometry_source_geometry_mode:
			parse_wrong.append(path.get_file())
	# Геометрия разбирается один раз, по первому шаблону: расхождение в разборе
	# у другого шаблона молча не применилось бы.
	_check("разбор геометрии у всех шаблонов навмеша общий", parse_wrong.is_empty(), ", ".join(parse_wrong))

	var unknown: Array[String] = []
	var uncovered: Array[String] = []
	var mask_wrong: Array[String] = []
	var used := {}
	var scenes := 0
	for file in DirAccess.get_files_at(ENEMY_DIR):
		if not file.begins_with("e_enemy") or not file.ends_with(".tscn"):
			continue
		scenes += 1
		var enemy := (load(ENEMY_DIR + file) as PackedScene).instantiate() as E_Enemy
		var profile: NavigationMesh = null
		for component in enemy.component_resources:
			if component is C_EnemyAI:
				profile = (component as C_EnemyAI).nav_profile
		if profile == null or not LayerNavigation.PROFILES.has(profile.resource_path):
			unknown.append(file)
			(enemy as Node).free()
			continue
		used[profile.resource_path] = true
		for shape_node in enemy.find_children("*", "CollisionShape3D", true, false):
			var capsule := (shape_node as CollisionShape3D).shape as CapsuleShape3D
			if capsule != null and (capsule.radius > profile.agent_radius or capsule.height > profile.agent_height):
				uncovered.append("%s (капсула %.2f×%.2f, агент %.2f×%.2f)" % [
					file, capsule.radius, capsule.height, profile.agent_radius, profile.agent_height])
		var solid := (enemy as Node as CharacterBody3D).collision_mask & ~PLAYER_LAYER
		if solid != profile.geometry_collision_mask:
			mask_wrong.append(file)
		(enemy as Node).free()
	_check("найдены сцены врагов", scenes >= 5, "найдено %d" % scenes)
	_check("у каждого врага шаблон навмеша из LayerNavigation.PROFILES", unknown.is_empty(), ", ".join(unknown))
	_check("шаблон навмеша врага покрывает его капсулу", uncovered.is_empty(), "; ".join(uncovered))
	_check(
		"маска геометрии навмеша — это то, во что враг упирается, кроме игрока",
		mask_wrong.is_empty(),
		"расходятся: %s" % ", ".join(mask_wrong)
	)
	_check("каждый шаблон кому-то нужен", used.size() == LayerNavigation.PROFILES.size(), str(used.keys()))


## Навмеш на каждый размер: под балкой, низ которой выше обычного агента и ниже
## крупного, навмеш обычного размера есть, крупного — нет, и у размеров разные
## карты. Ради этого навмеши и разделены: один общий по самому крупному выбросил
## бы такое место и для мелких врагов.
func _check_sizes() -> void:
	_nav.bake(_world)
	var guard := 0
	while not _nav.is_ready() and guard < 600:
		await _physics(1)
		guard += 1
	_check("навмеши всех размеров запеклись", _nav.is_ready(), "ждали %d физкадров" % guard)
	if not _nav.is_ready():
		return
	var small := _nav.regions[LayerNavigation.PROFILES[0]].get_navigation_map()
	var large := _nav.regions[LayerNavigation.PROFILES[1]].get_navigation_map()
	_check("у каждого размера своя карта", small != large, "")

	# Ближайшая точка навмеша к полу под серединой балки. Пол «на навмеше», если она
	# рядом по горизонтали и внизу: навмеш лежит чуть выше пола, а верх балки тоже
	# проходим, и у крупного ближайшей может оказаться точка на нём.
	var near_small := NavigationServer3D.map_get_closest_point(small, BEAM_CENTER)
	var near_large := NavigationServer3D.map_get_closest_point(large, BEAM_CENTER)
	_check(
		"под балкой %.1f м обычный враг проходит" % BEAM_BOTTOM,
		_on_floor_under_beam(near_small),
		"ближайшая точка %s" % near_small
	)
	_check(
		"под балкой %.1f м крупному навмеша нет" % BEAM_BOTTOM,
		not _on_floor_under_beam(near_large),
		"ближайшая точка %s" % near_large
	)

	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as E_Enemy
	_world.add_entity(enemy)
	var profile := (enemy.get_component(C_EnemyAI) as C_EnemyAI).nav_profile
	_check("враг получает карту своего размера", LayerNavigation.map_for(enemy as Node, profile) == small, "")
	await _drop(enemy)

	_nav.clear()
	_check(
		"после clear() карты размера нет — враг идёт по прямой",
		not LayerNavigation.map_for(_world, load(LayerNavigation.PROFILES[0]) as NavigationMesh).is_valid(),
		""
	)
	await _physics(2)


func _on_floor_under_beam(point: Vector3) -> bool:
	return _flat(point, BEAM_CENTER) < 0.3 and point.y < BEAM_BOTTOM * 0.5


# ---------------------------------------------------------------------------
# Настоящий слой
# ---------------------------------------------------------------------------


## Спавн слоя запекает навмеш, снос — снимает, а перебитый запекание не оставляет
## региона от прошлого слоя. Сид и ручки — как в corridor_spawn_check.
func _check_real_layer() -> void:
	_world.remove_entity(_player)
	if is_instance_valid(_player):
		(_player as Node).free()
	_world.queue_free()
	await get_tree().process_frame
	_world = _new_world()

	GameConfig.config.world_gen = _base_config.duplicate() as RS_WorldGenConfig
	var fresh := RS_WorldSave.new()
	fresh.world_seed = 424242
	WorldSave.save = fresh

	RunManager.enter_complex(424242)
	var layer := RunManager.layer
	var guard := 0
	while not layer.navigation.is_ready() and guard < 600:
		await _physics(1)
		guard += 1
	_check("спавн слоя запёк навмеш, и карта его применила", layer.navigation.is_ready(), "ждали %d физкадров" % guard)
	if not layer.navigation.is_ready():
		RunManager._end_run()
		return
	print("  замер слоя %d (сид 424242, %d комнат, %d коридорных узлов): разбор %.1f мс на главном потоке, запекание %.1f мс в потоке" % [
		layer.depth, layer.rooms.size(), layer.corridor_tiles.size(),
		layer.navigation.parse_usec / 1000.0, layer.navigation.bake_usec / 1000.0])

	var map := layer.navigation.regions[LayerNavigation.PROFILES[0]].get_navigation_map()
	var uncovered: Array[String] = []
	for id: StringName in layer.rooms:
		var origin := (layer.rooms[id].entity as Node as Node3D).global_position
		var near := NavigationServer3D.map_get_closest_point(map, origin)
		# Клетка 8 м: навмеш лежит на полу комнаты, а не где-то в соседней.
		if near.distance_to(origin) > 8.0:
			uncovered.append("%s (%.1f м)" % [id, near.distance_to(origin)])
	_check(
		"навмеш лежит под каждой комнатой слоя",
		uncovered.is_empty(),
		", ".join(uncovered.slice(0, 4))
	)

	var regions := layer.navigation.regions.values()
	var depth := layer.depth
	layer.despawn()
	var alive := 0
	for region: Variant in regions:
		if is_instance_valid(region):
			alive += 1
	_check(
		"снос слоя снимает регионы навмеша",
		alive == 0 and layer.navigation.regions.is_empty(),
		"живых регионов %d" % alive
	)

	# Запекание, которое не дождалось сноса: слой снесён, пока поток считал, и
	# результат прошлого слоя не должен лечь в карту нового.
	layer.spawn(depth)
	layer.despawn()
	await _physics(60)
	_check(
		"запекание, перебитое сносом слоя, региона не оставляет",
		layer.navigation.regions.is_empty() and get_tree().get_nodes_in_group(LayerNavigation.GROUP).is_empty(),
		""
	)

	RunManager._end_run()


func _restore() -> void:
	GameConfig.config.world_gen = _base_config
	WorldSave.save = _save_object
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	elif FileAccess.file_exists(WorldSave.SAVE_PATH):
		DirAccess.remove_absolute(WorldSave.SAVE_PATH)
