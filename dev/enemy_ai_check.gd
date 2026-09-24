extends "res://dev/check_harness.gd"
## Проверка простого поведения врага (S_EnemyAI): вне радиуса аггро стоит, в
## радиусе — реально идёт (тот самый CharacterBody3D, а не StaticBody3D, как у
## E_Body — иначе S_Walk/S_Movement его не двигают), в упор бьёт с кулдауном
## (не каждый кадр), бестелесную душу не замечает вовсе, а «тело забрал враг»
## не тупик — уже отлаженный O_ExpelFromBody выбрасывает игрока обратно в
## призрака. Плюс регресс-проверка на баг, найденный живым прогоном: враг
## обязан ходить через C_EnemyInput, а НЕ C_PlayerInput — второй такой
## компонент в мире ломает добрый десяток мест (RunManager.travel_to,
## S_InteractionDetector, HUD), которые находят «игрока» просто по наличию
## C_PlayerInput. Запускать: godot --headless dev/enemy_ai_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const WALKER_SCENE := "res://src/entities/body/e_body_walker.tscn"
const ENEMY_SCENE := "res://src/entities/enemy/e_enemy.tscn"

## Биты слоёв физики (project.godot [layer_names]).
const STATIC_LAYER := 1 << 0
const PLAYER_LAYER := 1 << 1
const ENEMIES_LAYER := 1 << 2
const MOVING_LAYER := 1 << 4


func _ready() -> void:
	var world := _new_world()

	# Полный набор систем группы "physics", как в world.tscn: захват нужен,
	# чтобы у игрока появился C_Health (враг реагирует только на воплощённого).
	_add_systems(world, "physics", [
		S_BodySnatch.new(), S_Phasing.new(), S_Gravity.new(),
		S_EnemyAI.new(), S_Walk.new(), S_Jump.new(), S_Flight.new(), S_Movement.new(),
	])
	_add_systems(world, "gameplay", [S_Health.new()])

	world.add_observer(O_ExpelFromBody.new())
	world.add_observer(O_BodyVisual.new())
	world.add_observer(O_BodyForm.new())
	world.add_observer(O_SoulTraits.new())

	await _run(world)

	_finish()


