extends Node
## Проверка подключения аудиодвижка byProd (GDExtension `addons/byprod`).
## Запуск: godot --headless dev/byprod_check.tscn
##
## Инвариант тихий, поэтому и проверяется: расширение, которое не загрузилось,
## НЕ роняет проект — классы просто перестают существовать, и звук молча
## пропадает целиком. Обратное так же тихо: рантайм `byProd.dll` лежит вне git
## (лицензия Madrigal запрещает распространять его отдельно от приложения), и
## на машине без него всё обязано деградировать в no-op, а не падать.
##
## Ни один класс расширения здесь не назван идентификатором — только строкой
## через `ClassDB`. Иначе скрипт с ненайденным `ByProdSoundManager` не прошёл бы
## парсер, `_ready()` не запустился бы вовсе, и прогон завершился бы С НУЛЁМ,
## пропустив ровно ту поломку, ради которой написан.
##
## Мир ECS не поднимается: расширение живёт сбоку от GECS и ни одной системы
## пока не питает.

## Версия SDK, под которую написан биндинг, в кодировке bpdVersion():
## (major << 16) | (minor << 8) | patch.
const EXPECTED_RUNTIME_VERSION := (0 << 16) | (5 << 8) | 2

var _ok := 0
var _fail := 0


func _ready() -> void:
	_run()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	# --- 1. Расширение загрузилось и зарегистрировало классы ------------
	for class_name_string in ["ByProdSoundManager", "ByProdEventDescription",
			"ByProdEventInstance", "ByProdGroupBus", "ByProdStreamPump"]:
		_check(
			"класс %s зарегистрирован" % class_name_string,
			ClassDB.class_exists(class_name_string),
			"GDExtension не загрузился — проверить addons/byprod/bin/ и byprod.gdextension",
		)

	if not ClassDB.class_exists("ByProdSoundManager"):
		return

	# --- 2. Нативный рантайм ------------------------------------------
	# Его отсутствие — не провал: он не в репозитории. Провал — если из-за
	# этого что-то падает или врёт, поэтому дальше проверяется именно это.
	var runtime_present: bool = ClassDB.class_call_static("ByProdSoundManager", "is_runtime_available")
	print("  --   нативный byProd %s" % ("найден" if runtime_present else "отсутствует (ожидаемо без SDK)"))

	var last_error: String = ClassDB.class_call_static("ByProdSoundManager", "get_last_error")
	_check(
		"без рантайма отчёт о причине не пустой",
		runtime_present or not last_error.is_empty(),
		"is_runtime_available()=false, но get_last_error() молчит — диагностика потеряна",
	)

	# Менеджер берётся у AudioManager, а НЕ создаётся здесь свой: второй менеджер
	# в одном процессе роняет рантайм segfault'ом прямо в создании, когда
	# устройство уже открыто первым. Проверка, заводившая собственный, валила
	# прогон целиком — при том, что все её ассерты успевали пройти.
	var manager = AudioManager.sound_manager()

	# --- 3. Деградация без рантайма ------------------------------------
	if not runtime_present:
		var version: int = ClassDB.class_call_static("ByProdSoundManager", "get_runtime_version")
		_check(
			"без рантайма менеджера нет, и игра при этом жива",
			manager == null,
			"менеджер есть, хотя библиотека не загружена",
		)
		_check(
			"без рантайма версия читается как 0",
			version == 0,
			"версия %d при отсутствующей библиотеке" % version,
		)
		return

	# --- 4. Работа с рантаймом -----------------------------------------
	# Отсутствие менеджера при живом рантайме — это отсутствие устройства
	# (headless на машине без звука, CI). Не провал биндинга, но и проверять
	# дальше нечего: своего менеджера здесь заводить нельзя.
	if manager == null:
		print("  --   устройство недоступно (%s) — работа с рантаймом не проверяется" % (
				ClassDB.class_call_static("ByProdSoundManager", "get_last_error")))
		return

	_check(
		"AudioManager поднял менеджер byProd",
		manager.is_valid(),
		"менеджер есть, но невалиден",
	)

	var runtime_version: int = ClassDB.class_call_static("ByProdSoundManager", "get_runtime_version")
	_check(
		"версия рантайма совпадает с той, под которую писан биндинг",
		runtime_version == EXPECTED_RUNTIME_VERSION,
		"рантайм %d, ожидался %d" % [runtime_version, EXPECTED_RUNTIME_VERSION],
	)
	_check(
		"несуществующее событие даёт null, а не мусор",
		manager.get_event_description("event:/нет-такого") == null,
		"вернулось описание события, которого нет в проекте",
	)
	_check(
		"такт и слушатель без загруженного проекта безопасны",
		_survives_update(manager),
		"update() без загруженного проекта уронил рантайм",
	)


## Отдельной функцией, чтобы падение было видно как провал ассерта, а не как
## обрыв всего прогона без итоговой строки.
func _survives_update(manager) -> bool:
	manager.update()
	manager.set_listener_transform(Vector3.ZERO, Vector3.FORWARD, Vector3.UP)
	manager.update()
	return true


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
