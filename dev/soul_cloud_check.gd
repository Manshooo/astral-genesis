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
	world.add_observer(O_SoulExit.new())

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

	# --- 1б. Чем ближе распад, тем призрачнее -----------------------------
	# Кривая — UI_HudMood.decay, та же, что у дуги и свечения: проверяется направление, а не числа.
	var life := player.get_component(C_Lifespan) as C_Lifespan
	var soul_max := life.effective_max(player)
	var states: Array[Dictionary] = []
	for share in [1.0, 0.2, 0.02]:
		life.current = soul_max * share
		_tick(1)
		states.append({
			"head": _decay_of(head),
			"trail": _decay_of(trail[0]),
			"amount": trail[0].amount_ratio,
			"wisps": wisps.amount_ratio,
		})
	var calm: Dictionary = states[0]
	var low: Dictionary = states[1]
	var faint: Dictionary = states[2]
	_check("на спокойном запасе облик не призрачен", calm.head == 0.0 and calm.amount == 1.0 and calm.wisps == 1.0,
		str(calm))
	_check("у порога сгусток и след призрачнее, и чем ближе, тем сильнее",
		0.0 < low.head and low.head < faint.head and 0.0 < low.trail and low.trail < faint.trail,
		"%s → %s" % [low, faint])
	_check("на исходе частиц меньше, но не ноль",
		faint.amount < low.amount and low.amount < 1.0 and faint.amount >= cloud.decay_amount
		and faint.wisps < 1.0 and faint.wisps >= cloud.decay_amount,
		"%s → %s при доле %.2f" % [low, faint, cloud.decay_amount])
	life.current = soul_max

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

	# Душа уходит с разгону: брошенное тело обязано продолжить этот ход по инерции, а не рухнуть на месте.
	var push := Vector3(3.0, 0.0, 0.0)
	(player.get_component(C_Velocity) as C_Velocity).velocity = push
	var left_at := (player as Node as Node3D).global_position
	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame
	_tick(1)
	var fx := _exit_fx(player)
	var husk := fx._husk if fx else null
	_check("выход оставил брошенное тело того, из которого вышли",
		husk != null and husk.scene_file_path == CRAWLER_SCENE, str(husk.scene_file_path if husk else fx))
	_check("брошенное тело не в мире ECS — второй раз его не захватить",
		husk != null and not ECS.world.entities.has(husk as Node as Entity), "")
	_check("брошенное тело ничего не задевает: ни луч захвата, ни игрока",
		husk != null and _layers_of(husk) == 0, "слои %d" % (_layers_of(husk) if husk else -1))
	_check("только вышедший сгусток рваный, а не сразу целый", _decay_of(head) > 0.5, "%.2f" % _decay_of(head))
	_check("после выхода слот снова пуст, а не с мешем прошлого тела", slot.mesh == null, str(slot.mesh))
	_check("после выхода сгусток снова виден", root.visible, "")
	_check("после выхода клочья у камеры снова идут", wisps.visible and wisps.emitting, "")
	_check("вышедший сгусток стоит в душе, а не там, где прятался",
		head.global_position.distance_to((player as Node as Node3D).global_position) < 0.01,
		"%s против %s" % [head.global_position, (player as Node as Node3D).global_position])

	# Брошенное тело летит по ходу души, а за время эффекта испаряется и убирает себя.
	await get_tree().create_timer(0.4).timeout
	var drift := _husk_center(husk) - left_at if is_instance_valid(husk) else Vector3.ZERO
	_check("брошенное тело ушло по инерции в сторону хода души", drift.dot(push.normalized()) > 0.3,
		"сдвиг %s при скорости %s" % [drift, push])
	await get_tree().create_timer(fx.evaporate_seconds * 0.5).timeout
	var burning := _burning_meshes(husk, fx.burn_material)
	_check("брошенное тело сгорает, а не просто бледнеет",
		burning > 0 and burning == husk.find_children("*", "MeshInstance3D", true, false).size(),
		"%d мешей в материале сгорания" % burning)
	var mesh := husk.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var burn := float(mesh.get_instance_shader_parameter(&"burn")) if mesh.get_instance_shader_parameter(&"burn") != null else -1.0
	_check("сгорание идёт, а не стоит на месте", 0.0 < burn and burn < 1.0, "%.2f" % burn)
	_tick(int(ceil(cloud.unfold_seconds / TICK)) + 1)
	_check("сгусток развернулся и снова по запасу", _decay_of(head) == 0.0, "%.2f" % _decay_of(head))
	await get_tree().create_timer(fx.fall_seconds + fx.evaporate_seconds + fx.linger_seconds).timeout
	_check("брошенное тело испарилось", not is_instance_valid(husk), "")
	_check("эффект выхода убрал себя сам", not is_instance_valid(fx), "")


## Распад, отданный облику; −1 — не отдан вовсе (параметр экземпляра не выставлен).
func _decay_of(node: GeometryInstance3D) -> float:
	var value: Variant = node.get_instance_shader_parameter(&"decay")
	return float(value) if value != null else -1.0


func _exit_fx(player: Entity) -> SoulExitFx:
	for node in (player as Node).get_parent().get_children():
		if node is SoulExitFx:
			return node as SoulExitFx
	return null


## Сумма слоёв коллизий всех тел оболочки: 0 — ничто в ней ни с чем не сталкивается как цель.
func _layers_of(husk: Node) -> int:
	var total := 0
	for node in [husk] + husk.find_children("*", "CollisionObject3D", true, false):
		if node is CollisionObject3D:
			total |= (node as CollisionObject3D).collision_layer
	return total


## Сколько мешей тела носят на всех поверхностях материал с шейдером сгорания.
func _burning_meshes(husk: Node, burn: ShaderMaterial) -> int:
	var count := 0
	for node in husk.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var all := mesh.mesh != null and mesh.mesh.get_surface_count() > 0
		for surface in (mesh.mesh.get_surface_count() if mesh.mesh else 0):
			var active := mesh.get_active_material(surface) as ShaderMaterial
			all = all and active != null and active.shader == burn.shader
		if all:
			count += 1
	return count


## Где сейчас тело: по костям рэгдолла, без них — по корню.
func _husk_center(husk: Node3D) -> Vector3:
	var bones := husk.find_children("*", "PhysicalBone3D", true, false)
	if bones.is_empty():
		return husk.global_position
	var sum := Vector3.ZERO
	for bone in bones:
		sum += (bone as Node3D).global_position
	return sum / bones.size()


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
