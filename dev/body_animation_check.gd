extends "res://dev/check_harness.gd"
## Анимации тел: правило «способность ⇒ обязательные клипы», облик на риге (сцена облика, голова и руки тенью,
## руки-муляж на камере) и то, что S_BodyAnimation включает по делу тела, — ход, удар, попадание, гибель трупа.
## Запускать: godot --headless dev/body_animation_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const HOUND_BODY := "res://src/entities/body/e_body_hound.tscn"
const HOUND_ENEMY := "res://src/entities/enemy/e_enemy_hound.tscn"
const CRAWLER_BODY := "res://src/entities/body/e_body_crawler.tscn"
## Что сцена облика вправе менять у узлов из .glb.
const ALLOWED_OVERRIDES: Array[StringName] = [&"extra_cull_margin", &"cast_shadow", &"material_override", &"unique_id"]
const SCENE_DIRS: Array[String] = ["res://src/entities/body/", "res://src/entities/enemy/", "res://src/entities/body/fp_arms/"]


func _ready() -> void:
	var world := _new_world()
	# Пол и настоящее движение: «на полу ли» — флаг move_and_slide(), без него тело всё время в воздухе.
	_add_floor()
	_add_systems(world, "physics", [S_BodySnatch.new(), S_Gravity.new(), S_Movement.new()])
	_add_systems(world, "gameplay", [S_BodyAnimation.new(), S_FirstPersonMotion.new()])
	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_BodyVisual.new())
	world.add_observer(O_BodyForm.new())

	_check_clip_contract()
	_check_appearance_overrides()
	await _check_worn(world)
	await _check_enemy(world)
	await _check_air(world)
	await _check_corpse(world)
	_finish()


# --- 1. Способность ⇒ клипы, дерево ⇒ клипы ------------------------------------
func _check_clip_contract() -> void:
	var animated := 0
	for path in _scenes():
		var probe := (load(path) as PackedScene).instantiate()
		var tree := RS_EntityVisuals.animation_tree(probe)
		if tree == null:
			probe.free()
			continue  # тело ещё не переведено на свой .glb — анимаций у него нет
		animated += 1
		var name := path.get_file()
		var missing := _missing_for_abilities(probe, tree)
		_check("%s: у каждой способности есть её клипы" % name, missing.is_empty(), str(missing))
		var unresolved := _unresolved(tree)
		_check("%s: каждый клип дерева есть в библиотеках" % name, unresolved.is_empty(), str(unresolved))
		probe.free()
	_check("анимированные сцены нашлись", animated >= 3, str(animated))

	# Детектор: библиотека без run у тела с бегом обязана провалить правило.
	var probe := (load(HOUND_BODY) as PackedScene).instantiate()
	var tree := RS_EntityVisuals.animation_tree(probe)
	var full := tree.get_animation_library(&"quadruped")
	var cut := AnimationLibrary.new()
	for clip in full.get_animation_list():
		if clip != &"run":
			cut.add_animation(clip, full.get_animation(clip))
	tree.remove_animation_library(&"quadruped")
	tree.add_animation_library(&"quadruped", cut)
	_check("пропавший клип способности ловится", _missing_for_abilities(probe, tree).has(&"run"), "")
	_check("пропавший клип дерева ловится", _unresolved(tree).has(&"quadruped/run"), "")
	probe.free()


## Клипы, которых требуют способности сцены (константа CLIPS скрипта компонента), а библиотеки дерева не держат.
func _missing_for_abilities(probe: Node, tree: AnimationTree) -> Array[StringName]:
	var missing: Array[StringName] = []
	var entity := probe as Entity
	if entity == null:
		return missing
	for component in entity.component_resources:
		var clips: Array = (component.get_script() as Script).get_script_constant_map().get("CLIPS", [])
		for clip in clips:
			var found := tree.get_animation_library_list().any(
				func(key: StringName) -> bool: return tree.get_animation_library(key).has_animation(clip)
			)
			if not found:
				missing.append(clip)
	return missing


func _unresolved(tree: AnimationTree) -> Array[StringName]:
	var names: Array[StringName] = []
	_clip_names(tree.tree_root, names)
	return names.filter(func(clip: StringName) -> bool: return not tree.has_animation(clip))


