extends Node
## Проверка отмеривания шагов (`S_Footsteps`/`C_Footsteps`).
## Запуск: godot --headless dev/footsteps_check.tscn
##
## Инвариант тихий: шаг, отмеренный не по тому пути, звучит «не в такт», а не
## отмеренный вовсе — не звучит никак; ошибку не бросает ни то, ни другое.
##
## Наблюдаем ЗАПРОС звука, а не воспроизведение: `AudioManager.event_requested`
## шлётся до всякой проверки на загруженный проект byProd, поэтому проверка
## работает без звукового контента, которого в репозитории и нет.
##
## Тело — настоящий `E_Enemy` на настоящем полу, с полной цепочкой S_Gravity →
## S_Movement, как в `world.tscn`: `is_on_floor()` считает только
## `move_and_slide()`, и на синтетической сущности без пола он всегда ложь —
## проверка молча мерила бы пустоту.

const ENEMY_SCENE := "res://src/entities/enemy/e_enemy.tscn"

## Скорость прогона, м/с. Держится постоянной каждый физкадр — ровно так же, как
## её каждый кадр выставляет S_Walk в игре.
const DRIVE_SPEED := 4.0

var _ok := 0
var _fail := 0

## Сколько ещё физкадров прогнать. Считает _physics_process, ставит _physics().
var _pending_ticks := 0
var _driven: C_Velocity = null
var _drive_speed := 0.0

## Пути событий, запрошенных с начала текущего отрезка.
var _requests: Array[String] = []


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	for system in [S_Gravity.new(), S_Movement.new()]:
		system.group = "physics"
		world.add_system(system)

	var footsteps := S_Footsteps.new()
	footsteps.group = "gameplay"
	world.add_system(footsteps)

	AudioManager.event_requested.connect(_on_event_requested)

	await _run(world)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _on_event_requested(event_path: String, _position: Vector3) -> void:
	_requests.append(event_path)


func _run(world: World) -> void:
	add_child(_floor(Vector3.ZERO))

	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Entity
	world.add_entity(enemy)
	await get_tree().process_frame

	var node := enemy as Node as Node3D
	node.global_position = Vector3(0.0, 0.5, 0.0)

	_check(
		"у ходячей сущности есть C_Footsteps — компонент довезён до сцены",
		enemy.has_component(C_Footsteps),
		"без компонента система не увидит сущность вовсе",
	)
	if not enemy.has_component(C_Footsteps):
		return

	var steps := enemy.get_component(C_Footsteps) as C_Footsteps
	steps.event_path = "event:/footstep_test"
	steps.stride = 2.0

	_driven = enemy.get_component(C_Velocity) as C_Velocity

	# Осесть на пол: до касания шаги считаться не должны, и это же проверяется
	# ниже отдельным ассертом про воздух.
	_drive_speed = 0.0
	await _physics(20)

	# --- 1. Ход по земле отмеряет шаги ----------------------------------
	_requests.clear()
	var start_x := node.global_position.x
	_drive_speed = DRIVE_SPEED
	await _physics(60)  # ~1 секунда
	var walked: float = absf(node.global_position.x - start_x)

	_check(
		"идущее по земле тело просит звук шага",
		not _requests.is_empty(),
		"за %.2f м не прозвучало ни шага" % walked,
	)
	_check(
		"событие взято из компонента, а не зашито в систему",
		not _requests.is_empty() and _requests[0] == "event:/footstep_test",
		"пришло «%s»" % ("<пусто>" if _requests.is_empty() else _requests[0]),
	)

	# Стартовый шаг звучит сразу (система взводит счётчик на полный шаг при
	# остановке), дальше — по одному на каждые stride метров пути.
	var expected := 1 + int(walked / steps.stride)
	_check(
		"число шагов отвечает пройденному пути, а не времени",
		absi(_requests.size() - expected) <= 1,
		"прошли %.2f м шагом %.2f — ждали ~%d, получили %d" % [
			walked, steps.stride, expected, _requests.size()],
	)

	# --- 2. Быстрее — чаще -----------------------------------------------
	var slow_count := _requests.size()
	_requests.clear()
	_drive_speed = DRIVE_SPEED * 2.0
	await _physics(60)
	_check(
		"вдвое быстрее — заметно чаще, частота следует скорости",
		_requests.size() > slow_count,
		"на удвоенной скорости шагов %d против %d на обычной" % [_requests.size(), slow_count],
	)

	# --- 3. Стоящий молчит ------------------------------------------------
	_requests.clear()
	_drive_speed = 0.0
	await _physics(60)
	_check("стоя на месте шагов нет", _requests.is_empty(), "шагов: %d" % _requests.size())

	# --- 4. В воздухе молчит ----------------------------------------------
	_requests.clear()
	node.global_position = Vector3(node.global_position.x, 6.0, 0.0)
	_drive_speed = DRIVE_SPEED
	await _physics(10)  # успеть пролететь горизонтально, не долетев до пола
	_check(
		"в воздухе шагов нет, сколько бы ни пролетел",
		_requests.is_empty(),
		"шагов: %d — шаг это касание земли, а не пройденное расстояние" % _requests.size(),
	)

	# --- 5. Без компонента — молча ----------------------------------------
	_drive_speed = 0.0
	await _physics(40)  # приземлиться обратно
	enemy.remove_component(C_Footsteps)
	await get_tree().process_frame

	_requests.clear()
	_drive_speed = DRIVE_SPEED
	await _physics(60)
	_check(
		"сущность без C_Footsteps в выборку не попадает",
		_requests.is_empty(),
		"шагов: %d — молчащее тело всё равно топает" % _requests.size(),
	)


## Гоняет мир из НАСТОЯЩЕГО _physics_process, как main.gd в игре: move_and_slide()
## вне физкадра Jolt считает недостоверно.
func _physics_process(delta: float) -> void:
	if _pending_ticks <= 0:
		return
	_pending_ticks -= 1

	if _driven:
		# Небольшая тяга вниз вместе с горизонталью — иначе move_and_slide() не
		# считает тело «на полу» при чисто горизонтальном движении.
		_driven.velocity = Vector3(_drive_speed, minf(_driven.velocity.y, -1.0), 0.0)

	ECS.process(delta, "physics")
	# Шаги живут в "gameplay" — тикаем той же дельтой, что и физику: прогон не
	# привязан к реальному времени, и «секунда» здесь это ровно 60 таких тиков.
	ECS.process(delta, "gameplay")


func _physics(frames: int) -> void:
	_pending_ticks = frames
	while _pending_ticks > 0:
		await get_tree().physics_frame
	await get_tree().physics_frame  # последнему тику дать долететь


## Плоский пол — верх ровно на y=0.
func _floor(at: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.position = at + Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
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
