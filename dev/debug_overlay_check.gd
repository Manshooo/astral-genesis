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
## Сейвы SkillManager и ArchitectManager на время проверки подменяются и
## возвращаются на место: начисление очков и эссенции ПИШЕТ в user://, и прогон
## не должен трогать прогресс игрока.

const OVERLAY_SCENE := preload("res://dev/debug_overlay.tscn")
## Тот же путь, по которому оверлей ищет мир. Литерал здесь намеренный: проверка
## обязана сверить ДВА независимых написания пути, а взяв константу из main.gd,
## она сверяла бы его с самим собой.
const OVERLAY_PATH := "res://dev/debug_overlay.tscn"

var _ok := 0
var _fail := 0
var _original_save: PlayerSkillSave
var _original_architect_save: PlayerSkillSave


func _ready() -> void:
	_original_save = SkillManager.save
	SkillManager.save = _original_save.duplicate()
	SkillManager.save.ranks = _original_save.ranks.duplicate()
	_original_architect_save = ArchitectManager.save
	ArchitectManager.save = _original_architect_save.duplicate()
	ArchitectManager.save.ranks = _original_architect_save.ranks.duplicate()

	await _run()

	SkillManager.save = _original_save
	SkillManager._save()
	ArchitectManager.save = _original_architect_save
	ArchitectManager._save()

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
	await _check_unique_rooms(overlay)
	await _check_immortality(overlay, world)
	_check_grants(overlay)

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
			# Действие с модификатором (у встроенного ui_swap_input_direction это
			# Ctrl+`) на голую клавишу не срабатывает: движок требует, чтобы его
			# модификаторы были зажаты. Читы жмутся без модификаторов — это не
			# пересечение.
			if (event as InputEventKey).get_modifiers_mask() != 0:
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
		RS_LevelGraph.DEPTHS[-1] < RS_LevelGraph.DEPTHS[0] and overlay.STEP_DOWN > 0,
		"поверхность %d, самый глубокий %d, шаг вниз %d"
		% [RS_LevelGraph.DEPTHS[-1], RS_LevelGraph.DEPTHS[0], overlay.STEP_DOWN]
	)