func _clip_names(node: AnimationNode, out: Array[StringName]) -> void:
	if node is AnimationNodeAnimation:
		out.append((node as AnimationNodeAnimation).animation)
	elif node is AnimationNodeBlendTree:
		for child in (node as AnimationNodeBlendTree).get_node_list():
			_clip_names((node as AnimationNodeBlendTree).get_node(child), out)
	elif node is AnimationNodeStateMachine:
		for child in (node as AnimationNodeStateMachine).get_node_list():
			_clip_names((node as AnimationNodeStateMachine).get_node(child), out)


func _scenes() -> Array[String]:
	var out: Array[String] = []
	for dir_path in SCENE_DIRS:
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".tscn"):
				out.append(dir_path + file)
	return out


# --- 2. Облик на риге ------------------------------------------------------------
func _check_worn(world: World) -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame
	var sphere := RS_EntityVisuals.primary(player) as MeshInstance3D
	var ghost_mesh := sphere.mesh

	await _capture(world, player, HOUND_BODY, Vector3(3, 0, 0))
	await get_tree().process_frame
	var worn := player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE)) as Node3D
	_check("риг надел сцену облика", worn != null and worn.scene_file_path.ends_with("SK_hound.tscn"),
		worn.scene_file_path if worn else "нет узла")
	_check("вид БФЖ спрятан, а не подменён", not sphere.visible and sphere.mesh == ghost_mesh, "")
	if worn != null:
		var shadows := worn.find_children("*", "GeometryInstance3D", true, false).filter(
			func(geo: GeometryInstance3D) -> bool:
				return geo.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		).map(func(geo: Node) -> String: return String(geo.name))
		shadows.sort()
		_check("голова и руки облика — только тенью, тело видно", shadows == ["hound_arms", "hound_head"], str(shadows))
		_check("рэгдолл с надетого облика снят", worn.find_children("*", "PhysicalBone3D", true, false).is_empty(), "")
		var feet := RS_EntityVisuals.transform_relative_to(worn, player).origin.y
		_check("облик сел подошвами на пол", is_equal_approx(feet, -player.foot_offset().y),
			"%.3f вместо %.3f" % [feet, -player.foot_offset().y])
		_check("облик смотрит в −Z, как камера", worn.transform.basis.z.z < 0.0, str(worn.transform.basis.z))
	var tree := player.get_node(O_BodyVisual.TREE_NODE) as AnimationTree
	_check("дерево рига проснулось с клипами тела", tree.active and tree.tree_root != null and tree.has_animation(&"quadruped/idle"), "")
	var arms := player.camera.get_node_or_null(NodePath(O_BodyVisual.FP_ARMS_NODE))
	_check("руки-муляж на камере", arms != null, "")
	if arms != null:
		var arm_mesh := arms.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_check("руки-муляж своей тени не дают", arm_mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "")
		var material := arm_mesh.mesh.surface_get_material(0) as BaseMaterial3D
		_check("материал рук не клипует в стены",
			material != null and material.use_fov_override and material.use_z_clip_scale, str(material))
	await _check_camera_motion(player)

	# Пересадка в тело без сцены облика: прошлый облик снят, меш тела на виде БФЖ.
	await _capture(world, player, CRAWLER_BODY, Vector3(-3, 0, 0))
	await get_tree().process_frame
	_check("пересадка снимает прошлый облик", player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE)) == null, "")
	_check("пересадка снимает руки-муляж", player.camera.get_node_or_null(NodePath(O_BodyVisual.FP_ARMS_NODE)) == null, "")
	_check("тело без сцены облика — меш на виде БФЖ", sphere.visible and sphere.mesh != ghost_mesh, "")
	_check("дерево рига уснуло", not tree.active, "")

	await _capture(world, player, HOUND_BODY, Vector3(6, 0, 0))
	await get_tree().process_frame
	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame
	_check("выход снимает облик", player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE)) == null, "")
	_check("выход возвращает вид БФЖ", sphere.visible and sphere.mesh == ghost_mesh, "видна=%s, меш=%s, призрак=%s" % [sphere.visible, sphere.mesh, ghost_mesh])
	await _animate(1)
	var look := player.get_component(C_FPSCamera) as C_FPSCamera
	_check("после выхода камера без качки", player.camera.h_offset == 0.0 and player.camera.v_offset == 0.0
		and player.camera.rotation.z == 0.0 and is_equal_approx(player.camera.rotation.x, look.pitch)
		and player.camera.position == look.eye_position, str(player.camera.position))
	world.remove_entity(player)
	player.queue_free()
	await get_tree().process_frame


