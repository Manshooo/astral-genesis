extends Node
## Проверка перешагивания порогов (S_Movement.STEP_HEIGHT): CharacterBody3D
## обязан закатываться на геометрию ниже STEP_HEIGHT без прыжка (дверные
## пороги, кромки ступенек комнатной геометрии — живой прогон нашёл, что без
## этого их приходится перепрыгивать), но настоящая стена выше STEP_HEIGHT
## обязана остановить как и раньше — новый манёвр не должен занизить это. И
## отдельно — что упор в настоящую стену не «съедает» прыжок следующим кадром
## (второй баг, найденный тем же живым прогоном, см. §3 ниже).
## Запускать: godot --headless dev/movement_check.tscn
##
## Порог в §1 взят 0.15 м, а не что-то заведомо маленькое, НАРОЧНО: голый
## move_and_slide() и без правки уже перекатывает капсулу (радиус 0.4 м) через
## препятствия примерно до 0.12–0.13 м просто своей формой — правка
## S_Movement нужна ровно на последних сантиметрах до STEP_HEIGHT. Высота
## пониже проверяла бы совпадение, а не саму правку.

const ENEMY_SCENE := "res://src/entities/enemy/e_enemy.tscn"
const STATIC_COLLIDERS_LAYER := 1

var _ok := 0
var _fail := 0

## Сколько ещё физкадров прогнать. Считает _physics_process, ставит _physics().
var _pending_ticks := 0
## Кого и куда толкать эти кадры — C_Velocity выставляется НАПРЯМУЮ каждый
## физкадр (S_Walk в проверке не участвует), как это делал бы любой мотор.
var _driven: C_Velocity = null
var _driven_node: Node3D = null
var _drive_dir := Vector3.ZERO
## Наибольшая высота, замеченная за время толкания — порог узкий (0.3 м), и к
## финальному кадру тело успевает сойти обратно на пол за ним; «поднимался ли
## вообще» ловим по максимуму, а не по срезу в конце.
var _max_y_seen := -INF


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	var movement := S_Movement.new()
	movement.group = "physics"
	world.add_system(movement)

	await _run(world)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World) -> void:
	# --- 1. Порог ниже STEP_HEIGHT — не стена, закатываемся -----------------
	add_child(_floor(Vector3(0.0, 0.0, 0.0)))
	add_child(_obstacle(Vector3(2.0, 0.0, 0.0), 0.15))

	var walker := _spawn(world, Vector3(0.0, 0.02, 0.0))
	var start_x := (walker as Node as Node3D).global_position.x
	var max_y := await _walk(walker, Vector3(4.0, 0.0, 0.0), 90)
	var end_pos := (walker as Node as Node3D).global_position

	_check(
		"порог 0.15 м (ниже STEP_HEIGHT) не стена — прошли мимо его X",
		end_pos.x > 3.0,
		"старт x=%.2f, финиш %s" % [start_x, end_pos]
	)
	_check(
		"на пороге 0.15 м тело реально поднималось на его высоту, а не телепортировалось сквозь",
		max_y > 0.10,
		"максимум y=%.3f за проход (ожидали >0.10, потолок — высота порога 0.15)" % max_y
	)

	# --- 2. Настоящая стена выше STEP_HEIGHT всё ещё стена -------------------
	# Тот же пол из §1 покрывает и эту зону (20×20 м) — второй не нужен.
	add_child(_obstacle(Vector3(2.0, 0.0, 6.0), 0.5))

	var walker2 := _spawn(world, Vector3(0.0, 0.02, 6.0))
	await _walk(walker2, Vector3(4.0, 0.0, 0.0), 90)
	var blocked_pos := (walker2 as Node as Node3D).global_position

	_check(
		"стена 0.5 м всё ещё останавливает — до неё, не сквозь и не поверх",
		blocked_pos.x < 1.9,
		"x=%.3f" % blocked_pos.x
	)
	_check(
		"перед стеной тело осталось на полу, не «влезло» на неё",
		blocked_pos.y < 0.2,
		"y=%.3f" % blocked_pos.y
	)

	# --- 3. Стена не должна «съедать» прыжок ---------------------------------
	# Живой прогон нашёл: упёршись в стену, иногда не получалось прыгнуть.
	# Причина — в _try_step() из §1/§2: когда манёвр срабатывает вхолостую
	# (стена реальная, не ступенька), он оставляет is_on_floor() лживым до
	# конца кадра (см. комментарий в самом S_Movement). S_Jump это состояние
	# читает и молча отказывает, хотя тело физически стоит на земле.
	await _check_jump_against_wall()


