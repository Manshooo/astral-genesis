extends "res://dev/check_harness.gd"
## Проверка боя: удар тела (C_Attack + S_Attack), здоровье и смерть врага
## (O_EnemyDeath) и «враг — живая версия тела».
##
## Проверяет ПОВЕДЕНИЕ, а не форму сцен: тело с ударом наносит урон врагу и
## убивает его; на месте врага встаёт тело нужной сцены с полным здоровьем, в
## которое можно вселиться, и удар переезжает вместе с телом; тело без удара
## получает отклик, призрак — молчаливый отказ, и урона нет ни там, ни там;
## стена не пропускает удар; мёртвый враг не бьёт; труп не бьют; труп уходит
## вместе с комнатой, не оставляя в мире битых ссылок.
## Запускать: godot --headless dev/combat_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const WALKER_SCENE := "res://src/entities/body/e_body_walker.tscn"
const CRAWLER_SCENE := "res://src/entities/body/e_body_crawler.tscn"
const SCIENTIST_ENEMY := "res://src/entities/enemy/e_enemy_scientist.tscn"
const SOLDIER_ENEMY := "res://src/entities/enemy/e_enemy_soldier.tscn"
const HOUND_ENEMY := "res://src/entities/enemy/e_enemy_hound.tscn"
const SCIENTIST_BODY := "res://src/entities/body/e_body_scientist.tscn"
const SOLDIER_BODY := "res://src/entities/body/e_body_soldier.tscn"
const HOUND_BODY := "res://src/entities/body/e_body_hound.tscn"

## Слои физики (project.godot [layer_names]).
const STATIC_LAYER := 1 << 0

var _world: World
var _room: Node3D


func _ready() -> void:
	_world = _new_world()
	_add_systems(_world, "physics", [
		S_BodySnatch.new(), S_Phasing.new(), S_Gravity.new(), S_EnemyAI.new(),
		S_Walk.new(), S_Jump.new(), S_Flight.new(), S_Movement.new(), S_Attack.new(),
	])
	_add_systems(_world, "gameplay", [S_Health.new(), S_ScreenMessage.new()])
	_world.add_observer(O_ExpelFromBody.new())
	_world.add_observer(O_EnemyDeath.new())
	_world.add_observer(O_BodyVisual.new())
	_world.add_observer(O_BodyForm.new())
	_world.add_observer(O_SoulTraits.new())

	_add_floor()
	await _run()
	_finish()


## Пол: без него враги, трупы и сам игрок падают под гравитацией в пустоту.
func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = STATIC_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)


