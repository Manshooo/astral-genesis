extends "res://dev/check_harness.gd"
## Проверка мыслей поглощённых (O_BodyThoughts): мысль тела звучит при первом
## захвате вида за забег и не повторяется при втором, неизвестный вид получает
## запасную, занятая строка HUD не перебивается, а новый забег начинает счёт
## заново.
##
## Событие захвата шлём вручную: сам захват (S_BodySnatch) проверяют другие
## проверки, а здесь важно, что наблюдатель делает с событием.
##
## Запускать: godot --headless dev/body_thoughts_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const WALKER_SCENE := "res://src/entities/body/e_body_walker.tscn"
const HOUND_SCENE := "res://src/entities/body/e_body_hound.tscn"
const CRAWLER_SCENE := "res://src/entities/body/e_body_crawler.tscn"
const THOUGHTS_PATH := "res://data/body_thoughts.tres"

## Сколько ждать, пока мысль выйдет после захвата: задержка наблюдателя с запасом.
const WAIT := O_BodyThoughts.DELAY + 0.4

var _soul: E_Player
var _observer: O_BodyThoughts
var _saved_stats: RS_RunStats


func _ready() -> void:
	_saved_stats = RunStats.current
	var world := _new_world()
	_observer = O_BodyThoughts.new()
	world.add_observer(_observer)

	_soul = (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(_soul)
	await get_tree().process_frame

	_check_data()
	# Забег начат: наблюдатель знает, что виденного пока нет. Сигнал
	# RunManager.complex_entered не шлём — на него отвечает и RunStats, подменяя
	# накопитель и сейв, а проверка про наблюдателя.
	RunStats.current = RS_RunStats.new()
	_observer._on_complex_entered(null)

	await _check_first_and_repeat()
	await _check_other_bodies()
	await _check_busy_screen()
	await _check_new_run()

	RunStats.current = _saved_stats
	_finish()


func _check_data() -> void:
	var thoughts := load(THOUGHTS_PATH) as RS_BodyThoughts
	_check("ресурс мыслей читается", thoughts != null, "")
	if thoughts == null:
		return
	_check("первое тело — сотрудник комплекса: своя мысль, а не запасная",
		thoughts.pick(WALKER_SCENE) == &"THOUGHT_BODY_WALKER", String(thoughts.pick(WALKER_SCENE)))
	_check("неизвестному виду достаётся запасная мысль",
		thoughts.pick("res://нет-такого-тела.tscn") == thoughts.default_key, "")
	var untranslated := PackedStringArray()
	for path in [WALKER_SCENE, HOUND_SCENE, CRAWLER_SCENE, "", "res://src/entities/body/e_body.tscn"]:
		var key := thoughts.pick(path)
		if tr(key) == String(key):
			untranslated.append(String(key))
	_check("все мысли переведены", untranslated.is_empty(), ", ".join(untranslated))


func _check_first_and_repeat() -> void:
	_capture(WALKER_SCENE)
	_check("в момент захвата мысли ещё нет — она выходит с задержкой", not _soul.has_component(C_ScreenMessage), "")
	await get_tree().create_timer(WAIT).timeout
	_check("первый захват вида звучит его мыслью", _message() == "THOUGHT_BODY_WALKER", _message())

	_clear_message()
	_capture(WALKER_SCENE)
	await get_tree().create_timer(WAIT).timeout
	_check("повторный захват того же вида молчит", _message() == "", _message())


func _check_other_bodies() -> void:
	_clear_message()
	_capture(HOUND_SCENE)
	await get_tree().create_timer(WAIT).timeout
	_check("другой вид — своя мысль", _message() == "THOUGHT_BODY_HOUND", _message())

	_clear_message()
	_capture("res://src/entities/body/e_body_неизвестное.tscn")
	await get_tree().create_timer(WAIT).timeout
	_check("вид без записи — запасная мысль", _message() == "THOUGHT_DEFAULT", _message())


## Чужая строка на экране: мысль её не перебивает, а ждёт и выходит следом.
func _check_busy_screen() -> void:
	_clear_message()
	C_ScreenMessage.show_on(_soul, "HUD_MSG_NO_ROOM")
	_capture(CRAWLER_SCENE)
	await get_tree().create_timer(O_BodyThoughts.DELAY + O_BodyThoughts.RETRY * 2.0 + 0.3).timeout
	_check("занятую строку мысль не перебивает", _message() == "HUD_MSG_NO_ROOM", _message())
	_clear_message()
	await get_tree().create_timer(O_BodyThoughts.RETRY + 0.3).timeout
	_check("освободилась — мысль выходит следом", _message() == "THOUGHT_BODY_CRAWLER", _message())

	# Игрок вышел из тела за время задержки — мысль того тела не к месту.
	_clear_message()
	_capture("res://src/entities/body/e_body_ушло.tscn")
	_soul.remove_component(C_Embodied)
	await get_tree().create_timer(WAIT).timeout
	_check("вышел из тела до мысли — мысли нет", _message() == "", _message())


## Новый забег начинает счёт заново; загруженный — помнит уже носимые тела.
func _check_new_run() -> void:
	# Загрузка: в записи забега тело уже занято — мысль его не повторяется.
	var resumed := RS_RunStats.new()
	resumed.note_body(WALKER_SCENE, &"BODY_WALKER")
	RunStats.current = resumed
	_observer._on_complex_entered(null)
	_clear_message()
	_capture(WALKER_SCENE)
	await get_tree().create_timer(WAIT).timeout
	_check("загруженный забег не повторяет мысль уже носимого тела", _message() == "", _message())

	# Новый забег: то же тело звучит снова.
	RunStats.current = RS_RunStats.new()
	_observer._on_complex_entered(null)
	_clear_message()
	_capture(WALKER_SCENE)
	await get_tree().create_timer(WAIT).timeout
	_check("в новом забеге мысль тела звучит снова", _message() == "THOUGHT_BODY_WALKER", _message())


## Захват тела со сценой [param scene_path]: душа получает C_Embodied и событие.
func _capture(scene_path: String) -> void:
	if _soul.has_component(C_Embodied):
		_soul.remove_component(C_Embodied)
	var embodied := C_Embodied.new()
	embodied.body_scene_path = scene_path
	_soul.add_component(embodied)
	ECS.world.emit_event(&"body_snatched", _soul)


func _message() -> String:
	var message := _soul.get_component(C_ScreenMessage) as C_ScreenMessage
	return message.text if message else ""


func _clear_message() -> void:
	if _soul.has_component(C_ScreenMessage):
		_soul.remove_component(C_ScreenMessage)