## Камера в hound стоит там, где голова облика: стоя чуть впереди маркера Eyes, в беге — на метр ниже и впереди,
## в укусе — выпадом вперёд; у стены не уходит за неё. Качка — сдвигом картинки.
func _check_camera_motion(player: E_Player) -> void:
	var camera := player.camera
	var look := player.get_component(C_FPSCamera) as C_FPSCamera
	var motion := player.get_component(C_FirstPersonMotion) as C_FirstPersonMotion
	# Сила качки — настройка игрока: проверка ставит свою и возвращает его (в файл ничего не пишется).
	var players_motion := SettingsManager.settings.camera_motion
	SettingsManager.settings.camera_motion = RS_Settings.CAMERA_MOTION_FULL
	await _animate(30)
	var base := look.eye_position
	_check("стоя камера у глаз облика, а не у маркера", camera.position.is_equal_approx(base + motion.stand_head),
		"%s, база %s" % [camera.position, base])

	var vel := player.get_component(C_Velocity) as C_Velocity
	var sprint := player.get_component(C_Sprint) as C_Sprint
	sprint.active = true
	vel.velocity = Vector3(4, 0, 0)
	var swayed := 0.0
	for i in 80:
		await _animate(1)
		swayed = maxf(swayed, absf(camera.v_offset))
	_check("на бегу камера качается", swayed > 0.01, "%.3f м" % swayed)
	_check("в беге камера опустилась к голове и ушла вперёд",
		camera.position.y < base.y - 0.8 and camera.position.z < base.z - 0.6, "%s, база %s" % [camera.position, base])
	SettingsManager.settings.camera_motion = RS_Settings.CAMERA_MOTION_OFF
	var still := 0.0
	var running_at := camera.position
	for i in 30:
		await _animate(1)
		still = maxf(still, absf(camera.v_offset) + absf(camera.h_offset) + absf(camera.rotation.z))
	_check("покачивание выкл — качки нет, голова на месте", still == 0.0 and camera.position.distance_to(running_at) < 0.01,
		"качка %.4f, сдвиг %.3f" % [still, camera.position.distance_to(running_at)])
	SettingsManager.settings.camera_motion = RS_Settings.CAMERA_MOTION_FULL

	# Стена в 0.6 м перед центром тела: голова в беге (0.94 м вперёд) за ней, камера — нет.
	var wall := StaticBody3D.new()
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	(box.shape as BoxShape3D).size = Vector3(4, 8, 0.2)
	wall.add_child(box)
	add_child(wall)
	var forward: Vector3 = -player.global_basis.z
	wall.global_transform = Transform3D(player.global_basis, player.global_position + forward * 0.7)
	await _physics(3)
	await _animate(2)
	var ahead: float = (camera.global_position - player.global_position).dot(forward)
	_check("у стены камера не уходит за неё, но и не прячется в базу", ahead < 0.6 - 0.05 and ahead > 0.2, "%.3f м впереди центра, стена в 0.6" % ahead)
	wall.queue_free()
	await _physics(3)
	sprint.active = false
	vel.velocity = Vector3.ZERO
	await _animate(90)

	var attack := player.get_component(C_Attack) as C_Attack
	var stand := camera.position
	attack.cooldown_left = attack.interval
	await _animate(int(motion.bite_time * motion.bite_peak * 60.0))
	_check("укус выносит камеру вперёд и клюёт вниз",
		camera.position.z < stand.z - 0.2 and camera.rotation.x < look.pitch - 0.03,
		"z %.3f при %.3f, тангаж %.3f при %.3f" % [camera.position.z, stand.z, camera.rotation.x, look.pitch])
	await _animate(40)
	_check("укус отыграл — камера вернулась",
		is_equal_approx(camera.rotation.x, look.pitch) and camera.position.distance_to(stand) < 0.01, str(camera.position))
	SettingsManager.settings.camera_motion = players_motion