func _run() -> void:
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)

	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	_world.add_entity(player)
	(player as Node as Node3D).global_position = Vector3(0.0, 1.0, 0.0)
	await _physics(3)
	var inp := player.get_component(C_PlayerInput) as C_PlayerInput

	# Враг на расстоянии удара, но с выключенным ИИ: аггро 0 — стоит и не бьёт в
	# ответ, чтобы урон по игроку не мешал считать урон по врагу.
	var scientist := await _spawn_enemy(SCIENTIST_ENEMY, Vector3(0.0, 0.05, -1.5), false)
	var health := scientist.get_component(C_Health) as C_Health
	_check("у врага есть прочность", health != null and health.current > 0.0, "")
	var full := health.current

	# --- 1. Призрак бить не умеет: защёлка съедена, ни сообщения, ни урона ------
	inp.attack_pressed = true
	await _physics(2)
	_check("призрак: нажатие удара съедено", not inp.attack_pressed, "")
	_check("призрак: урона нет", is_equal_approx(health.current, full), "%.1f" % health.current)
	_check("призраку про «нечем бить» не сообщают", player.get_component(C_ScreenMessage) == null, "")

	# --- 2. Во плоти с ударом: тело отдаёт C_Attack душе ------------------------
	var body := _spawn_body(WALKER_SCENE, Vector3(0.0, 0.0, 0.0))
	await _physics(2)
	await _capture(player)
	var attack := player.get_component(C_Attack) as C_Attack
	_check("захват перенёс удар на душу", attack != null, "")
	if attack == null:
		return
	var walker_damage := attack.damage
	await _physics(3)  # осесть на пол после посадки
	(player as Node as Node3D).global_position.x = 0.0
	(player as Node as Node3D).global_position.z = 0.0
	await _physics(2)

	# --- 3. Удар в упор наносит урон, кулдаун держит ----------------------------
	await _strike(player, inp)
	_check(
		"удар снял ровно урон тела",
		is_equal_approx(health.current, full - walker_damage),
		"%.1f -> %.1f (ждали -%.1f)" % [full, health.current, walker_damage]
	)
	_check("удар оставил отклик попадания", player.get_component(C_ScreenMessage) != null, "")
	var after_first := health.current
	inp.attack_pressed = true
	await _physics(2)
	_check("кулдаун: повторный удар сразу не проходит", is_equal_approx(health.current, after_first), "%.1f" % health.current)
	attack.cooldown_left = 0.0
	await _strike(player, inp)
	_check("после паузы удар снова проходит", health.current < after_first, "%.1f" % health.current)

	# --- 4. Дальность и стена ---------------------------------------------------
	(scientist as Node as Node3D).global_position = Vector3(0.0, 0.05, -(attack.reach + 2.0))
	await _physics(3)
	var before := health.current
	attack.cooldown_left = 0.0  # иначе мимо могла увести пауза, а не дальность
	await _strike(player, inp)
	_check("враг дальше reach — удар мимо", is_equal_approx(health.current, before), "%.1f" % health.current)

	(scientist as Node as Node3D).global_position = Vector3(0.0, 0.05, -1.5)
	var wall := _add_wall(Vector3(0.0, 1.0, -0.9))
	await _physics(3)
	attack.cooldown_left = 0.0
	await _strike(player, inp)
	_check("стена между игроком и врагом гасит удар", is_equal_approx(health.current, before), "%.1f" % health.current)
	wall.free()
	await _physics(2)
	# Контроль: без стены тот же удар проходит — значит, мимо его увела именно она.
	attack.cooldown_left = 0.0
	await _strike(player, inp)
	_check("контроль: убрали стену — удар проходит", health.current < before, "%.1f" % health.current)

	# --- 5. Мёртвый враг не бьёт ----------------------------------------------
	var dead := await _spawn_enemy(SCIENTIST_ENEMY, Vector3(6.0, 0.05, 6.0), true)
	var player_health := player.get_component(C_Health) as C_Health
	(player as Node as Node3D).global_position = Vector3(6.0, 1.0, 4.5)
	await _physics(3)
	# Контроль: живой враг в той же позиции бьёт — иначе «мёртвый не бьёт» могло
	# пройти просто оттого, что бить было некому.
	var dead_ai := dead.get_component(C_EnemyAI) as C_EnemyAI
	dead_ai.attack_cooldown_left = 0.0
	var control_before := player_health.current
	await _physics(2)
	_check("контроль: живой враг в упор бьёт", player_health.current < control_before, "%.1f" % player_health.current)

	dead.add_component(C_Dead.new())
	dead_ai.attack_cooldown_left = 0.0
	var hp_before := player_health.current
	await _physics(4)
	_check("враг с C_Dead не бьёт", is_equal_approx(player_health.current, hp_before), "%.1f -> %.1f" % [hp_before, player_health.current])
	_world.remove_entity(dead)
	(player as Node as Node3D).global_position = Vector3(0.0, 1.0, 0.0)
	await _physics(3)

	# --- 6. Убитый враг → тело нужной сцены, полное здоровье, захватываемое ------
	attack.cooldown_left = 0.0
	health.current = 1.0
	await _strike(player, inp)
	await get_tree().process_frame  # подмена трупом отложена (Правило v9)
	await _physics(2)
	_check("убитый враг убран из мира", not is_instance_valid(scientist) or scientist.is_queued_for_deletion(), "")
	var corpse := _find_body(SCIENTIST_BODY)
	_check("на месте врага встало тело учёного", corpse != null, "")
	if corpse == null:
		return
	var corpse_health := corpse.get_component(C_Health) as C_Health
	_check(
		"у трупа свежее полное здоровье",
		corpse_health != null and is_equal_approx(corpse_health.current, corpse_health.maximum) and corpse_health.current > 1.0,
		""
	)
	_check("труп захватываем", corpse.has_component(C_BodySnatchable), "")
	_check("труп стоит под той же комнатой, что был враг", corpse.get_parent() == _room, str(corpse.get_parent()))
	_check(
		"труп встал на место врага",
		(corpse as Node as Node3D).global_position.distance_to(Vector3(0.0, 0.05, -1.5)) < 0.5,
		str((corpse as Node as Node3D).global_position)
	)

	# --- 7. Трупы не бьют ------------------------------------------------------
	var corpse_before := corpse_health.current
	attack.cooldown_left = 0.0
	await _strike(player, inp)
	_check("удар по трупу не проходит — в него вселяются, его не бьют", is_equal_approx(corpse_health.current, corpse_before), "")

	# --- 8. Вселение в труп переносит его числа удара --------------------------
	corpse.add_component(C_SnatchTargeted.new())
	await _capture(player)
	var scene_path := (player.get_component(C_Embodied) as C_Embodied).body_scene_path if player.has_component(C_Embodied) else ""
	_check("вселились в труп врага", scene_path == SCIENTIST_BODY, scene_path)
	var scientist_attack := player.get_component(C_Attack) as C_Attack
	_check(
		"в теле учёного свой, более слабый удар",
		scientist_attack != null and scientist_attack.damage < walker_damage,
		"%s vs %.1f" % [str(scientist_attack.damage) if scientist_attack else "нет", walker_damage]
	)

	# --- 9. Тело без удара: отклик «нечем», урона нет --------------------------
	var target := await _spawn_enemy(SCIENTIST_ENEMY, Vector3(0.0, 0.05, -1.5), false)
	var target_health := target.get_component(C_Health) as C_Health
	var target_full := target_health.current
	player.remove_component(player.get_component(C_Attack))
	if player.has_component(C_ScreenMessage):
		player.remove_component(player.get_component(C_ScreenMessage))
	await _physics(2)
	inp.attack_pressed = true
	await _physics(2)
	await get_tree().process_frame
	var message := player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check("тело без C_Attack: отклик «нечем бить»", message != null and message.text == "HUD_MSG_NO_ATTACK", message.text if message else "нет")
	_check("тело без C_Attack: урона нет", is_equal_approx(target_health.current, target_full), "")
	_check("нажатие съедено", not inp.attack_pressed, "")

	# --- 10. Варианты врагов: свой труп, полное здоровье ------------------------
	for case in [[SOLDIER_ENEMY, SOLDIER_BODY], [HOUND_ENEMY, HOUND_BODY]]:
		var enemy := await _spawn_enemy(case[0], Vector3(12.0, 0.05, 12.0), false)
		S_Health.deal_damage(enemy, 10000.0, null, &"test")
		await _physics(2)
		await get_tree().process_frame
		await _physics(2)
		var made := _find_body(case[1])
		_check("враг %s оставил тело %s" % [case[0].get_file(), case[1].get_file()], made != null, "")
		if made != null:
			var h := made.get_component(C_Health) as C_Health
			_check("  и оно с полным здоровьем", h != null and is_equal_approx(h.current, h.maximum), "")
			_check("  и с ударом в наборе", made.has_component(C_Attack) or _scene_has_attack(case[1]), "")
			_world.remove_entity(made)

	# --- 11. Комната ушла — труп ушёл из мира без битых ссылок ------------------
	var leaving := Node3D.new()
	leaving.name = "LeavingRoom"
	add_child(leaving)
	var doomed := (load(SCIENTIST_ENEMY) as PackedScene).instantiate() as E_Enemy
	leaving.add_child(doomed)
	(doomed as Node as Node3D).position = Vector3(-12.0, 0.05, -12.0)
	_world.add_entity(doomed)
	await _physics(2)
	S_Health.deal_damage(doomed, 10000.0, null, &"test")
	await _physics(2)
	await get_tree().process_frame
	_check("под уходящей комнатой появился труп", leaving.get_child_count() > 0 and _count_bodies_under(leaving) == 1, str(leaving.get_children()))
	leaving.free()
	await _physics(2)
	var stale := 0
	for entity in _world.entities:
		if not is_instance_valid(entity):
			stale += 1
	_check("после ухода комнаты в мире нет битых сущностей", stale == 0, "битых: %d" % stale)


