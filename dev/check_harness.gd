extends Node
## Общая обвязка headless-проверок dev/*_check: счёт ассертов, итоговая строка,
## код выхода, сторож ошибок скрипта, мир с системами и подконтрольные физкадры.
## Проверка наследует её путём — extends "res://dev/check_harness.gd" — и в конце
## зовёт _finish().
##
## Раньше каждая проверка несла свою копию всего этого: 27 одинаковых _check()
## (одна — с другой сигнатурой), 15 заготовок мира и 5 копий механики физкадров.
## Хуже дублирования было то, что защиту от «тихо оборванного блока» успели
## получить только пять проверок из 27. Обрыв такой: SCRIPT ERROR внутри блока
## прерывает только этот блок, прогон идёт дальше, итог печатается с нулём
## провалов — и сломанное выглядит зелёным (так однажды прошёл первый прогон
## corridor_graph_check). Те пять сверяли число ассертов с ручной константой
## EXPECTED_ASSERTS, которую надо было править при каждом новом ассерте. Здесь
## сторож другой и общий: Logger движка считает сами SCRIPT ERROR, и любая такая
## ошибка за прогон — провал, сколько бы ассертов ни было.
##
## Путём, а не class_name: dev/* исключён из экспорта, и глобальному классу
## отсюда нечего делать в списке классов собранной игры и редактора.

## Имя группы, которую крутят подконтрольные физкадры по умолчанию, — та же, что
## main.gd гоняет из _physics_process.
const PHYSICS_GROUP := "physics"

var _ok := 0
var _fail := 0
## Печатать ли строку на каждый пройденный ассерт. Проверки с тысячами
## однотипных ассертов (прогон инструмента по сидам) выключают её: в логе CI
## нужны провалы, а не две с половиной тысячи «ok».
var _print_passes := true
## Сколько подконтрольных физкадров ещё осталось прогнать (см. _physics).
var _pending_ticks := 0
var _script_errors := _ScriptErrorCounter.new()


## Считает SCRIPT ERROR за время жизни проверки. Только их: push_error — это
## сообщение, которое проверка может вызвать намеренно (битые данные в
## негативном сценарии), а ошибка скрипта — всегда оборванный код.
## Движок зовёт логгер с любого потока, поэтому счётчик под мьютексом.
class _ScriptErrorCounter:
	extends Logger

	var _mutex := Mutex.new()
	var _count := 0
	var _first := ""

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_count += 1
		if _first == "":
			_first = "%s (%s:%d, %s)" % [rationale if rationale != "" else code, file, line, function]
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var result := _count
		_mutex.unlock()
		return result

	func first() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result


func _enter_tree() -> void:
	OS.add_logger(_script_errors)


func _exit_tree() -> void:
	OS.remove_logger(_script_errors)


func _check(what: String, passed: bool, detail: String = "") -> void:
	if passed:
		_ok += 1
		if _print_passes:
			print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])


## Итог и выход. Итоговую строку раннер ТРЕБУЕТ: проверка, упёршаяся в
## --quit-after, закрывается движком с кодом 0, и отличить обрыв от успеха можно
## только по тому, напечатан ли итог (см. SKILL.md gameplay-testing).
func _finish() -> void:
	var errors := _script_errors.count()
	_check(
		"прогон без ошибок скрипта",
		errors == 0,
		"SCRIPT ERROR: %d, первая — %s" % [errors, _script_errors.first()]
	)
	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## Свежий мир под проверку, сразу назначенный ECS.world.
func _new_world() -> World:
	var world := World.new()
	add_child(world)
	ECS.world = world
	return world


## Добавляет системы в [param group] и сортирует группы так же, как это делает
## World.initialize() для систем из world.tscn. Без сортировки проверка гоняет
## системы в порядке списка, а игра — в порядке deps(), и расхождение не видно:
## именно так ход и прыжок годами доезжали до тела на тик позже S_Movement.
func _add_systems(world: World, group: String, systems: Array) -> void:
	for system: System in systems:
		system.group = group
	world.add_systems(systems, true)


## Что делает один подконтрольный физкадр. По умолчанию — группа "physics";
## проверка, которой нужно больше (гнать тело, тикать "gameplay"), переопределяет.
func _on_physics_tick(delta: float) -> void:
	ECS.process(delta, PHYSICS_GROUP)


func _physics_process(delta: float) -> void:
	if _pending_ticks <= 0:
		return
	_pending_ticks -= 1
	_on_physics_tick(delta)


## Прогоняет [param frames] физкадров и ждёт, пока они отработают.
func _physics(frames: int) -> void:
	_pending_ticks = frames
	while _pending_ticks > 0:
		await get_tree().physics_frame
	await get_tree().physics_frame  # последнему тику дать долететь