func _capture(world: World, player: E_Player, scene: String, at: Vector3) -> void:
	var body := (load(scene) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = at
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	await _physics(1)


# --- 3. Враг: ход, удар, попадание ----------------------------------------------
func _check_enemy(world: World) -> void:
	var enemy := (load(HOUND_ENEMY) as PackedScene).instantiate() as E_Enemy
	world.add_entity(enemy)
	await get_tree().process_frame
	_check("рэгдолл с облика врага снят", enemy.find_children("*", "PhysicalBone3D", true, false).is_empty(), "")
	var tree := RS_EntityVisuals.animation_tree(enemy)
	var playback := tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback
	var vel := enemy.get_component(C_Velocity) as C_Velocity

	var anim := enemy.get_component(C_BodyAnimation) as C_BodyAnimation
	var fast := anim.run_from_speed + 1.0
	var trotting := (anim.trot_from_speed + anim.run_from_speed) * 0.5
	for case in [[Vector3(fast, 0, 0), &"run"], [Vector3(trotting, 0, 0), &"trot"], [Vector3(1.0, 0, 0), &"walk"],
			[Vector3.ZERO, &"idle"]]:
		vel.velocity = case[0]
		# Полторы секунды: переход идёт в темпе клипа (pace стоит после машины состояний), медленный шаг тянет его вдвое.
		await _animate(90)
		_check("враг на %.1f м/с — %s" % [case[0].length(), case[1]], playback.get_current_node() == case[1],
			"играет %s, хочет %s, путь %s" % [playback.get_current_node(), anim.state, playback.get_travel_path()])

	vel.velocity = Vector3(fast, 0, 0)
	await _animate(10)
	var pace := clampf(fast / anim.run_clip_speed, S_BodyAnimation.RUN_PACE.x, S_BodyAnimation.RUN_PACE.y)
	_check("клип бега ускорен под ход", is_equal_approx(tree.get(S_BodyAnimation.PACE), pace), str(tree.get(S_BodyAnimation.PACE)))
	vel.velocity = Vector3.ZERO

	var ai := enemy.get_component(C_EnemyAI) as C_EnemyAI
	ai.attack_cooldown_left = ai.attack_interval
	await _animate(2)
	_check("замах врага играет укус", tree.get(&"parameters/action/active"), "")

	var health := enemy.get_component(C_Health) as C_Health
	health.current -= 5.0
	await _animate(2)
	_check("попадание играет удар", tree.get(&"parameters/hit/active"), "")
	world.remove_entity(enemy)
	enemy.queue_free()
	await get_tree().process_frame


# --- 4. Труп: гибель клипом, потом рэгдолл; тело в комнате — сразу рэгдолл -----
func _check_corpse(world: World) -> void:
	var holder := Node3D.new()
	add_child(holder)
	var enemy := (load(HOUND_ENEMY) as PackedScene).instantiate() as E_Enemy
	holder.add_child(enemy)
	world.add_entity(enemy)
	await get_tree().process_frame
	O_EnemyDeath.replace_with_corpse(enemy)
	await get_tree().process_frame
	var corpse := holder.get_child(holder.get_child_count() - 1) as E_Body
	var tree := RS_EntityVisuals.animation_tree(corpse)
	var playback := tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback
	var simulator := corpse.find_children("*", "PhysicalBoneSimulator3D", true, false)[0] as PhysicalBoneSimulator3D
	await _animate(5)
	_check("свежий труп падает клипом гибели", tree.active and playback.get_current_node() == S_BodyAnimation.DEATH,
		str(playback.get_current_node()))
	_check("рэгдолл ждёт конца клипа", not simulator.is_simulating_physics(), "")
	var length := tree.get_animation(&"quadruped/death").length
	await get_tree().create_timer(length + 0.2).timeout
	_check("после клипа тело подхватил рэгдолл", simulator.is_simulating_physics() and not tree.active, "")

	var lying := (load(HOUND_BODY) as PackedScene).instantiate() as E_Body
	holder.add_child(lying)
	await get_tree().process_frame
	var lying_sim := lying.find_children("*", "PhysicalBoneSimulator3D", true, false)[0] as PhysicalBoneSimulator3D
	_check("тело в комнате лежит рэгдоллом с начала",
		lying_sim.is_simulating_physics() and not RS_EntityVisuals.animation_tree(lying).active, "")
	holder.queue_free()
	await get_tree().process_frame


## Тики системы вперемешку с кадрами: физтик двигает тела, AnimationTree двигается в process-кадре.
func _animate(frames: int) -> void:
	for i in frames:
		# Сразу после physics_frame — внутри физкадра: move_and_slide() и space-state Jolt здесь законны.
		await get_tree().physics_frame
		ECS.process(1.0 / 60.0, "physics")
		ECS.process(1.0 / 60.0, "gameplay")
		await get_tree().process_frame


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(400, 1, 400)
	floor_body.add_child(shape)
	add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)


