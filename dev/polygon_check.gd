extends "res://dev/check_harness.gd"
## Полигон (dev/polygon/polygon.tscn) на настоящей сцене: те же системы, что в игре, без забега; стенд клипов ведёт
## время клипа сам и показывает версию вместо основной; общая подмена клипов доходит до манекена и новых деревьев, но не
## до стенда; манекен на дорожке проходит клипы хода, удар, попадание, прыжок и гибель тем путём, каким их узнаёт
## S_BodyAnimation; тело на мате захватывается с первого раза и кладётся заново; экраны станции берут ввод и камеру и
## отдают их; раздел «Полигон» меню отладки есть только в полигоне. Ломается это тихо — стенд показывает не тот клип,
## манекен бежит не тем клипом, подмена не доезжает. Запускать: godot --headless dev/polygon_check.tscn

const POLYGON := "res://dev/polygon/polygon.tscn"
const WORLD := "res://src/world/world.tscn"
const MENU := "res://dev/debug_menu.tscn"
const BODY_LIBRARY := "res://assets/characters/_rigs/quadruped/ANIM_quadruped.glb"
const ARMS_LIBRARY := "res://assets/characters/_rigs/quadruped/ANIM_quadruped_fp.glb"
## Путь синтетической версии: в папку версий проверка ничего не пишет, версия кладётся в список в памяти.
const FAKE_VARIANT := "res://dev/polygon/clips/ANIM_quadruped_run_as_walk.glb"

var _polygon: Node
var _station: Node3D
var _skill_save_backup := PackedByteArray()
var _had_skill_save := false


func _ready() -> void:
	# Выход из тела бывает «Чистым» и пишет очко в skills.tres — сейв разработчика снимается до всего.
	_skill_save_backup = FileAccess.get_file_as_bytes(SkillManager.SAVE_PATH)
	_had_skill_save = not _skill_save_backup.is_empty()

	_polygon = (load(POLYGON) as PackedScene).instantiate()
	add_child(_polygon)
	await _frames(5)
	_station = _polygon.stations()[0]

	_check_frame()
	await _check_stand()
	await _check_variants()
	await _check_treadmill()
	await _check_mat()
	await _check_screens()
	await _check_menu()
	await _check_exit()
	_restore_skill_save()
	_finish()


# --- 1. Каркас: мир игры без забега ---------------------------------------------
func _check_frame() -> void:
	var game := (load(WORLD) as PackedScene).instantiate()
	var wanted := _scripts_under(game.get_node("World/Systems"))
	game.free()
	var have := _scripts_under(_polygon.get_node("World/Systems"))
	_check("в полигоне те же системы и наблюдатели, что в игре", have == wanted,
		"лишние %s, нет %s" % [have.filter(func(p: String) -> bool: return not wanted.has(p)),
			wanted.filter(func(p: String) -> bool: return not have.has(p))])
	_check("полигон не начинает забег", RunManager.current_graph == null, "")
	var player := E_Player.find() as Node as Node3D
	var spawn := _station.get_node("Spawn") as Node3D
	var flat := Vector2(player.global_position.x - spawn.global_position.x, player.global_position.z - spawn.global_position.z)
	_check("игрок стоит на маркере первой станции", flat.length() < 0.5, "%.2f м от маркера" % flat.length())


## Скрипты систем и наблюдателей из самой сцены; добавленные на ходу (слушатель HUD) владельца-сцены не имеют.
func _scripts_under(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "", true, false):
		var script := node.get_script() as Script
		if script != null and (node is System or node is Observer) and node.owner != null:
			out.append(script.resource_path if script.resource_path != "" else "<без пути: %s>" % node.get_path())
	out.sort()
	return out


