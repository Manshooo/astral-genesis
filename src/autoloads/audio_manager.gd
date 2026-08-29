extends Node
## Единственный владелец рантайма byProd: держит менеджер, грузит собранный
## проект звука, каждый кадр двигает слушателя, тикает движок и переводит его
## уровень тика вслед за паузой игры.
##
## Ни один класс расширения здесь НЕ назван идентификатором — только строкой
## через `ClassDB`. Это не стилистика: автолоад со ссылкой на незагруженный
## класс не проходит парсер, а упавший автолоад валит игру целиком. Расширение
## же может отсутствовать штатно — рантайм byProd не входит в репозиторий (см.
## `addons/byprod/README.md`), и в свежем клоне до `--import` классов ещё нет.
## Цена ошибки здесь — не «нет звука», а «не запускается», поэтому дороже.
##
## Всё, что ниже, устроено так, чтобы отсутствие звука было тихим: нет
## расширения, нет рантайма, нет собранного проекта — игра идёт молча.

## Проект, собранный редактором byProd. Рядом с ним лежат его же банки (.bybank),
## которые рантайм запрашивает у хоста сам, по имени.
##
## Пока это ПРОБНЫЙ проект (`assets/sound/demo/`) с единственным событием
## `event:/walk` — им проверяется, что цепочка «механика → byProd → колонки»
## жива. Когда появится настоящий проект звука, здесь поменяется путь, и
## больше ничего: события механика называет строками из своих компонентов.
##
## Каталог собранного проекта лежит в git и попадает в сборку через
## `include_filter` в `export_presets.cfg`: .byprod и .bybank — не ресурсы Godot,
## сам он их в .pck не положит.
const PROJECT_PATH := "res://assets/sound/demo/build/walk.byprod"
const BANK_DIRECTORY := "res://assets/sound/demo/build"

## Просьба сыграть событие — до всякой проверки на то, есть ли чем играть.
## Подписчику (проверке в dev/, вибрации, отладочному оверлею) важно, что
## механика ЗАПРОСИЛА звук, а не сложилось ли воспроизведение.
signal event_requested(event_path: String, position: Vector3)

## ByProdSoundManager, когда расширение и рантайм на месте.
var _manager: Object = null

## Проект загружен — до этого играть нечего.
var _loaded := false

## Описания событий по пути: поиск по строке стоит дороже, чем словарь, а шаги
## спрашивают одно и то же событие по нескольку раз в секунду.
var _descriptions: Dictionary = {}

## Пути, о которых уже пожаловались. Без этого промах по имени события
## превратился бы в поток предупреждений с частотой шагов.
var _missing_reported: Dictionary = {}

## Уровни тика рантайма — «сколько мира сейчас идёт». Берутся из ClassDB, а не
## пишутся числами: имя класса расширения здесь нельзя называть идентификатором
## (см. шапку), а магическая константа молча разъехалась бы с биндингом.
var _tick_level_none := 0
var _tick_level_full := 0

## Уровень, отданный рантайму последним. Нужен именно кэш: у SceneTree нет
## сигнала о смене `paused`, состояние приходится сверять каждый кадр, а звать
## из-за этого нативный set_tick_level() по шестьдесят раз в секунду незачем.
var _tick_level := -1


func _ready() -> void:
	# Пауза — единственный момент, когда этому автолоаду ОСОБЕННО есть что
	# делать: обычный `_process` на паузе не вызывается, и сказать рантайму, что
	# мир встал, было бы уже некому. Тикать движок на паузе тоже надо — команды
	# он разбирает в update(), и без него уровень тика не доехал бы до голосов.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Громкость приезжает из настроек, а не наоборот: SettingsManager стоит в
	# project.godot ВЫШЕ этого автолоада, поэтому к моменту _ready его settings
	# уже загружены и подписка ничего не пропустит. Обратной зависимости нет
	# намеренно — SettingsManager не должен знать про byProd.
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_start()


func _start() -> void:
	if not ClassDB.class_exists("ByProdSoundManager"):
		push_warning("byProd: расширение не загружено — игра идёт без звука.")
		return

	_tick_level_none = ClassDB.class_get_integer_constant("ByProdSoundManager", "TICK_LEVEL_NONE")
	_tick_level_full = ClassDB.class_get_integer_constant("ByProdSoundManager", "TICK_LEVEL_FULL")

	_manager = ClassDB.class_call_static("ByProdSoundManager", "create")
	if _manager == null:
		push_warning("byProd: %s — игра идёт без звука." % ClassDB.class_call_static(
				"ByProdSoundManager", "get_last_error"))
		return

	# Ставится до загрузки проекта: банки рантайм просит сам, и без каталога он
	# сообщит «нет такого банка» вместо того, чтобы молча остаться без волн.
	_manager.set_bank_directory(BANK_DIRECTORY)

	# До загрузки проекта: громкость — свойство менеджера, а не проекта, и
	# применить её надо даже когда проекта нет, иначе первый же поворот
	# ползунка после неудачной загрузки застал бы движок на единице.
	_apply_volume()

	if not FileAccess.file_exists(PROJECT_PATH):
		push_warning("byProd: нет собранного проекта %s — игра идёт без звука." % PROJECT_PATH)
		return

	if not _manager.load_project(FileAccess.get_file_as_bytes(PROJECT_PATH)):
		push_warning("byProd: проект %s не принят рантаймом." % PROJECT_PATH)
		return

	_loaded = true


