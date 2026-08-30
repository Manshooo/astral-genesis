extends Node
## Проверка отладочного оверлея (dev/debug_overlay.gd): читы делают то, что
## обещает шпаргалка, а сам оверлей не уезжает в собранную игру.
## Запускать: godot --headless dev/debug_overlay_check.tscn
##
## Оверлей — инструмент, и ломается он тише всего остального: неверный путь в
## main.gd или потерянный `dev/*` в фильтре экспорта не дают ни ошибки, ни
## предупреждения. В первом случае читов просто нет («а раньше работало»), во
## втором они, наоборот, есть — в релизе у игрока.
##
## Клавиши здесь не подставляются в обход обработчика: проверка синтезирует
## InputEventKey и зовёт _unhandled_key_input, то есть проходит ровно тем путём,
## каким идёт живое нажатие. Позвав метод чита напрямую, она бы не заметила
## самого частого промаха — клавиши, до которой таблица не доводит.
##
## SkillManager.save на время проверки подменяется и возвращается на месте:
## начисление очков ПИШЕТ в user://, и прогон не должен трогать прогресс игрока.

const OVERLAY_SCENE := preload("res://dev/debug_overlay.tscn")
## Тот же путь, по которому оверлей ищет мир. Литерал здесь намеренный: проверка
## обязана сверить ДВА независимых написания пути, а взяв константу из main.gd,
## она сверяла бы его с самим собой.
const OVERLAY_PATH := "res://dev/debug_overlay.tscn"

var _ok := 0
var _fail := 0
var _original_save: PlayerSkillSave


func _ready() -> void:
	_original_save = SkillManager.save
	SkillManager.save = _original_save.duplicate()
	SkillManager.save.ranks = _original_save.ranks.duplicate()

	await _run()

	SkillManager.save = _original_save
	SkillManager._save()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_check_packaging()

	var world := World.new()
	add_child(world)
	ECS.world = world
	var lifespan := S_Lifespan.new()
	lifespan.group = "gameplay"
	world.add_system(lifespan)

	var overlay: CanvasLayer = OVERLAY_SCENE.instantiate()
	add_child(overlay)
	await get_tree().process_frame

	_check_cheatsheet(overlay)
	_check_keys(overlay)
	await _check_immortality(overlay, world)
	_check_points(overlay)

	overlay.queue_free()
	world.queue_free()


# --- 1. Оверлей не должен уезжать в игру и обязан доезжать до мира -----------


func _check_packaging() -> void:
	# Мир грузит оверлей ПО СТРОКЕ, а не preload'ом, и промах по ней движок не
	# видит: ResourceLoader.exists() просто вернёт false, и читов не будет.
	_check(
		"путь оверлея в main.gd ведёт на существующую сцену",
		ResourceLoader.exists(OVERLAY_PATH),
		"нет ресурса по пути %s" % OVERLAY_PATH
	)

	# Обратная сторона того же: путь исключён из экспорта, и это ЕДИНСТВЕННОЕ,
	# что держит читы вне собранной игры. Фильтр правится в редакторе через
	# диалог экспорта, где `dev/*` теряется одним кликом и молча.
	var file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	if file == null:
		_check("export_presets.cfg читается", false, "не открылся")
		return

	var filters: Array[String] = []
	for line in file.get_as_text().split("\n"):
		if line.begins_with("exclude_filter="):
			filters.append(line)
	file.close()

	_check("в экспорте есть пресеты с фильтром", not filters.is_empty(), "ни одного exclude_filter")
	for filter in filters:
		_check(
			"пресет экспорта исключает dev/*",
			filter.contains("dev/*"),
			"фильтр без dev/*: %s" % filter
		)


# --- 2. Шпаргалка не врёт ----------------------------------------------------


func _check_cheatsheet(overlay: CanvasLayer) -> void:
	var keys: VBoxContainer = overlay.get_node("%Keys")
	var actions: Array = overlay._actions

	# Первым ассертом — что таблица вообще есть: пустая позеленила бы всё
	# остальное вхолостую.
	_check("таблица читов не пуста", not actions.is_empty(), "ни одного действия")
	_check(
		"шпаргалка: строка на каждый чит",
		keys.get_child_count() == actions.size(),
		"строк %d, читов %d" % [keys.get_child_count(), actions.size()]
	)

	var blank := 0
	for row in keys.get_children():
		var key_label: Label = row.get_node("Key")
		var action_label: Label = row.get_node("Action")
		if key_label.text.is_empty() or action_label.text.is_empty():
			blank += 1
	_check("шпаргалка: у каждой строки есть клавиша и подпись", blank == 0, "пустых строк: %d" % blank)