func _spawn_enemy(path: String, at: Vector3, aggressive: bool) -> Entity:
	var enemy := (load(path) as PackedScene).instantiate() as E_Enemy
	_room.add_child(enemy)
	(enemy as Node as Node3D).global_position = at
	_world.add_entity(enemy)
	if not aggressive:
		(enemy.get_component(C_EnemyAI) as C_EnemyAI).aggro_range = 0.0
	await _physics(3)
	return enemy


func _spawn_body(path: String, at: Vector3) -> Entity:
	var body := (load(path) as PackedScene).instantiate() as Entity
	_room.add_child(body)
	(body as Node as Node3D).global_position = at
	_world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	return body


## Стена на слое static_colliders — перекрывает луч удара, но не врага.
func _add_wall(at: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = STATIC_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = at
	return wall


func _capture(player: E_Player) -> void:
	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	await _physics(2)
	await get_tree().process_frame
	await _physics(2)


func _strike(player: E_Player, inp: C_PlayerInput) -> void:
	inp.attack_pressed = true
	await _physics(2)
	await get_tree().process_frame


func _find_body(scene_path: String) -> Entity:
	for entity in _world.entities:
		if is_instance_valid(entity) and entity is E_Body and (entity as Node).scene_file_path == scene_path:
			return entity
	return null


func _count_bodies_under(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is E_Body:
			count += 1
	return count


func _scene_has_attack(path: String) -> bool:
	for component in E_Body.traits_of_scene(path):
		if component is C_Attack:
			return true
	return false


func _on_physics_tick(delta: float) -> void:
	ECS.process(delta, "physics")
	ECS.process(delta, "gameplay")
