extends "res://dev/check_harness.gd"
## Облик души (C_SoulCloud, S_SoulCloud) на настоящем e_player.tscn: вне тела
## сгусток, след и клочья у камеры видны и идут за душой; во плоти гаснут все;
## пересадка тело→тело и выход возвращают пустой слот меша, а не меш прошлого тела.
##
## Ломается это тихо: облик, не погасший во плоти, висит дымом поверх тела, а
## слот, запомнивший меш прошлого тела, после выхода оставляет душу в чужом теле.
## Слот — первая геометрия рига: частицы, вставшие раньше него в дереве, отняли
## бы его у O_BodyVisual, и вселение молча не надело бы меш.
##
## Чего не ловит: коалесценцию remove+add C_BodyVisual при пересадке, от которой
## страхует C_BodyVisual.restore_captured, — здесь снятие прошлого облика
## срабатывает раньше надевания, и мутация «без флага» проходит зелёной.
##
## Запускать: godot --headless dev/soul_cloud_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const BODY_SCENE := "res://src/entities/body/e_body.tscn"
const CRAWLER_SCENE := "res://src/entities/body/e_body_crawler.tscn"
const TICK := 0.016

var _skill_save_backup := PackedByteArray()
var _had_skill_save := false
var _original_skill_save: PlayerSkillSave


func _ready() -> void:
	# Выход из тела бывает «Чистым выходом» и сразу пишет очко в skills.tres — снимаем до мира.
	_skill_save_backup = FileAccess.get_file_as_bytes(SkillManager.SAVE_PATH)
	_had_skill_save = not _skill_save_backup.is_empty()
	_original_skill_save = SkillManager.save
	SkillManager.save = _original_skill_save.duplicate()
	SkillManager.save.ranks = _original_skill_save.ranks.duplicate()

	var world := _new_world()
	_add_systems(world, "physics", [S_BodySnatch.new()])
	_add_systems(world, "gameplay", [S_SoulCloud.new()])
	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_BodyVisual.new())
	world.add_observer(O_BodyForm.new())

	await _run(world)
	_restore_skill_save()

	_finish()


func _run(world: World) -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame
	var cloud := player.get_component(C_SoulCloud) as C_SoulCloud
	var root := player.get_node(cloud.root_path) as Node3D
	var head := player.get_node(cloud.head_path) as MultiMeshInstance3D
	var wisps := player.get_node(cloud.wisps_path) as GPUParticles3D
	var trail := _particles_under(root)
	var slot := RS_EntityVisuals.primary(player) as MeshInstance3D

	# --- 1. Вне тела облик виден и идёт за душой -------------------------
	_tick(10)
	_check("вне тела сгусток виден", root.visible, "")
	_check("вне тела клочья у камеры видны и идут", wisps.visible and wisps.emitting, "")
	_check("вне тела след идёт", not trail.is_empty() and trail.all(func(p: GPUParticles3D) -> bool: return p.emitting),
		"%d частиц под обликом" % trail.size())
	_check("у сгустка столько карточек, сколько задано", head.multimesh.instance_count == cloud.count,
		"%d из %d" % [head.multimesh.instance_count, cloud.count])
	_check("основной меш рига — пустой слот души, а не частица облика",
		slot != null and slot.mesh == null, str(RS_EntityVisuals.primary(player)))

	(player as Node as Node3D).global_position += Vector3(4.0, 0.0, 0.0)
	_tick(120)
	_check("сгусток ушёл за душой", head.global_position.distance_to((player as Node as Node3D).global_position) < 0.01,
		"%s против %s" % [head.global_position, (player as Node as Node3D).global_position])

	# --- 2. Во плоти облик гаснет весь ------------------------------------
	var body := _spawn_body(world, BODY_SCENE, Vector3(7.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame
	_tick(1)
	var body_mesh := E_Body.visual_of_scene(BODY_SCENE).mesh

	_check("захват состоялся", player.has_component(C_Embodied), str(body))
	_check("во плоти сгусток погас", not root.visible, "")
	_check("во плоти клочья у камеры погасли", not wisps.visible and not wisps.emitting, "")
	_check("во плоти след не идёт", trail.all(func(p: GPUParticles3D) -> bool: return not p.emitting), "")
	_check("меш тела надет на слот", slot.mesh == body_mesh, "%s вместо %s" % [slot.mesh, body_mesh])

	# --- 3. Пересадка тело→тело и выход возвращают пустой слот ----------
	var crawler := _spawn_body(world, CRAWLER_SCENE, (player as Node as Node3D).global_position + Vector3(-3.0, 0.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame
	_tick(1)
	_check("пересадка состоялась", player.has_component(C_Embodied) and slot.mesh != body_mesh, str(crawler))
	_check("после пересадки облик по-прежнему погашен", not root.visible, "")

	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame
	_tick(1)
	_check("после выхода слот снова пуст, а не с мешем прошлого тела", slot.mesh == null, str(slot.mesh))
	_check("после выхода сгусток снова виден", root.visible, "")
	_check("после выхода клочья у камеры снова идут", wisps.visible and wisps.emitting, "")
	_check("вышедший сгусток стоит в душе, а не там, где прятался",
		head.global_position.distance_to((player as Node as Node3D).global_position) < 0.01,
		"%s против %s" % [head.global_position, (player as Node as Node3D).global_position])


func _tick(frames: int) -> void:
	for i in frames:
		ECS.process(TICK, "gameplay")


func _particles_under(node: Node) -> Array[GPUParticles3D]:
	var found: Array[GPUParticles3D] = []
	for p in node.find_children("*", "GPUParticles3D", true, false):
		found.append(p as GPUParticles3D)
	return found


func _spawn_body(world: World, path: String, at: Vector3) -> Entity:
	# Entity наследует Node, поэтому до Node3D — через двойной каст, как в S_BodySnatch._embody.
	var body := (load(path) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = at
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	return body


## Возвращает сейв навыков разработчика ровно таким, каким он был до прогона.
func _restore_skill_save() -> void:
	SkillManager.save = _original_skill_save
	if _had_skill_save:
		var file := FileAccess.open(SkillManager.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_skill_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SkillManager.SAVE_PATH))
	_check("сейв навыков разработчика возвращён на место",
		FileAccess.get_file_as_bytes(SkillManager.SAVE_PATH) == _skill_save_backup, "")