func _check_keys(overlay: CanvasLayer) -> void:
	var seen: Array[int] = []
	var doubled: Array[String] = []
	for action in overlay._actions:
		var key: int = action["key"]
		if seen.has(key):
			doubled.append(OS.get_keycode_string(key))
		seen.append(key)
	# Вторая запись на ту же клавишу не падает — до неё просто не доходит
	# перебор, и чит выглядит «не работает».
	_check("клавиши читов не повторяются", doubled.is_empty(), "дубли: %s" % ", ".join(doubled))

	# Чит, совпавший с игровым действием, срабатывал бы вместе с ним — и в
	# настройках управления игрок увидел бы клавишу, которая делает что-то ещё.
	var clashes: Array[String] = []
	for action_name in InputMap.get_actions():
		for event in InputMap.action_get_events(action_name):
			if not event is InputEventKey:
				continue
			for cheat in overlay._actions:
				var key: int = cheat["key"]
				if event.keycode == key or event.physical_keycode == key:
					clashes.append("%s ↔ %s" % [OS.get_keycode_string(key), action_name])
	_check(
		"клавиши читов не пересекаются с InputMap",
		clashes.is_empty(),
		"совпадения: %s" % ", ".join(clashes)
	)

	# Глубина растёт ВНИЗ (поверхность — 0), и перепутанный знак не падает, а
	# увозит на поверхность вместо низа. Сверяется с самим графом, а не с
	# числом в проверке: поменяется соглашение — ассерт скажет об этом здесь.
	_check(
		"«слой ниже» ведёт вглубь комплекса",
		RS_LevelGraph.SURFACE_DEPTH < RS_LevelGraph.HOME_DEPTH and overlay.STEP_DOWN > 0,
		"поверхность %d, дом %d, шаг вниз %d"
		% [RS_LevelGraph.SURFACE_DEPTH, RS_LevelGraph.HOME_DEPTH, overlay.STEP_DOWN]
	)


# --- 3. Читы делают то, что написано -----------------------------------------


## Бессмертие проверяется НАБЛЮДАЕМЫМ распадом, а не флагом: флаг ставится одной
## строкой и всегда «работает», а сам чит подливает карманы в _process, и
## промахнуться можно и мимо кармана, и мимо кадра.
func _check_immortality(overlay: CanvasLayer, world: World) -> void:
	var player := _spawn_player(world, true)
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	var full := decay.effective_maximum(player)

	# Контроль: без чита карман обязан убывать. Без этого ассерта следующий
	# зеленел бы и на сломанном S_Lifespan — «не убыло» было бы правдой зря.
	ECS.process(1.0, "gameplay")
	await get_tree().process_frame
	_check(
		"без чита карман тела убывает",
		decay.remaining < full,
		"остаток %.1f при максимуме %.1f" % [decay.remaining, full]
	)

	_press(overlay, KEY_F4)
	for i in 3:
		ECS.process(1.0, "gameplay")
		await get_tree().process_frame
	_check(
		"бессмертие держит карман тела полным",
		is_equal_approx(decay.remaining, full),
		"остаток %.1f при максимуме %.1f" % [decay.remaining, full]
	)

	# Развоплощённая душа платит из ДРУГОГО кармана, и подлить надо оба: чит,
	# забывший про C_Lifespan, во плоти выглядел бы работающим.
	world.remove_entity(player)
	var ghost := _spawn_player(world, false)
	var life := ghost.get_component(C_Lifespan) as C_Lifespan
	var soul_full := life.effective_max(ghost)
	for i in 3:
		ECS.process(1.0, "gameplay")
		await get_tree().process_frame
	_check(
		"бессмертие держит полным и запас души",
		is_equal_approx(life.current, soul_full),
		"остаток %.1f при максимуме %.1f" % [life.current, soul_full]
	)

	_press(overlay, KEY_F4)
	world.remove_entity(ghost)


func _check_points(overlay: CanvasLayer) -> void:
	var before: int = SkillManager.save.skill_points
	_press(overlay, KEY_F2)
	_check(
		"клавиша очков начисляет ровно столько, сколько обещает подпись",
		SkillManager.save.skill_points == before + overlay.POINTS_PER_PRESS,
		"было %d, стало %d" % [before, SkillManager.save.skill_points]
	)


# --- Вспомогательное ---------------------------------------------------------


## Нажатие идёт через обработчик оверлея, а не мимо него: проверяется в том числе
## то, что таблица доводит клавишу до чита.
func _press(overlay: CanvasLayer, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	overlay._unhandled_key_input(event)


## Игрока оверлей ищет по C_PlayerInput — так же, как HUD и RunManager.
func _spawn_player(world: World, embodied: bool) -> Entity:
	var player := Entity.new()
	world.add_entity(player)
	player.add_component(C_PlayerInput.new())
	player.add_component(C_Lifespan.new())
	if embodied:
		player.add_component(C_BodyDecay.new())
	return player


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