# --- 2. Стенд клипов ---------------------------------------------------------------
func _check_stand() -> void:
	var stand: Node3D = _station.stand
	stand.set_springs(false)
	stand.playing = false
	_check("на стенде клипы основной библиотеки тела, и те, что вне дерева, тоже",
		_sorted(Array(stand.clip_names())) == _sorted((load(BODY_LIBRARY) as AnimationLibrary).get_animation_list()),
		str(stand.clip_names()))
	_check("рэгдолла на стенде нет", stand.find_children("*", "PhysicalBone3D", true, false).is_empty(), "")

	stand.select_clip(&"run")
	stand.playing = false
	stand.seek(0.0)
	var start := await _pose(stand)
	stand.seek(stand.length() * 0.5)
	var middle := await _pose(stand)
	_check("перемотка двигает позу", not _same(start, middle), "")
	await _frames(10)
	_check("на паузе поза стоит", _same(middle, await _pose(stand)), "")

	var at: float = stand.time
	stand.step(1)
	_check("кадр вперёд — ровно шаг клипа и пауза", is_equal_approx(stand.time, at + stand.frame_step()) and not stand.playing,
		"%.4f → %.4f, шаг %.4f" % [at, stand.time, stand.frame_step()])

	stand.loop = false
	stand.seek(stand.length() - 0.01)
	stand.playing = true
	await _frames(10)
	_check("без петли клип встаёт на последнем кадре", not stand.playing and is_equal_approx(stand.time, stand.length()),
		"%.3f из %.3f" % [stand.time, stand.length()])
	stand.loop = true
	stand.seek(stand.length() - 0.01)
	stand.playing = true
	await _frames(10)
	_check("с петлёй клип идёт по кругу", stand.playing and stand.time < stand.length() * 0.5, "%.3f" % stand.time)
	stand.playing = false
	await _check_one_shot(stand)

	if not stand.has_arms():
		_check("у hound есть руки-муляж для стенда", false, "fp_arms_scene пуст")
		return
	stand.select_model(1)
	await _frames(1)
	var arms := _visible_meshes(stand)
	var shared := load("res://assets/characters/SK_hound_fp_arms/materials/MAT_hound_fp.tres") as BaseMaterial3D
	var unclipped := arms.all(func(mesh: MeshInstance3D) -> bool:
		var material := mesh.get_active_material(0) as BaseMaterial3D
		return material != null and not material.use_fov_override and not material.use_z_clip_scale)
	_check("руки-муляж на стенде видны одни и без «поджатого» материала", not arms.is_empty() and unclipped, str(arms))
	_check("общий материал рук не тронут — в игре он поджат как был", shared.use_fov_override and shared.use_z_clip_scale, "")
	_check("у рук свои клипы", _sorted(Array(stand.clip_names())) == _sorted((load(ARMS_LIBRARY) as AnimationLibrary).get_animation_list()),
		str(stand.clip_names()))
	stand.select_model(0)
	await _frames(1)


## Клип без петли в самом клипе (укус, гибель) плеер, доиграв, останавливает сам. Стенд, который ждал от плеера
## «играю», после этого молча не двигал позу: ни повтор, ни перемотка — помогал только повторный выбор клипа.
func _check_one_shot(stand: Node3D) -> void:
	var one_shot: StringName = &""
	for clip_name in stand.clip_names():
		stand.select_clip(StringName(clip_name))
		if not stand.is_looping_clip():
			one_shot = StringName(clip_name)
			break
	if one_shot == &"":
		_check("у тела есть клип без петли", false, str(stand.clip_names()))
		return
	stand.loop = false
	stand.playing = false
	stand.seek(stand.length() * 0.5)
	var middle := await _pose(stand)
	stand.playing = true
	await _frames(90)
	var last := await _pose(stand)
	_check("%s: без петли доигрывается и встаёт" % one_shot, not stand.playing and is_equal_approx(stand.time, stand.length()),
		"%.3f из %.3f" % [stand.time, stand.length()])

	stand.toggle_play()
	await _frames(3)
	_check("%s: доигранный клип пускается заново с начала" % one_shot,
		stand.playing and stand.time < stand.length() * 0.5 and not _same(await _pose(stand), last),
		"играет %s, %.3f из %.3f" % [stand.playing, stand.time, stand.length()])

	stand.playing = false
	stand.seek(stand.length())
	await _pose(stand)
	stand.seek(stand.length() * 0.5)
	_check("%s: после конца клипа перемотка двигает позу" % one_shot, _same(await _pose(stand), middle), "")
	stand.loop = true


