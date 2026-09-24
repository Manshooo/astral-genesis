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
## Мир ECS не поднимается: проверяется цепочка «расширение → рантайм → проект»,
## а её потребитель (S_Footsteps) проверяется своей отдельной проверкой
## dev/footsteps_check.tscn — там нужна физика, здесь она только мешала бы.

## Версия рантайма, которую кладёт пайплайн (URL в .github/workflows/*.yml), в
## кодировке bpdVersion(): (major << 16) | (minor << 8) | patch.
##
## Число двигается не по желанию: старые пакеты с byprod.io ПРОПАДАЮТ, и 0.5.2
## отдала 404 в тот же день, когда вышла 0.5.3. Ассерт держит пару «пайплайн ↔
## проверка» сведённой: разъехавшись, проверка молча зеленела бы на рантайме,
## которого в сборке нет.
##
## БИНДИНГ собран под ту же версию (godot-byprod@d832ec3) — и этого ассерт НЕ
## проверяет: разъехавшись, биндинг всего лишь пишет предупреждение в лог при
## старте, потому что рантайм он резолвит по символам, а не линкуется с ним.
## Проверка на такой паре зеленеет целиком, так что расхождение видно только
## строкой «this binding targets …» в логе. Пересобрать биндинг можно лишь в
## godot-byprod, отсюда это не делается.
const EXPECTED_RUNTIME_VERSION := (0 << 16) | (5 << 8) | 3

## Событие шагов — им проверяется, что контент вообще доезжает до рантайма, и
## заодно что параметры события живы (у него есть темп).
const WALK_EVENT := "event:/sfx/walk"

## Float-параметр этого события — темп ходьбы, им S_Footsteps правит петлю.
const WALK_TEMPO_PARAMETER := "Param1"

var _ok := 0
var _fail := 0


