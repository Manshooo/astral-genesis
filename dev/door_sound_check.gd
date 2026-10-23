extends "res://dev/check_harness.gd"
## Проверка звука хода двери (`S_DoorMotion` → `C_DoorMotion.sound`).
## Запуск: godot --headless dev/door_sound_check.tscn
##
## Инвариант тихий: событие хода держит петлю привода, пока не придёт stop, и
## пропущенный stop звучит мотором, который не глохнет, а ход без своего события —
## тишиной; ошибки не бросает ни то, ни другое.
##
## Старт хода наблюдается по `AudioManager.event_requested` — он шлётся до всякой
## проверки на загруженный проект. Окончание — подставным объектом в
## `C_DoorMotion.sound`, положенным после старта: так проверка не зависит ни от
## рантайма byProd, ни от того, есть ли событие в собранном проекте звука.

const DOOR_SCENES := [
	"res://src/entities/door/complex_door.tscn",
	"res://src/entities/door/double_door.tscn",
]


## Записывает, что сделали с инстансом события, вместо ByProdEventInstance.
class _InstanceRecorder:
	extends RefCounted

	var calls: Array[String] = []

	func send_signal(signal_name: String) -> void:
		calls.append("signal:" + signal_name)

	func release_when_finished() -> void:
		calls.append("release")


var _requests: Array[String] = []


func _ready() -> void:
	var world := _new_world()
	_add_systems(world, "physics", [S_DoorMotion.new()])
	AudioManager.event_requested.connect(func(path: String, _position: Vector3) -> void: _requests.append(path))

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

	# Сколько физкадров на ход в одну сторону — с запасом, по duration двери, а не литералом.
	var travel := ceili(motion.duration * Engine.physics_ticks_per_second) + 5
	var ended := ["signal:" + motion.stop_signal, "release"]

	# --- 1. Открытие: своё событие на старте, stop и отдача рантайму на конце ---
	_requests.clear()
	S_DoorMotion.open(door)
	_check(
		"%s: старт открытия заводит событие хода" % name,
		_requests == [motion.event_path],
		"запросы: %s" % [_requests],
	)
	var opening := _InstanceRecorder.new()
	motion.sound = opening
	await _physics(travel)
	_check(
		"%s: доехав до открытой, ход получает stop и уходит рантайму" % name,
		opening.calls == ended and motion.sound == null and motion.phase == C_DoorMotion.Phase.OPEN,
		"вызовы: %s, фаза %d" % [opening.calls, motion.phase],
	)

	# --- 2. Закрытие по hold — тот же путь: новое событие, stop на конце ---------
	_requests.clear()
	await _physics(int(Engine.physics_ticks_per_second * motion.hold) + 2)
	_check(
		"%s: закрытие заводит своё событие хода, тот же путь, что открытие" % name,
		_requests == [motion.event_path] and motion.phase == C_DoorMotion.Phase.CLOSING,
		"запросы: %s, фаза %d" % [_requests, motion.phase],
	)
	var closing := _InstanceRecorder.new()
	motion.sound = closing
	await _physics(travel)
	_check(
		"%s: доехав до закрытой, ход получает stop и уходит рантайму" % name,
		closing.calls == ended and motion.sound == null and motion.phase == C_DoorMotion.Phase.CLOSED,
		"вызовы: %s, фаза %d" % [closing.calls, motion.phase],
	)

	# --- 3. Разворот посреди закрытия: прерванный ход без окончания ------------
	S_DoorMotion.open(door)
	await _physics(travel)
	S_DoorMotion.close(door)
	var interrupted := _InstanceRecorder.new()
	motion.sound = interrupted
	await _physics(travel / 3)
	_requests.clear()
	S_DoorMotion.open(door)
	_check(
		"%s: развёрнутый ход не получает stop — удар в упор посреди проёма" % name,
		interrupted.calls.is_empty() and motion.sound != interrupted,
		"вызовы прерванного: %s" % [interrupted.calls],
	)
	_check(
		"%s: разворот заводит новое событие хода" % name,
		_requests == [motion.event_path],
		"запросы: %s" % [_requests],
	)
	var reopening := _InstanceRecorder.new()
	motion.sound = reopening
	await _physics(travel)
	_check(
		"%s: после разворота ход доезжает и получает stop" % name,
		reopening.calls == ended and motion.phase == C_DoorMotion.Phase.OPEN,
		"вызовы: %s" % [reopening.calls],
	)

	motion.sound = null
	world.remove_entity(door)
	await get_tree().process_frame