# --- 3. Версии клипов ------------------------------------------------------------
func _check_variants() -> void:
	var clips: RefCounted = _polygon.clips
	var officials: Array = clips.officials.keys()
	var sources := load("res://dev/polygon/clip_sources.gd")
	_check("версия рук узнаётся по самому длинному имени основной",
		sources.official_for_file("ANIM_quadruped_fp_прыжок.glb", officials) == ARMS_LIBRARY, "")
	_check("версия тела — к телу", sources.official_for_file("ANIM_quadruped_run2.glb", officials) == BODY_LIBRARY, "")
	_check("чужой файл ни к чему не относится", sources.official_for_file("hound_run.glb", officials) == "", "")

	# Версия, где run — это клип walk: разница видна позой, без файла на диске.
	var official := load(BODY_LIBRARY) as AnimationLibrary
	var fake := AnimationLibrary.new()
	fake.add_animation(&"run", official.get_animation(&"walk"))
	clips.variants.append({"path": FAKE_VARIANT, "title": "run_as_walk", "official": BODY_LIBRARY, "library": fake})

	var stand: Node3D = _station.stand
	stand.select_clip(&"walk")
	stand.playing = false
	stand.seek(0.3)
	var walk := await _pose(stand)
	stand.select_variant(FAKE_VARIANT)
	stand.select_clip(&"run")
	stand.playing = false
	stand.seek(0.3)
	_check("стенд с версией играет клип версии", _same(walk, await _pose(stand)), "")
	_check("клип из версии помечен, остальные — нет", Array(stand.overridden()) == ["run"], str(stand.overridden()))
	stand.toggle_ab()
	stand.seek(0.3)
	_check("A/B на той же позиции показывает основной клип", not _same(walk, await _pose(stand)) and is_equal_approx(stand.time, 0.3),
		"время %.3f" % stand.time)
	stand.select_variant("")

	# Общая подмена: манекен, новый манекен, но не стенд.
	var treadmill: Node3D = _station.treadmill
	var stand_player := _station.get_node("%StandPlayer") as AnimationPlayer
	var stand_library := stand_player.get_animation_library(stand_player.get_animation_library_list()[0])
	clips.choose(BODY_LIBRARY, FAKE_VARIANT)
	await _frames(1)
	_check("выбранная версия встала манекену", _library_of(treadmill.animation_tree()).get_animation(&"run") == fake.get_animation(&"run"), "")
	treadmill.spawn_puppet()
	await _frames(2)
	_check("новое дерево получает версию само", _library_of(treadmill.animation_tree()).get_animation(&"run") == fake.get_animation(&"run"), "")
	_check("стенд ведёт клипы сам — общая подмена его не трогает",
		stand_player.get_animation_library(stand_player.get_animation_library_list()[0]) == stand_library, "")
	clips.choose(BODY_LIBRARY, "")
	await _frames(1)
	_check("«основные» возвращают основную библиотеку", _library_of(treadmill.animation_tree()) == official, "")
	clips.variants.pop_back()


func _library_of(tree: AnimationTree) -> AnimationLibrary:
	return tree.get_animation_library(tree.get_animation_library_list()[0])