func _ready() -> void:
	await _run()

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

	# Собранный аддон лежит в git и потому может отстать от биндинга: подписка
	# на паузу появилась в godot-byprod позже первой выкладки. Спрашивается
	# здесь, до всякого рантайма, — это единственный ассерт про паузу, который
	# проходит и в CI, где рантайма нет вовсе.
	_check(
		"биндинг умеет подписывать инстанс на паузу",
		ClassDB.class_has_method("ByProdEventInstance", "set_auto_pause"),
		"в addons/byprod/bin/ лежит расширение старее godot-byprod@1de1fca — обновить",
	)

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

	# --- Громкость: значение по умолчанию ------------------------------
	# Спрашиваем ДЕФОЛТ, а не текущие настройки: проверка идёт на машине
	# разработчика, где в user:// лежит его собственный ползунок.
	_check(
		"по умолчанию громкость на единице",
		is_equal_approx(SettingsManager.default_settings().master_volume, 1.0),
		"дефолт %f — тихий старт игры выглядел бы как поломка звука" % (
			SettingsManager.default_settings().master_volume),
	)

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

	# Прогон проверок не должен звучать у того, кто их запустил, — а запускают их
	# пачками и в наушниках. В headless AudioManager поднимает рантайм БЕЗ своего
	# устройства (host-mixed), и вот это здесь и сверяется.
	#
	# Ассерт слабый и честно слабый: у рантайма нет способа спросить «открыто ли
	# устройство», так что проверяется решение AudioManager, а не его следствие.
	# Ловит он ровно одно — убранную развилку по DisplayServer, из-за которой
	# звук вернулся бы в наушники молча. Наблюдаемое подтверждение — строка
	# рантайма в логе: «Audio started on null driver» вместо «on MiniAudio».
	_check(
		"headless-прогон не открывает устройство вывода",
		AudioManager._host_mixed,
		"рантайм поднят с настоящим устройством — проверки будут звучать",
	)

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
		"версия рантайма — та, которую кладёт пайплайн",
		runtime_version == EXPECTED_RUNTIME_VERSION,
		"рантайм %d, ожидался %d" % [runtime_version, EXPECTED_RUNTIME_VERSION],
	)
	_check(
		"несуществующее событие даёт null, а не мусор",
		manager.get_event_description("event:/нет-такого") == null,
		"вернулось описание события, которого нет в проекте",
	)
	_check(
		"такт и слушатель безопасны",
		_survives_update(manager),
		"update() уронил рантайм",
	)

	# --- 5. Проект звука доехал до рантайма ----------------------------
	# Событие находится только если рантайм принял и .byprod, и его банк: банки
	# он просит у хоста сам, и промах по каталогу выглядит ровно как «нет такого
	# события». Проверяется поэтому здесь, а не по флагу «проект загружен».
	var description = manager.get_event_description(WALK_EVENT)
	_check(
		"событие шагов на месте",
		description != null,
		"«%s» не найдено — проверить %s и банки рядом с ним" % [
			WALK_EVENT, AudioManager.PROJECT_PATH],
	)

	# Спрашивается СТРОКА С КАРТОЧКИ, а не константа рядом: разойтись могут
	# только собранный проект и то, что просит механика, — а сверка литерала с
	# самим собой зеленела бы всегда.
	var card: Control = load("res://src/ui/skill_tree/skill_node_card.tscn").instantiate()
	_check(
		"карточка навыка просит событие, которое есть в проекте",
		manager.get_event_description(card.unlock_event) != null,
		"карточка просит «%s» — в собранном проекте такого события нет" % card.unlock_event
	)
	card.free()

	if description == null:
		return

	# Найденное событие — ещё не звучащее: голос мог не выделиться, волна могла
	# не доехать из банка. Отличить это можно только заведя инстанс и спросив
	# рантайм, что с ним стало, — «загрузилось» тут ничего не доказывает.
	var instance = description.create_instance()
	_check("инстанс события создаётся", instance != null, "create_instance() вернул null")
	if instance == null:
		return

	instance.start()
	instance.set_parameter(WALK_TEMPO_PARAMETER, 1.0)
	manager.update()

	# Константа берётся из ClassDB, а не пишется числом: имя расширения нельзя
	# называть идентификатором (см. шапку), но и магическое число здесь молча
	# разъедется с биндингом.
	var playing := ClassDB.class_get_integer_constant("ByProdEventInstance", "STATE_PLAYING")
	_check(
		"заведённое событие действительно играет",
		instance.get_state() == playing,
		"состояние %d вместо %d — волна не доехала из банка или голос не выделился" % [
			instance.get_state(), playing],
	)

	instance.stop()

	# --- 6. Громкость доезжает из настроек в мастер-шину ----------------
	# Через SettingsManager, а не прямым вызовом: проверяется именно цепочка
	# «ползунок → настройки → сигнал → движок», ради которой AudioManager на
	# settings_changed и подписан. Правка идёт по КОПИИ и откатывается ниже —
	# проверка не имеет права оставить игроку свою громкость.
	var original := SettingsManager.settings
	_check(
		"громкость из настроек доезжает до движка",
		_volume_reaches_engine(manager, 0.5, 0.5),
		"мастер-шина осталась на прежнем значении — оборвалась цепочка настроек",
	)
	_check(
		"громкость выше единицы прижимается к единице",
		_volume_reaches_engine(manager, 2.0, 1.0),
		"движку ушло значение вне диапазона 0..1",
	)
	_check(
		"нулевая громкость доезжает как ноль, а не как «нет значения»",
		_volume_reaches_engine(manager, 0.0, 0.0),
		"ноль потерялся по дороге — тишина не включилась бы",
	)
	SettingsManager.settings = original

	# --- 7. Пауза игры останавливает звук ------------------------------
	# Инстанс берётся у AudioManager, а не у описания напрямую: подписка на
	# уровень тика ставится именно там, и проверка мимо него мерила бы путь,
	# которым механика звук не заводит.
	#
	# Ломается это тихо во все три стороны сразу: не подписанный инстанс,
	# автолоад, чей `_process` спит на паузе, и уровень тика, не вернувшийся к
	# FULL, выглядят одинаково — «звук ведёт себя не так», без единой ошибки в
	# логе. Поэтому проверяется наблюдаемое состояние голоса, а не вызовы.
	var paused_state := ClassDB.class_get_integer_constant("ByProdEventInstance", "STATE_PAUSED")
	var loop = AudioManager.create_event_instance(WALK_EVENT)
	_check("AudioManager отдаёт инстанс события", loop != null, "create_event_instance() вернул null")
	if loop == null:
		return

	loop.start()
	manager.update()

	get_tree().paused = true
	var stopped_on_pause: bool = await _reaches_state(loop, paused_state)
	_check(
		"на паузе игры звук замолкает",
		stopped_on_pause,
		"состояние %d вместо %d — инстанс не подписан на уровень тика либо AudioManager спит на паузе" % [
			loop.get_state(), paused_state],
	)

	get_tree().paused = false
	var resumed: bool = await _reaches_state(loop, playing)
	_check(
		"после паузы звук едет дальше с того же места",
		resumed,
		"состояние %d вместо %d — уровень тика не вернулся к FULL" % [loop.get_state(), playing],
	)

	loop.stop()


## Ставит громкость через настройки и отвечает, увидел ли её движок.
##
## Присваивание идёт в СВОЙСТВО settings целиком: сеттер и есть то, что
## применяет эффекты и шлёт settings_changed, — правка поля на месте прошла бы
## мимо всей цепочки и проверяла бы пустоту.
func _volume_reaches_engine(manager, requested: float, expected: float) -> bool:
	var draft := SettingsManager.settings.copy()
	draft.master_volume = requested
	SettingsManager.settings = draft
	return is_equal_approx(manager.get_global_volume(), expected)


## Ждёт, пока голос не придёт в состояние `state`, но не дольше нескольких
## кадров.
##
## Кадрами, а не одним ожиданием: уровень тика доезжает до рантайма из
## `AudioManager._process`, а `process_frame` летит ДО `_process` узлов — после
## одного `await` автолоад ещё не тикал ни разу. Запас сверх этого — на то, что
## рантайм мешает в своём потоке и применяет команду не обязательно в тот же
## вызов `update()`.
func _reaches_state(instance, state: int, frames: int = 8) -> bool:
	for _i in frames:
		await get_tree().process_frame
		if instance.get_state() == state:
			return true
	return false


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