func _process(_delta: float) -> void:
	if _manager == null:
		return

	# Слушатель едет за активной камерой, а не за игроком: это одно и то же во
	# время забега, но в меню и на экране итогов игрока в мире может не быть
	# вовсе, а камера есть всегда.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var t := camera.global_transform
		_manager.set_listener_transform(t.origin, -t.basis.z, t.basis.y)

	_apply_tick_level(get_tree().paused)
	_manager.update()


## Переводит рантайм между «мир идёт» и «мир стоит».
##
## Пауза здесь — это `SceneTree.paused`, то есть ровно то, что ставит UIManager
## под меню паузы. Экран, открытый без паузы (дерево навыков), мир не
## останавливает — и звук под ним тоже не обязан замолкать.
##
## Промежуточный TICK_LEVEL_PARTIAL («мир идёт наполовину») биндинг знает, но
## подписывать на него пока некого: он разводит музыку, которая играет под
## открытым меню, и окружение, которое нет, а ни того ни другого в проекте
## звука ещё нет. Появятся — уровень станет параметром подписки, а не вторым
## состоянием здесь.
func _apply_tick_level(paused: bool) -> void:
	var level := _tick_level_none if paused else _tick_level_full
	if level == _tick_level:
		return
	_tick_level = level
	_manager.set_tick_level(level)


func _on_settings_changed(_settings: RS_Settings) -> void:
	_apply_volume()


## Общая громкость из настроек — в мастер-шину byProd.
##
## Значение уходит КАК ЕСТЬ: громкость byProd — линейный множитель (1.0 —
## «как записано»), а не децибелы, поэтому linear_to_db, обязательный для шин
## Godot, здесь только испортил бы шкалу. Мастер-шина и глобальная громкость —
## одно и то же число, отсюда set_global_volume, а не поиск шины по пути.
##
## Громкостей по шинам («музыка», «эффекты») пока нет и завести их из кода
## нельзя: шины объявляет ПРОЕКТ byProd, а в пробном (assets/sound/demo) их
## ноль — get_group_bus вернул бы null, и ползунок оказался бы мёртвым. Когда
## настоящий проект их объявит, добавятся поля в RS_Settings и вызовы
## get_group_bus(...).set_volume() рядом с этим.
func _apply_volume() -> void:
	if _manager == null:
		return
	_manager.set_global_volume(clampf(SettingsManager.settings.master_volume, 0.0, 1.0))


## Менеджер byProd этого процесса, или null, если рантайма нет.
##
## Существует, чтобы никто не заводил СВОЙ: второй менеджер в одном процессе
## роняет рантайм (проверено — segfault прямо в bpdSoundManagerCreate, когда
## устройство уже открыто первым). Отсюда же и автолоад: единственность здесь
## не удобство, а требование.
func sound_manager() -> Object:
	return _manager


## Разовый звук в точке мира: механика говорит ЧТО и ГДЕ, не заботясь о том,
## загружен ли звук вообще.
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
	# Владение уходит рантайму: одноразовый звук незачем держать со стороны игры,
	# и без этого инстанс жил бы до сборки мусора, занимая голос.
	#
	# Отсюда же и порядок: после этой строки ручки инстанса у игры нет, и
	# подписать его на паузу было бы уже нечем. Разовый звук слушается паузы
	# ТОЛЬКО так — сам себя он не остановит, потому что его никто не держит.
	instance.release_when_finished()


## Длящийся звук: инстанс отдаётся вызывающему, и дальше он сам решает, когда
## его завести, чем параметризовать и когда отпустить.
##
## Отдельно от `play_event_3d`, потому что владение здесь противоположное:
## разовый звук доигрывает сам и не нужен игре после старта, а зацикленный
## (шаги, гул, дождь) не кончается никогда — и если его никто не держит, его
## некому и остановить. Ссылку достаточно уронить: деструктор биндинга
## освобождает голос сам.
func create_event_instance(event_path: String) -> Object:
	# Как и в play_event_3d — до проверки на «а есть ли чем играть»: подписчику
	# важен сам запрос. Позиции у петли нет, она заводится не в точке мира.
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


## Подписывает инстанс на уровень тика: на паузе он встанет, после — поедет
## дальше с того же места.
##
## Централизовано, а не оставлено вызывающему, по двум причинам. Подписка в
## рантайме ВЫКЛЮЧЕНА по умолчанию, то есть забытый вызов не ломается заметно —
## звук просто продолжает играть сквозь паузу, и это надо ещё услышать. И
## заведённый на паузе инстанс (петля шагов, стартовавшая в тот же кадр)
## подписки требует ровно так же, а вызывающий об этом думать не обязан.
func _follow_pause(instance: Object) -> void:
	# Уровень не передаётся: по умолчанию биндинг ставит TICK_LEVEL_NONE —
	# «замолкнуть, когда мир остановлен целиком», — а другого уровня в игре
	# пока нет (см. _apply_tick_level).
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