# --- 4. Дорожка: машина состояний на манекене -----------------------------------
func _check_treadmill() -> void:
	var treadmill: Node3D = _station.treadmill
	treadmill.spawn_puppet()
	await _frames(2)
	var puppet: E_Enemy = treadmill.puppet
	_check("манекен — враг без ввода: ИИ и ход его не берут, удар по-прежнему узнаётся по C_EnemyAI",
		not puppet.has_component(C_EnemyInput) and puppet.has_component(C_EnemyAI), "")

	var presets: Dictionary = treadmill.presets()
	var playback := treadmill.animation_tree().get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback
	var wrong: Array[String] = []
	for title in [["бег", &"run"], ["рысь", &"trot"], ["шаг", &"walk"], ["стоять", &"idle"]]:
		if not presets.has(title[0]):
			wrong.append("нет скорости «%s»" % title[0])
			continue
		treadmill.speed = presets[title[0]]
		await _frames(90)
		if playback.get_current_node() != title[1]:
			wrong.append("«%s» %.1f м/с играет %s" % [title[0], presets[title[0]], playback.get_current_node()])
	_check("каждая скорость дорожки даёт свой клип хода", wrong.is_empty(), ", ".join(wrong))

	treadmill.speed = presets.get("бег", 6.0)
	var worst := 0.0
	for i in 120:
		await _frames(1)
		var flat := (puppet as Node as Node3D).global_position - treadmill.global_position
		worst = maxf(worst, absf(Vector2(flat.x, flat.z).length() - treadmill.radius))
	_check("манекен бежит по кругу дорожки, а не уходит с неё", worst < 1.0, "отклонение до %.2f м" % worst)

	var tree: AnimationTree = treadmill.animation_tree()
	treadmill.bite()
	await _frames(3)
	_check("укус на дорожке играет удар", tree.get(&"parameters/action/active"), "")
	treadmill.hit()
	await _frames(3)
	_check("попадание играет удар по телу", tree.get(&"parameters/hit/active"), "")
	await _frames(5)
	var health := puppet.get_component(C_Health) as C_Health
	_check("после попадания прочность вернулась", is_equal_approx(health.current, health.maximum), "%.1f" % health.current)

	treadmill.jump()
	var flew := false
	for i in 40:
		await _frames(1)
		flew = flew or S_BodyAnimation.AIRBORNE.has(playback.get_current_node())
	_check("прыжок на ходу уходит в клип полёта", flew, "")

	treadmill.kill()
	await _frames(6)
	var corpse: E_Body = treadmill.corpse
	var corpse_tree := RS_EntityVisuals.animation_tree(corpse) if is_instance_valid(corpse) else null
	var corpse_playback := corpse_tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback if corpse_tree != null else null
	_check("гибель — настоящая: на месте манекена труп, падающий клипом гибели",
		corpse_playback != null and corpse_playback.get_current_node() == S_BodyAnimation.DEATH,
		"труп %s, дерево активно %s, играет %s" % [corpse, corpse_tree.active if corpse_tree else false,
			corpse_playback.get_current_node() if corpse_playback else &"—"])
	treadmill.spawn_puppet()
	await _frames(2)
	_check("«вернуть манекен» убирает труп и ставит живого", not is_instance_valid(corpse) and treadmill.alive(), "")
	treadmill.speed = 0.0


# --- 5. Мат: тело для первого лица -------------------------------------------------
func _check_mat() -> void:
	var mat: Node3D = _station.mat
	var body: E_Body = mat.body
	_check("на мате с начала лежит тело", is_instance_valid(body) and ECS.world.entities.has(body), "")
	_check("второе тело поверх лежащего не кладётся", not mat.lay_body(), "")
	var player := E_Player.find()
	body.add_component(C_SnatchTargeted.new())
	(player.get_component(C_BodySnatch) as C_BodySnatch).capture_requested = true
	await _frames(3)
	_check("захват в полигоне удаётся с первого раза", E_Player.is_embodied(), "")
	await _frames(1)
	_check("захваченное тело поглощено, и пульт кладёт новое", not is_instance_valid(body) and mat.lay_body(), "")
	O_ExpelFromBody.expel(player, false)
	await _frames(2)