func _run(world: World) -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame

	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as E_Enemy
	world.add_entity(enemy)
	await get_tree().process_frame

	var ai := enemy.get_component(C_EnemyAI) as C_EnemyAI
	var enemy_node := enemy as Node as Node3D
	var player_node := player as Node as Node3D

	# --- 0. Регресс: враг не должен маскироваться под игрока -----------------
	# Ровно тот баг, который живой прогон нашёл в S_Walk/RunManager.travel_to/
	# S_InteractionDetector/HUD: все они находят «игрока» запросом «у кого есть
	# C_PlayerInput» без уточнения C_BodySnatch. Если бы враг тоже нёс
	# C_PlayerInput, execute_one() мог бы вернуть его вместо настоящего игрока.
	_check(
		"у врага нет C_PlayerInput — он не может подменить игрока в чужих запросах",
		not enemy.has_component(C_PlayerInput),
		""
	)
	_check(
		"запрос «у кого есть C_PlayerInput» находит настоящего игрока, а не врага",
		ECS.world.query.with_all([C_PlayerInput]).execute_one() == player,
		""
	)

	await _check_layers(world, player, enemy)

	# --- 1. Бестелесная душа врага не интересует, даже вплотную -------------
	# Цель ищется по C_Embodied + C_Health — у свежей души их нет, и дистанция
	# тут вообще не должна считаться.
	player_node.position = enemy_node.global_position + Vector3(1.0, 0.0, 0.0)
	await _physics(5)
	_check(
		"призрак вплотную не будит врага — цели без C_Health не существует",
		ai.state == C_EnemyAI.State.IDLE,
		"state=%s" % ai.state
	)

	# --- 2. Захват тела делает игрока целью ----------------------------------
	var walker := _spawn_body(world, WALKER_SCENE, Vector3(20.0, 0.0, 20.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	await _physics(1)
	await get_tree().process_frame
	_check("захват состоялся — теперь есть кого атаковать", player.has_component(C_Embodied), str(walker))

	# --- 3. Вне aggro_range — стоим, физически не сдвигаясь ------------------
	player_node.position = enemy_node.global_position + Vector3(0.0, 0.0, ai.aggro_range + 5.0)
	await _physics(5)
	var enemy_inp := enemy.get_component(C_EnemyInput) as C_EnemyInput
	_check(
		"игрок за пределами aggro_range — враг стоит",
		ai.state == C_EnemyAI.State.IDLE and enemy_inp.move_direction == Vector3.ZERO,
		"state=%s move_direction=%s" % [ai.state, enemy_inp.move_direction]
	)
	var idle_before := enemy_node.global_position
	await _physics(10)
	_check(
		"вне аггро враг не сдвинулся по горизонтали (свободное падение под гравитацией не в счёт)",
		Vector2(idle_before.x, idle_before.z).distance_to(
			Vector2(enemy_node.global_position.x, enemy_node.global_position.z)
		) < 0.01,
		"было %s, стало %s" % [idle_before, enemy_node.global_position]
	)

	# --- 4. В радиусе аггро, вне атаки — разворачивается и реально идёт -----
	var chase_distance := (ai.aggro_range + ai.attack_range) * 0.5
	player_node.position = enemy_node.global_position + Vector3(0.0, 0.0, chase_distance)
	var dist_start := _xz_distance(enemy_node, player_node)
	await _physics(30)
	_check(
		"игрок в радиусе аггро — враг переходит в погоню",
		ai.state == C_EnemyAI.State.CHASING,
		"state=%s" % ai.state
	)
	var dist_after := _xz_distance(enemy_node, player_node)
	_check(
		"погоня реально сокращает дистанцию — CharacterBody3D действительно ходит",
		dist_after < dist_start - 0.1,
		"было %.2f м, стало %.2f м" % [dist_start, dist_after]
	)

	# --- 5. В упор — бьёт с кулдауном, а не каждый кадр ----------------------
	var health := player.get_component(C_Health) as C_Health
	health.current = health.effective_maximum(player)
	player_node.position = enemy_node.global_position + Vector3(ai.attack_range * 0.5, 0.0, 0.0)
	ai.attack_cooldown_left = 0.0
	await _physics(1)
	var health_after_first_hit := health.current
	_check(
		"первый удар в упор снял ровно attack_damage",
		is_equal_approx(health_after_first_hit, health.effective_maximum(player) - ai.attack_damage),
		"%.2f" % health_after_first_hit
	)
	await _physics(5)  # 5 физкадров — заведомо меньше attack_interval (1 с)
	_check(
		"кулдаун держит — второго удара за пять кадров не случилось",
		is_equal_approx(health.current, health_after_first_hit),
		"%.2f -> %.2f" % [health_after_first_hit, health.current]
	)

	# --- 6. Тело добито — игрока выбрасывает обратно в призрака --------------
	# Урон наносит только S_EnemyAI (health.current -= attack_damage), а
	# объявление смерти и развоплощение — уже отлаженный путь (S_Health +
	# O_ExpelFromBody); здесь проверяем, что враг корректно встраивается в
	# начало этой цепочки, а не что цепочка сама работает.
	health.current = ai.attack_damage * 0.5  # следующий удар точно добьёт
	ai.attack_cooldown_left = 0.0
	await _physics(1)
	await get_tree().process_frame  # O_ExpelFromBody вызван через call_deferred
	_check(
		"тело добито врагом — игрока выбросило обратно в призрака",
		not player.has_component(C_Embodied),
		"C_Embodied всё ещё висит" if player.has_component(C_Embodied) else ""
	)
	_check(
		"развоплощение вернуло возможности души — призрак не застрял мёртвым телом",
		player.has_component(C_Flight),
		""
	)


## Слои коллизий игрока и врага (см. [[Конвенции проекта]], §2). Всё здесь
## ломается молча: игрок на static_colliders — стена для всякой маски «по
## геометрии», враг на moving_colliders — подвижная геометрия для всех, кому нужны
## двери, а маска без permeable пропускает врага сквозь решётки.
func _check_layers(world: World, player: E_Player, enemy: E_Enemy) -> void:
	var player_body := player as Node as CharacterBody3D
	var enemy_body := enemy as Node as CharacterBody3D
	_check(
		"игрок на слое player — не на static_colliders, где он был бы стеной",
		player_body.collision_layer == PLAYER_LAYER,
		"layer=%d" % player_body.collision_layer
	)
	_check(
		"враг на слое enemies — не на moving_colliders, слое подвижной геометрии",
		enemy_body.collision_layer == ENEMIES_LAYER,
		"layer=%d" % enemy_body.collision_layer
	)
	var enemy_solid := STATIC_LAYER | PLAYER_LAYER | MOVING_LAYER | C_Phasing.PERMEABLE_BIT
	_check(
		"враг упирается в стены, в игрока, в подвижную и в проницаемую геометрию",
		enemy_body.collision_mask & enemy_solid == enemy_solid,
		"mask=%d" % enemy_body.collision_mask
	)
	# Проницаемый бит у игрока ведёт S_Phasing (призрак — без него, во плоти — с
	# ним), здесь он не сверяется. А тела-цели захвата на слое enemies игроку не
	# преграда: у тела-рэгдолла корневая капсула стоит там, где труп стоял до
	# падения, и была бы невидимым столбом посреди комнаты.
	_check(
		"игрок упирается в стены и в подвижную геометрию, но не в слой enemies",
		(
			player_body.collision_mask & (STATIC_LAYER | MOVING_LAYER) == STATIC_LAYER | MOVING_LAYER
			and player_body.collision_mask & ENEMIES_LAYER == 0
		),
		"mask=%d" % player_body.collision_mask
	)

	# Враг на слое enemies попадает под луч захвата — и обязан не заслонять тело
	# у себя за спиной: ради этого он раньше и жил на чужом слое.
	var cam := player.camera
	var forward := -cam.global_transform.basis.z
	var enemy_node := enemy as Node as Node3D
	var enemy_home := enemy_node.global_position
	enemy_node.global_position = cam.global_position + forward * 1.5 - Vector3.UP * 0.9
	var shielded := (load(WALKER_SCENE) as PackedScene).instantiate() as Entity
	(shielded as Node as Node3D).position = cam.global_position + forward * 3.0 - Vector3.UP * 0.9
	world.add_entity(shielded)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var detector := S_SnatchTargetDetector.new()
	var seen: Entity = detector._raycast_body(cam, 5.0)
	detector.free()
	_check(
		"тело за спиной врага остаётся в прицеле захвата — луч проходит врага насквозь",
		seen == shielded,
		"в прицеле %s" % (seen.name if seen else "ничего")
	)
	world.remove_entity(shielded)
	enemy_node.global_position = enemy_home
	await get_tree().physics_frame


func _xz_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x, a.global_position.z).distance_to(
		Vector2(b.global_position.x, b.global_position.z)
	)


func _spawn_body(world: World, path: String, at: Vector3) -> Entity:
	# Entity наследует Node, поэтому до Node3D — через двойной каст.
	var body := (load(path) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = at
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	return body


## Тем же тактом дёргает группу "gameplay" — S_Health в ней должен успеть
## отработать до следующей проверки, а на реальный кадровый _process в
## headless-прогоне полагаться нельзя.
func _on_physics_tick(delta: float) -> void:
	ECS.process(delta, "physics")
	ECS.process(delta, "gameplay")
