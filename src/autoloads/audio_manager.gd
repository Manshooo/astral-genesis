extends Node
## Единственный владелец рантайма byProd: менеджер, проект звука, слушатель, тик и пауза.
## Классы расширения — только строкой через `ClassDB`: автолоад со ссылкой на незагруженный
## класс не парсится и валит игру; нет расширения — игра идёт молча. Вики: [[Звук]].

## Выгрузка проекта byProd (редакторский проект вне репозитория). Смена проекта звука —
## правка этих двух констант; в сборку идёт через `include_filter` экспорта ([[Звук]] §6).
const PROJECT_PATH := "res://assets/sound/astral-genesis.byprod"
const BANK_DIRECTORY := "res://assets/sound"

## Частота headless-рантайма, Гц: та же, что вживую, чтобы прогоны мерили одно и то же.
const HEADLESS_SAMPLE_RATE := 44100
## Потолок кадров за тик: на первом кадре delta бывает в секунды.
const HEADLESS_MIX_FRAMES_MAX := 4096

## Просьба сыграть событие — до проверки, есть ли чем играть: подписчикам важен сам запрос.
signal event_requested(event_path: String, position: Vector3)

## ByProdSoundManager, когда расширение и рантайм на месте.
var _manager: Object = null

## Проект загружен — до этого играть нечего.
var _loaded := false

## Рантайм поднят без устройства вывода (headless): буфер забирает хост.
var _host_mixed := false

## Описания событий по пути: шаги спрашивают одно и то же по нескольку раз в секунду.
var _descriptions: Dictionary = {}

## Пути, о которых уже предупредили, — иначе промах станет потоком варнингов.
var _missing_reported: Dictionary = {}

## Уровни тика берутся из ClassDB, а не числами: класс расширения нельзя назвать идентификатором.
var _tick_level_none := 0
var _tick_level_full := 0

## Последний отданный рантайму уровень: у SceneTree нет сигнала смены `paused`.
var _tick_level := -1


func _ready() -> void:
	# На паузе _process не зовётся, а движок тикать надо — команды разбирает update().
	process_mode = Node.PROCESS_MODE_ALWAYS

	# SettingsManager стоит в project.godot выше: settings уже загружены; обратной зависимости нет.
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_start()


func _start() -> void:
	if not ClassDB.class_exists("ByProdSoundManager"):
		push_warning("byProd: расширение не загружено — игра идёт без звука.")
		return

	_tick_level_none = ClassDB.class_get_integer_constant("ByProdSoundManager", "TICK_LEVEL_NONE")
	_tick_level_full = ClassDB.class_get_integer_constant("ByProdSoundManager", "TICK_LEVEL_FULL")

	# Headless: рантайм без устройства (host-mixed), громкостью не глушим — иначе byprod_check
	# сверял бы ноль с нулём ([[Звук]] §5а).
	_host_mixed = DisplayServer.get_name() == "headless"
	if _host_mixed:
		_manager = ClassDB.class_call_static(
			"ByProdSoundManager", "create_host_mixed", HEADLESS_SAMPLE_RATE
		)
	else:
		_manager = ClassDB.class_call_static("ByProdSoundManager", "create")
	if _manager == null:
		push_warning("byProd: %s — игра идёт без звука." % ClassDB.class_call_static(
				"ByProdSoundManager", "get_last_error"))
		return

	# До загрузки проекта: иначе рантайм сообщит «нет такого банка».
	_manager.set_bank_directory(BANK_DIRECTORY)

	# До загрузки проекта: громкость — свойство менеджера, применять надо и без проекта.
	_apply_volume()

	if not FileAccess.file_exists(PROJECT_PATH):
		push_warning("byProd: нет собранного проекта %s — игра идёт без звука." % PROJECT_PATH)
		return

	if not _manager.load_project(FileAccess.get_file_as_bytes(PROJECT_PATH)):
		push_warning("byProd: проект %s не принят рантаймом." % PROJECT_PATH)
		return

	_loaded = true