# --- 6. Экраны станции -------------------------------------------------------------
func _check_screens() -> void:
	var player := E_Player.find() as E_Player
	for opener in [&"open_clips", &"open_states"]:
		var screen: Control = _station.call(opener)
		await _frames(2)
		var orbit := screen.get_node("%OrbitCamera") as Camera3D
		_check("%s: камера облёта ведёт кадр, ввод игрока заблокирован" % opener,
			orbit.current and player.has_component(C_UIBlocked), "")
		UIManager.close_top()
		await _frames(2)
		_check("%s: закрытие возвращает кадр и ввод игроку" % opener,
			player.camera.current and not player.has_component(C_UIBlocked), "")


# --- 7. Раздел «Полигон» меню отладки ----------------------------------------------
func _check_menu() -> void:
	var plain := (load(MENU) as PackedScene).instantiate()
	add_child(plain)
	plain.setup([] as Array[Dictionary], [] as Array[String], "сид")
	_check("вне полигона раздела «Полигон» нет", not (plain.get_node("%Polygon") as Control).visible, "")
	plain.free()

	var overlay := _polygon.find_children("*", "CanvasLayer", false, false).filter(
		func(node: Node) -> bool: return node.has_method(&"set_immortal"))[0] as Node
	overlay._open_menu()
	await _frames(1)
	var menu: Control = overlay._menu
	var buttons := (menu.get_node("%PolygonActions") as Node).get_children()
	var entries: Array[Dictionary] = _polygon.debug_entries()
	_check("в полигоне раздел открыт, кнопка на каждую запись полигона",
		(menu.get_node("%Polygon") as Control).visible and buttons.size() == entries.size(), "%d / %d" % [buttons.size(), entries.size()])

	var player := E_Player.find() as Node as Node3D
	player.global_position += Vector3(6, 0, 0)
	(buttons[0] as Button).pressed.emit()
	await _frames(2)
	var spawn := _station.get_node("Spawn") as Node3D
	_check("кнопка станции закрывает меню и ставит игрока на её маркер",
		not is_instance_valid(menu) and Vector2(player.global_position.x - spawn.global_position.x,
			player.global_position.z - spawn.global_position.z).length() < 0.5, "")


# --- 8. Уход со сцены --------------------------------------------------------------
func _check_exit() -> void:
	_polygon.set_time_scale(0.25)
	var clips: RefCounted = _polygon.clips
	_polygon.queue_free()
	await get_tree().process_frame
	_check("уход с полигона возвращает темп времени", Engine.time_scale == 1.0, str(Engine.time_scale))
	_check("и перестаёт подменять клипы в новых сценах", not get_tree().node_added.get_connections().any(
		func(c: Dictionary) -> bool: return (c.callable as Callable).get_object() == clips), "")


func _restore_skill_save() -> void:
	if _had_skill_save:
		var file := FileAccess.open(SkillManager.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_skill_save_backup)
			file.close()
	elif FileAccess.file_exists(SkillManager.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SkillManager.SAVE_PATH))
	_check("сейв навыков разработчика возвращён на место",
		FileAccess.get_file_as_bytes(SkillManager.SAVE_PATH) == _skill_save_backup, "")


# --- Помощники -----------------------------------------------------------------------
## Кадры идут сами: полигон крутит ECS из своих _process/_physics_process, как main.gd.
func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
	await get_tree().process_frame


## Повороты всех костей видимого облика стенда.
func _pose(stand: Node3D) -> Array[Quaternion]:
	await get_tree().process_frame
	var out: Array[Quaternion] = []
	for skeleton: Skeleton3D in stand.find_children("*", "Skeleton3D", true, false):
		if not skeleton.is_visible_in_tree():
			continue
		for bone in skeleton.get_bone_count():
			out.append(skeleton.get_bone_pose_rotation(bone))
	return out


func _same(a: Array[Quaternion], b: Array[Quaternion]) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):
			return false
	return true


func _visible_meshes(stand: Node3D) -> Array:
	return stand.find_children("*", "MeshInstance3D", true, false).filter(
		func(mesh: MeshInstance3D) -> bool: return mesh.is_visible_in_tree())


func _sorted(names: Array) -> Array:
	var out := names.map(func(name: Variant) -> String: return String(name))
	out.sort()
	return out