# --- 3б. Воздух: нет пола — клип полёта, какой бы ни была скорость -----------
func _check_air(world: World) -> void:
	var enemy := (load(HOUND_ENEMY) as PackedScene).instantiate() as E_Enemy
	world.add_entity(enemy)
	var body := enemy as Node as CharacterBody3D
	body.position = Vector3(0, 0, 60)
	var playback := RS_EntityVisuals.animation_tree(enemy).get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback
	var vel := enemy.get_component(C_Velocity) as C_Velocity
	var anim := enemy.get_component(C_BodyAnimation) as C_BodyAnimation
	var fast := anim.run_from_speed + 1.0

	# Прыжок с разбега: в воздухе только jump и jump_air, и из jump_air назад в jump не тянет.
	vel.velocity = Vector3(fast, 0, 0)
	await _animate(40)
	vel.velocity.y = 9.0
	# Первый кадр в воздухе дерево ещё в прежнем клипе: travel() срабатывает на следующем его тике.
	var flight := (await _flight(body, playback)).slice(1)
	_check("прыжок с разбега начинается клипом jump", flight.size() > 10 and flight[0] == &"jump", _brief(flight))
	_check("в прыжке ни шага, ни бега — только полёт", flight.all(func(s: StringName) -> bool: return S_BodyAnimation.AIRBORNE.has(s)),
		_brief(flight))
	_check("из jump_air назад в jump не возвращает",
		not flight.has(&"jump_air") or flight.rfind(&"jump") < flight.find(&"jump_air"), _brief(flight))
	await _animate(10)
	_check("на бегу приземление сразу уходит в бег", anim.state == &"run", str(anim.state))

	# Прыжок с места: приземление играет своим клипом.
	vel.velocity = Vector3.ZERO
	await _animate(30)
	vel.velocity.y = 9.0
	await _flight(body, playback)
	var landed: Array[StringName] = []
	for i in 10:
		await _animate(1)
		landed.append(playback.get_current_node())
	_check("прыжок с места: приземление играет jump_land", landed.has(&"jump_land"), _brief(landed))

	# Сход с края на бегу: вертикальная скорость поначалу около нуля, а тело уже в воздухе.
	vel.velocity = Vector3(fast, 0, 0)
	await _animate(60)
	body.position += Vector3(0, 6, 0)
	var fall := await _flight(body, playback)
	# Первые кадры без пола — выдержка AIR_DELAY (ступенька), дальше только полёт.
	var settled := fall.slice(ceili(S_Movement.AIR_GRACE * 60.0) + 2)
	_check("падение с края — jump_air, а не галоп", settled.size() > 10 and settled.all(
		func(s: StringName) -> bool: return s == &"jump_air"
	), _brief(fall))
	world.remove_entity(enemy)
	enemy.queue_free()
	await get_tree().process_frame


## Состояние дерева на каждом кадре, пока тело в воздухе.
func _flight(body: CharacterBody3D, playback: AnimationNodeStateMachinePlayback) -> Array[StringName]:
	var seen: Array[StringName] = []
	for i in 240:
		await _animate(1)
		if body.is_on_floor():
			if i > 3:
				break
			continue
		seen.append(playback.get_current_node())
	return seen


## Последовательность без повторов подряд — для сообщения о провале.
func _brief(states: Array[StringName]) -> String:
	var runs: Array[String] = []
	for state in states:
		if runs.is_empty() or not runs.back().begins_with(String(state) + "×"):
			runs.append("%s×1" % state)
		else:
			var parts: PackedStringArray = runs.back().split("×")
			runs[-1] = "%s×%d" % [parts[0], int(parts[1]) + 1]
	return ", ".join(runs)


## Сцена облика не переопределяет рэгдолл и точки крепления: их строит постимпорт из .glb, а сохранённая редактором
## поза костей перекрывала бы новую выгрузку из Blender — коллизии в игре оставались бы старыми.
func _check_appearance_overrides() -> void:
	for dir_name in DirAccess.get_directories_at("res://assets/characters"):
		for file in DirAccess.get_files_at("res://assets/characters/%s" % dir_name):
			if not (file.begins_with("SK_") and file.ends_with(".tscn")):
				continue
			var state := (load("res://assets/characters/%s/%s" % [dir_name, file]) as PackedScene).get_state()
			var stale: Array[String] = []
			for i in state.get_node_count():
				# Свой узел (модификатор) сцена задаёт целиком; у узла из .glb разрешена только отрисовка.
				if state.get_node_type(i) != &"":
					continue
				for p in state.get_node_property_count(i):
					var property := state.get_node_property_name(i, p)
					if not ALLOWED_OVERRIDES.has(property):
						stale.append("%s:%s" % [state.get_node_path(i), property])
			_check("%s: рэгдолл и точки крепления — из .glb, не переопределены" % file, stale.is_empty(), str(stale))
