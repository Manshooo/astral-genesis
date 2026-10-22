extends "res://dev/check_harness.gd"
## Проверка сигналов двери в её звуковое событие (`S_DoorMotion` → `C_DoorMotion.sound`).
## Запуск: godot --headless dev/door_sound_check.tscn
##
## Инвариант тихий: событие двери держит петлю привода, пока не придёт сигнал конца
## хода, и пропущенный door_stopped звучит мотором, который не глохнет, — ошибки нет.
##
## Событие подменено записывающим объектом: S_DoorMotion заводит инстанс, только если
## поле пусто, и дальше лишь шлёт в него сигналы. Так проверка не зависит ни от
## рантайма byProd, ни от собранного проекта звука, которых в репозитории нет.

const DOOR_SCENES := [
	"res://src/entities/door/complex_door.tscn",
	"res://src/entities/door/double_door.tscn",
]


## Записывает сигналы вместо ByProdEventInstance.
class _SignalRecorder:
	extends RefCounted

	var signals: Array[String] = []

	func send_signal(signal_name: String) -> void:
		signals.append(signal_name)


func _ready() -> void:
	var world := _new_world()
	_add_systems(world, "physics", [S_DoorMotion.new()])

	for path: String in DOOR_SCENES:
		await _run(world, path)

	_finish()


func _run(world: World, path: String) -> void:
	var door := (load(path) as PackedScene).instantiate() as Entity
	world.add_entity(door)
	await get_tree().process_frame

	var name := path.get_file()
	var motion := door.get_component(C_DoorMotion) as C_DoorMotion
	_check("%s: у двери есть C_DoorMotion" % name, motion != null, "без него звук двери не заводится вовсе")
	if motion == null:
		return

	var recorder := _SignalRecorder.new()
	motion.sound = recorder
	# Сколько физкадров на ход в одну сторону — с запасом, по duration двери, а не литералом.
	var travel := ceili(motion.duration * Engine.physics_ticks_per_second) + 5

	# --- 1. Открытие: сигнал на старте и сигнал на конце хода ----------
	S_DoorMotion.open(door)
	await _physics(2)
	_check(
		"%s: на старте открытия — opened, конца хода ещё нет" % name,
		recorder.signals == [motion.opened_signal],
		"сигналы: %s" % [recorder.signals],
	)
	await _physics(travel)
	_check(
		"%s: доехав до открытой, дверь шлёт stopped ровно раз" % name,
		recorder.signals == [motion.opened_signal, motion.stopped_signal]
			and motion.phase == C_DoorMotion.Phase.OPEN,
		"сигналы: %s, фаза %d" % [recorder.signals, motion.phase],
	)

	# --- 2. Стоит открытой — новых сигналов нет -------------------------
	recorder.signals.clear()
	await _physics(int(Engine.physics_ticks_per_second * motion.hold * 0.5))
	_check("%s: стоящая открытой дверь молчит" % name, recorder.signals.is_empty(), "сигналы: %s" % [recorder.signals])

	# --- 3. Закрытие сама по hold: closed, затем stopped ----------------
	await _physics(int(Engine.physics_ticks_per_second * motion.hold) + travel)
	_check(
		"%s: закрылась сама — closed, затем stopped" % name,
		recorder.signals == [motion.closed_signal, motion.stopped_signal]
			and motion.phase == C_DoorMotion.Phase.CLOSED,
		"сигналы: %s, фаза %d" % [recorder.signals, motion.phase],
	)

	# --- 4. Разворот посреди закрытия: opened без stopped ---------------
	S_DoorMotion.open(door)
	await _physics(travel)
	recorder.signals.clear()
	S_DoorMotion.close(door)
	await _physics(travel / 3)
	S_DoorMotion.open(door)
	await _physics(2)
	_check(
		"%s: развёрнутая с середины закрытия — closed, opened и без stopped" % name,
		recorder.signals == [motion.closed_signal, motion.opened_signal],
		"сигналы: %s — stopped посреди хода оборвал бы звук до упора" % [recorder.signals],
	)
	await _physics(travel)
	_check(
		"%s: после разворота доехала и прислала stopped" % name,
		recorder.signals.back() == motion.stopped_signal and motion.phase == C_DoorMotion.Phase.OPEN,
		"сигналы: %s" % [recorder.signals],
	)

	motion.sound = null
	world.remove_entity(door)
	await get_tree().process_frame