## Перенос в уникальные комнаты из меню отладки. Кнопки строятся из конфига
## генерации, а цель ищется по сцене узла графа — и промах в любом из двух мест
## молча оставляет «Комнату Архитектора» без Архитектора.
func _check_unique_rooms(overlay: CanvasLayer) -> void:
	var config := GameConfig.config.world_gen
	var uniques: Array[RS_UniqueRoom] = []
	for unique: RS_UniqueRoom in config.unique_rooms:
		if unique != null and unique.preset != null and unique.preset.scene != null:
			uniques.append(unique)

	# Меню открывается клавишей через стек UIManager — оттуда курсор и Esc.
	_press(overlay, overlay.MENU_KEY)
	var menu: Control = overlay._menu
	_check(
		"клавиша меню открывает меню отладки поверх игры с курсором",
		is_instance_valid(menu) and menu.is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"меню %s, курсор %d" % [is_instance_valid(menu), Input.mouse_mode]
	)
	if not is_instance_valid(menu):
		return

	var buttons: Array[String] = []
	for button: Button in menu.get_node("%Rooms").get_children():
		if button.visible:
			buttons.append(button.text)
	var titles: Array[String] = []
	for unique in uniques:
		titles.append(unique.preset.display_name)
	_check(
		"в разделе «Телепорт» по кнопке на каждую уникальную комнату конфига",
		not titles.is_empty() and buttons == titles,
		"кнопки %s, комнаты %s" % [buttons, titles]
	)

	_press(overlay, overlay.MENU_KEY)
	var menus := get_tree().root.find_children("*", "Control", false, false).filter(
		func(node: Node) -> bool: return node.scene_file_path == "res://dev/debug_menu.tscn"
	)
	_check("повторная клавиша второго меню не открывает", menus.size() == 1, "меню: %d" % menus.size())

	# Кнопка без забега: меню закрывается, а перенос говорит, что забега нет.
	RunManager.current_graph = null
	var room_button: Button = menu.get_node("%Rooms").get_child(0)
	room_button.pressed.emit()
	await get_tree().process_frame
	var report: Label = overlay.get_node("%Report")
	_check(
		"кнопка закрывает меню и без забега говорит, что забег не запущен",
		not is_instance_valid(menu) and report.text == "забег не запущен",
		"меню открыто: %s, сообщение «%s»" % [is_instance_valid(menu), report.text]
	)

	# Ищется по той же строке, что пишет генератор (RS_LevelGraph._place_unique_rooms):
	# разойдись они — перенос не найдёт комнату, которая в комплексе есть.
	var lost: Array[String] = []
	for run_seed in [1, 7, 42, 1234, 99991]:
		var generated := RS_LevelGraph.new().generate_run(
			run_seed, GameConfig.config.room_preset_library, config
		)
		for unique in uniques:
			if unique.chance < 1.0:
				continue
			var path := unique.preset.scene.resource_path
			if overlay.next_room(generated, path, &"") == null:
				lost.append("%s на сиде %d" % [unique.preset.display_name, run_seed])
	_check("перенос находит каждую уникальную комнату на пяти сидах", lost.is_empty(), ", ".join(lost))

	# Повторное нажатие ведёт в следующую комнату той же сцены, а не в ту же:
	# выходов в забеге бывает несколько.
	var graph := RS_LevelGraph.new()
	for pair in [[&"a", "x.tscn"], [&"b", "y.tscn"], [&"c", "x.tscn"]]:
		var node := RS_LevelNode.new()
		node.id = pair[0]
		node.room_scene_path = pair[1]
		graph.nodes[node.id] = node
	var first: RS_LevelNode = overlay.next_room(graph, "x.tscn", &"")
	var second: RS_LevelNode = overlay.next_room(graph, "x.tscn", &"a")
	var wrapped: RS_LevelNode = overlay.next_room(graph, "x.tscn", &"c")
	_check(
		"повторный перенос идёт по кругу по комнатам той же сцены",
		first.id == &"a" and second.id == &"c" and wrapped.id == &"a",
		"%s → %s → %s" % [first.id, second.id, wrapped.id]
	)
	_check(
		"комнаты, которой в графе нет, перенос не выдумывает",
		overlay.next_room(graph, "z.tscn", &"") == null,
		""
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


## Очки и эссенция — кнопками раздела «Прокачка» меню отладки. Кнопки жмутся
## сигналом pressed, то есть тем же путём, что клик: через сигнал меню и таблицу
## начислений оверлея, а не вызовом чита напрямую.
func _check_grants(overlay: CanvasLayer) -> void:
	_press(overlay, overlay.MENU_KEY)
	var menu: Control = overlay._menu
	if not is_instance_valid(menu):
		_check("меню отладки открылось для «Прокачки»", false, "меню нет")
		return

	var buttons: Array[Button] = []
	var texts: Array[String] = []
	for button: Button in menu.get_node("%Grants").get_children():
		if button.visible:
			buttons.append(button)
			texts.append(button.text)
	var titles: Array[String] = []
	for grant in overlay._grants:
		titles.append(grant["title"])
	_check(
		"в «Прокачке» по кнопке на каждое начисление, подписи из таблицы оверлея",
		titles.size() == 2 and texts == titles,
		"кнопки %s, таблица %s" % [texts, titles]
	)
	if buttons.size() != 2:
		UIManager.close_top()
		return

	var points_before: int = SkillManager.save.skill_points
	var essence_before: int = ArchitectManager.save.skill_points
	buttons[0].pressed.emit()
	_check(
		"кнопка очков начисляет ровно столько, сколько обещает подпись, и только очки",
		SkillManager.save.skill_points == points_before + overlay.POINTS_PER_PRESS
			and ArchitectManager.save.skill_points == essence_before,
		"очки %d → %d, эссенция %d → %d"
		% [points_before, SkillManager.save.skill_points, essence_before, ArchitectManager.save.skill_points]
	)
	buttons[1].pressed.emit()
	buttons[1].pressed.emit()
	# Эссенция — валюта ДРУГОГО дерева: легла не туда — экран Архитектора пуст,
	# а очки навыков молча растут.
	_check(
		"кнопка эссенции начисляет эссенцию Архитектору, а не очки навыков",
		ArchitectManager.save.skill_points == essence_before + overlay.ESSENCE_PER_PRESS * 2
			and SkillManager.save.skill_points == points_before + overlay.POINTS_PER_PRESS,
		"эссенция %d → %d" % [essence_before, ArchitectManager.save.skill_points]
	)
	_check("начисление меню не закрывает — копят пачкой",
		is_instance_valid(menu) and menu.is_inside_tree(), "")
	UIManager.close_top()


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