func _process(delta: float) -> void:
	if _manager == null:
		return

	# Слушатель за активной камерой, не за игроком: в меню игрока в мире нет.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var t := camera.global_transform
		_manager.set_listener_transform(t.origin, -t.basis.z, t.basis.y)

	_apply_tick_level(get_tree().paused)
	_manager.update()
	if _host_mixed:
		_mix_and_discard(delta)


## Headless: прокрутить звук без вывода. Кадры по реальному delta, иначе звуковые часы
## разойдутся с игровыми ([[Звук]] §5а).
func _mix_and_discard(delta: float) -> void:
	var frames := mini(int(delta * HEADLESS_SAMPLE_RATE), HEADLESS_MIX_FRAMES_MAX)
	if frames > 0:
		_manager.mix(frames)


## Переводит рантайм между «мир идёт» и «мир стоит» по `SceneTree.paused`.
## Промежуточный TICK_LEVEL_PARTIAL пока не используется ([[Звук]] §5).
func _apply_tick_level(paused: bool) -> void:
	var level := _tick_level_none if paused else _tick_level_full
	if level == _tick_level:
		return
	_tick_level = level
	_manager.set_tick_level(level)


func _on_settings_changed(_settings: RS_Settings) -> void:
	_apply_volume()


## Общая громкость в мастер-шину byProd: значение линейное, без linear_to_db.
## Громкостей по шинам пока нет ([[Звук]] §4).
func _apply_volume() -> void:
	if _manager == null:
		return
	_manager.set_global_volume(clampf(SettingsManager.settings.master_volume, 0.0, 1.0))


## Менеджер byProd процесса или null. Второй менеджер в процессе роняет рантайм segfault'ом.
func sound_manager() -> Object:
	return _manager


## Разовый звук в точке мира.
func play_event_3d(event_path: String, position: Vector3) -> void:
	event_requested.emit(event_path, position)

	if not _loaded:
		return

	var description := _description_for(event_path)
	if description == null:
		return

	var instance = description.create_instance()
	if instance == null:
		return

	instance.set_3d_attributes(position, Vector3.ZERO)
	_follow_pause(instance)
	instance.start()
	# Владение уходит рантайму; после этой строки подписать инстанс на паузу уже нечем.
	instance.release_when_finished()


## Разовый звук интерфейса: без 3D-атрибутов и без подписки на паузу — меню паузы обязано
## звучать ([[Звук]] §5).
func play_event_ui(event_path: String) -> void:
	event_requested.emit(event_path, Vector3.ZERO)

	if not _loaded:
		return

	var description := _description_for(event_path)
	if description == null:
		return

	var instance = description.create_instance()
	if instance == null:
		return

	instance.start()
	instance.release_when_finished()


## Длящийся звук: инстанс отдаётся вызывающему. Ссылку достаточно уронить — деструктор
## биндинга освобождает голос.
func create_event_instance(event_path: String) -> Object:
	# До проверки «есть ли чем играть»: подписчику важен сам запрос.
	event_requested.emit(event_path, Vector3.ZERO)

	if not _loaded:
		return null

	var description := _description_for(event_path)
	if description == null:
		return null

	var instance = description.create_instance()
	if instance != null:
		_follow_pause(instance)
	return instance


## Подписывает инстанс на уровень тика. Подписка в рантайме выключена по умолчанию —
## забытый вызов не заметен: звук идёт сквозь паузу.
func _follow_pause(instance: Object) -> void:
	# Уровень не передаётся: по умолчанию NONE — замолкнуть, когда мир стоит целиком.
	instance.set_auto_pause(true)


func _description_for(event_path: String) -> Object:
	if _descriptions.has(event_path):
		return _descriptions[event_path]

	var description = _manager.get_event_description(event_path)
	if description == null:
		if not _missing_reported.has(event_path):
			_missing_reported[event_path] = true
			push_warning("byProd: в проекте нет события «%s»." % event_path)
		return null

	_descriptions[event_path] = description
	return description