## Отдельный мир и полный набор систем движения (S_Gravity/S_Walk/S_Jump/
## S_Movement — как в world.tscn), а не только S_Movement из §1/§2: баг живёт
## на стыке S_Jump.is_on_floor() и остаточного состояния после S_Movement, и
## воспроизвести его можно только всей цепочкой разом.
func _check_jump_against_wall() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	for system in [S_Gravity.new(), S_Walk.new(), S_Jump.new(), S_Movement.new()]:
		system.group = "physics"
		world.add_system(system)

	var player := (load("res://src/entities/player/e_player.tscn") as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame

	# Призрак по умолчанию летает (C_Flight) и не ходит — для этой проверки
	# нужно тело на земле. Вне прохода систем добавлять/снимать компоненты
	# напрямую безопасно (правило v9 касается только process()).
	if player.has_component(C_Flight):
		player.remove_component(player.get_component(C_Flight))
	player.add_component(C_Walk.new())
	player.add_component(C_Jump.new())

	add_child(_floor(Vector3(0.0, 0.0, 12.0)))
	add_child(_obstacle(Vector3(2.0, 0.0, 12.0), 1.0))  # настоящая стена

	(player as Node as Node3D).global_position = Vector3(0.0, 0.5, 12.0)
	await get_tree().physics_frame

	var inp := player.get_component(C_PlayerInput) as C_PlayerInput
	var vel := player.get_component(C_Velocity) as C_Velocity

	# Базис рига единичный (не поворачивался) — Vector3.RIGHT в местных
	# координатах и есть мировой +X, тот же, что использует _obstacle() выше.
	inp.move_direction = Vector3.RIGHT
	await _physics(30)  # осесть на пол и упереться в стену на несколько кадров

	inp.jump_pressed = true
	await _physics(1)

	_check(
		"прыжок у стены срабатывает — is_on_floor() не врёт после step-манёвра",
		vel.velocity.y > 0.0,
		"velocity.y=%.3f (ожидали положительную — толчок прыжка)" % vel.velocity.y
	)


func _spawn(world: World, at: Vector3) -> Entity:
	var body := (load(ENEMY_SCENE) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = at
	world.add_entity(body)
	return body


## Толкает [param body] с постоянной горизонтальной скоростью [param dir] через
## S_Movement [param frames] физкадров подряд. Возвращает наибольшую высоту,
## которую тело занимало за это время (см. _max_y_seen).
func _walk(body: Entity, dir: Vector3, frames: int) -> float:
	_driven = body.get_component(C_Velocity) as C_Velocity
	_driven_node = body as Node as Node3D
	_drive_dir = dir
	_max_y_seen = _driven_node.global_position.y
	await _physics(frames)
	_driven = null
	_driven_node = null
	return _max_y_seen


## Гоняет мир из НАСТОЯЩЕГО _physics_process, как main.gd в игре: move_and_slide()
## недоступен из корутины по physics_frame (Jolt крутится на отдельном потоке,
## см. [[GECS и правила движка]]).
func _physics_process(delta: float) -> void:
	if _pending_ticks <= 0:
		return
	_pending_ticks -= 1
	if _driven:
		# Небольшая тяга вниз — иначе move_and_slide() не считает тело «на
		# полу» при чисто горизонтальном движении, а без этого S_Movement не
		# пробует перешагивание вовсе (см. was_on_floor в его process()).
		_driven.velocity = Vector3(_drive_dir.x, -1.0, _drive_dir.z)
	ECS.process(delta, "physics")
	if _driven_node:
		_max_y_seen = maxf(_max_y_seen, _driven_node.global_position.y)


func _physics(frames: int) -> void:
	_pending_ticks = frames
	while _pending_ticks > 0:
		await get_tree().physics_frame
	await get_tree().physics_frame  # последнему тику дать долететь


## Плоский пол под сценой — верх ровно на y=0.
func _floor(at: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.collision_layer = STATIC_COLLIDERS_LAYER
	node.position = at + Vector3(0.0, -2.0, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 4.0, 20.0)
	shape.shape = box
	node.add_child(shape)
	return node


## Препятствие заданной высоты, стоящее на полу (низ на y=0, верх на height).
func _obstacle(at: Vector3, height: float) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.collision_layer = STATIC_COLLIDERS_LAYER
	node.position = at + Vector3(0.0, height * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, height, 4.0)
	shape.shape = box
	node.add_child(shape)
	return node


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
