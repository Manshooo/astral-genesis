# res://dev/debug_overlay.gd
## Отладочный оверлей: горячие клавиши, чтобы смотреть механику, не проходя ради
## неё забег. Экран навыков открывается где угодно, слой меняется телепортом,
## распад БФЖ выключается; очки навыков, эссенция Архитектора и перенос в
## уникальную комнату (хаб, выход, Архитектор) — из меню отладки
## (dev/debug_menu.gd).
##
## Повод: чтобы взглянуть на правку в дереве навыков, надо было запустить игру,
## бегать пару минут ради очков и только потом открыть экран. Цена взгляда была
## выше цены самой правки, и это решало, какие правки вообще делаются.
##
## Почему он лежит в dev/, а не в src/. Собранной игре читы не нужны, и `dev/*`
## исключён из экспорта — значит в релизе этого файла просто нет. Отсюда способ
## подключения: мир грузит оверлей ПО ПУТИ и только если путь существует (см.
## src/world/main.gd), а не через preload. Отсутствие обязано означать «читов
## нет», а не «игра не запускается» — тем же правилом живёт byProd, см.
## how-to/Звук.md.
##
## Клавиши идут МИМО InputMap намеренно. Действие в InputMap попадает в настройки
## управления и предлагается игроку к переназначению — а чит не управление, ему
## там не место; заодно не приходится думать, что делает кодек ребайндинга с
## действием, которого в релизе нет.
##
## Шпаргалка на экране строится ИЗ ТОЙ ЖЕ таблицы, что и обработчик нажатий,
## поэтому подпись не может разойтись с тем, что клавиша делает — а разойдясь,
## она врала бы молча. Строка-образец лежит в сцене, копии делает код: тем же
## приёмом, что деления рангов на карточке навыка.
extends CanvasLayer

## Сколько очков даёт одно нажатие. Десяток — это два-три ранга: хватает
## проверить покупку и следующий шаг дерева, но не открывает его целиком. Открыв
## всё разом, теряешь ровно то, ради чего дерево и смотрят, — серый предпросмотр
## и появление новой ветки.
const POINTS_PER_PRESS := 10
## Эссенция — по одной, как её даёт встреча с Архитектором
## (RS_GameConfig.architect_essence_reward). Дерево Архитектора крошечное и
## дешёвое (карта — 1/1/2/2), и пачка перепрыгивала бы уровни карты, которые как
## раз и смотрят по одному.
const ESSENCE_PER_PRESS := 1

## Глубина РАСТЁТ вниз (RS_LevelGraph: поверхность — 0, дом — 3), поэтому «ниже»
## это +1. Знак тут легко перепутать, и перепутанный он не падает, а увозит на
## поверхность вместо низа.
const STEP_DOWN := 1
const STEP_UP := -1

## Меню отладки — вне ряда F-клавиш: F9–F12 при запуске из редактора забирает
## его отладчик (см. dev/debug_menu.gd). Клавиша под Esc — привычное место
## отладочной консоли; на русской раскладке это «ё», поэтому сверяется и
## физическая клавиша (см. _unhandled_key_input).
const MENU_KEY := KEY_QUOTELEFT
## preload здесь законен: меню лежит в dev/ рядом с оверлеем и уходит из экспорта
## вместе с ним — «нет одного без другого» не бывает.
const MENU_SCENE := preload("res://dev/debug_menu.tscn")

@onready var _panel: PanelContainer = %Panel
@onready var _keys: VBoxContainer = %Keys
@onready var _status: Label = %Status
@onready var _report: Label = %Report
@onready var _report_timer: Timer = %ReportTimer

## Клавиша → что она делает и как называется в шпаргалке. Собирается в _ready, а
## не инициализатором поля: Callable на собственный метод до готовности узла
## взять неоткуда.
var _actions: Array[Dictionary] = []
## Начисления валюты — кнопками раздела «Прокачка» в меню отладки, а не
## клавишами. Жмут их пачкой, пока копят на нужный ранг, а клавиш в ряду F уже
## не хватает (см. MENU_KEY). Меню строит кнопку на каждую запись и шлёт её
## номер обратно — подпись берётся отсюда же, как в шпаргалке.
var _grants: Array[Dictionary] = []

var _immortal := false
## Открытое меню отладки; повторная клавиша второе не открывает.
var _menu: Control


func _ready() -> void:
	# Читы обязаны работать и в меню паузы: там как раз и разглядывают то, что
	# иначе бежит.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# F5 в ряду пропущен: он занят встроенным действием ui_filedialog_refresh, а
	# чит, совпавший с действием InputMap, срабатывал бы вместе с ним. Дырку
	# держит ассерт в debug_overlay_check — заполнить её «для красоты» не выйдет
	# молча. F2 свободна: очки уехали в меню, а остальные клавиши не сдвинуты,
	# чтобы не переучивать руки.
	_actions = [
		{"key": KEY_F1, "label": "свернуть панель", "call": _toggle_panel},
		{"key": KEY_F3, "label": "дерево навыков", "call": _open_skill_tree},
		{"key": KEY_F4, "label": "бессмертие", "call": _toggle_immortal},
		{"key": KEY_F6, "label": "слой ниже", "call": _travel_down},
		{"key": KEY_F7, "label": "слой выше", "call": _travel_up},
		{"key": KEY_F8, "label": "сбросить дерево", "call": _reset_skills},
		{"key": MENU_KEY, "label": "меню отладки", "call": _open_menu},
	]
	_grants = [
		{"title": "Очки навыков +%d" % POINTS_PER_PRESS, "call": _add_points},
		{"title": "Эссенция Архитектора +%d" % ESSENCE_PER_PRESS, "call": _add_essence},
	]
	_build_rows()

	_report.text = ""
	_report_timer.timeout.connect(func() -> void: _report.text = "")


## Значения бегут непрерывно (запас, глубина, очки), поэтому опрашиваем каждый
## кадр — как это делает HUD: событийная модель тут проигрывает поллингу.
func _process(_delta: float) -> void:
	var player := _get_player()
	if _immortal and player != null:
		_refill(player)
	_status.text = _status_text()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	for action in _actions:
		if event.keycode != action["key"] and event.physical_keycode != action["key"]:
			continue
		action["call"].call()
		get_viewport().set_input_as_handled()
		return


## Имя клавиши берётся у движка, а не пишется второй раз рядом с keycode: две
## записи одного и того же расходятся, и расходятся именно в шпаргалке.
func _build_rows() -> void:
	var template: HBoxContainer = _keys.get_child(0)
	for i in _actions.size():
		var row: HBoxContainer = template if i == 0 else template.duplicate()
		if i > 0:
			_keys.add_child(row)
		row.get_node("Key").text = OS.get_keycode_string(_actions[i]["key"])
		row.get_node("Action").text = _actions[i]["label"]


## Сид и номер сборки — чтобы раскладку, на которой что-то нашлось или
## сломалось, можно было назвать и воспроизвести: один и тот же сид на другом
## коммите генератора даёт другой комплекс.
func _status_text() -> String:
	var depth := "—"
	if RunManager.current_depth != RunManager.NO_DEPTH:
		depth = str(RunManager.current_depth)
	return "слой %s · узел %s\nочки %d · эссенция %d · бессмертие %s\nсид мира %d · смертей %d\nсборка v%s" % [
		depth,
		RunManager.current_node_id if RunManager.current_node_id != &"" else "—",
		SkillManager.save.skill_points,
		ArchitectManager.save.skill_points,
		"вкл" if _immortal else "выкл",
		WorldSave.save.world_seed,
		WorldSave.save.death_count,
		ProjectSettings.get_setting("application/config/version"),
	]


## Уникальные комнаты конфига генерации — хаб, выход, Архитектор: кнопка меню на
## каждую, подпись из пресета. Из данных, а не списком здесь: новая уникальная
## комната попадает в меню без правки оверлея.
##
## Конфиг — базовый, а не снимок забега: меню открывается и без забега. Разойтись
## они могут лишь у забега, начатого до правки конфига, — тогда перенос честно
## скажет, что такой комнаты в комплексе нет.
func unique_rooms() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var config := GameConfig.config.world_gen
	if config == null:
		return result
	for unique: RS_UniqueRoom in config.unique_rooms:
		if unique == null or unique.preset == null or unique.preset.scene == null:
			continue
		result.append({"title": unique.preset.display_name, "scene_path": unique.preset.scene.resource_path})
	return result


# --- Сами читы ---------------------------------------------------------------


func _toggle_panel() -> void:
	_panel.visible = not _panel.visible


func _add_points() -> void:
	SkillManager.add_skill_points(POINTS_PER_PRESS)
	_say("+%d очков" % POINTS_PER_PRESS)


## Эссенция идёт тем же add_skill_points, что и очки, но у ArchitectManager:
## валюта у обоих деревьев лежит в одном поле их СВОЕГО сейва.
func _add_essence() -> void:
	ArchitectManager.add_skill_points(ESSENCE_PER_PRESS)
	_say("+%d эссенции" % ESSENCE_PER_PRESS)


## Дерево открывается напрямую через UIManager, минуя терминал в хабе: смысл
## оверлея в том, чтобы смотреть экран там, где стоишь.
func _open_skill_tree() -> void:
	UIManager.open_skill_tree(SkillManager, SkillManager.SKILL_TREE)


## Экран в стеке UIManager с блоком ввода — как дерево навыков: курсор, Esc и
## возврат управления приходят оттуда, а не пишутся здесь второй раз.
func _open_menu() -> void:
	if is_instance_valid(_menu):
		return
	_menu = MENU_SCENE.instantiate()
	UIManager.push_blocking_screen(_menu)
	var titles: Array[String] = []
	for grant in _grants:
		titles.append(grant["title"])
	_menu.setup(unique_rooms(), titles)
	_menu.travel_requested.connect(_on_menu_travel)
	_menu.grant_requested.connect(_on_menu_grant)


## Начисление меню не закрывает, в отличие от переноса: копят пачкой, а итог
## виден сразу — строкой оверлея поверх меню и счётчиком на панели.
func _on_menu_grant(index: int) -> void:
	_grants[index]["call"].call()


## Меню закрывается ДО переноса: закрытие возвращает захват курсора и снимает
## блок ввода, а перенос в другой слой пересобирает мир — пусть он застанет
## игрока уже с управлением.
func _on_menu_travel(scene_path: String, title: String) -> void:
	UIManager.close_top()
	_travel_to_room(scene_path, title)


func _toggle_immortal() -> void:
	_immortal = not _immortal
	_say("бессмертие %s" % ("вкл" if _immortal else "выкл"))


func _reset_skills() -> void:
	SkillManager.reset()
	_say("дерево обнулено")


func _travel_down() -> void:
	_travel(STEP_DOWN)


func _travel_up() -> void:
	_travel(STEP_UP)


## Телепорт в первый узел соседнего слоя. RunManager.travel_to соседство рёбер не
## проверяет — грузит слой и ставит игрока в комнату, — поэтому годится как чит
## без единой строчки специально для него.
func _travel(step: int) -> void:
	if RunManager.current_graph == null:
		_say("забег не запущен")
		return

	var target_depth := RunManager.current_depth + step
	var nodes := RunManager.current_graph.get_nodes_by_depth(target_depth)
	if nodes.is_empty():
		_say("глубины %d в комплексе нет" % target_depth)
		return

	RunManager.travel_to(nodes[0].id)
	_say("слой %d" % target_depth)


## Перенос в комнату по её сцене — тем же RunManager.travel_to, что и смена слоя.
func _travel_to_room(scene_path: String, title: String) -> void:
	if RunManager.current_graph == null:
		_say("забег не запущен")
		return
	var target := next_room(RunManager.current_graph, scene_path, RunManager.current_node_id)
	if target == null:
		_say("%s: в этом комплексе нет" % title)
		return
	RunManager.travel_to(target.id)
	_say("%s · слой %d" % [title, target.depth])


## Следующая после [param current_id] комната со сценой [param scene_path], по
## кругу. Комнат с одной сценой бывает несколько (выходов, например), и повторное
## нажатие обязано вести в следующую, а не в ту же самую. null — такой нет.
static func next_room(graph: RS_LevelGraph, scene_path: String, current_id: StringName) -> RS_LevelNode:
	var rooms: Array[RS_LevelNode] = []
	for node_data: RS_LevelNode in graph.nodes.values():
		if node_data.room_scene_path == scene_path:
			rooms.append(node_data)
	if rooms.is_empty():
		return null
	var at := -1
	for i in rooms.size():
		if rooms[i].id == current_id:
			at = i
	return rooms[(at + 1) % rooms.size()]


## Бессмертие держится ПОДЛИВАНИЕМ обоих карманов каждый кадр, а не снятием
## S_Lifespan: система общая на все души, и выключенная ради игрока она заодно
## заморозила бы распад тел вокруг — то есть подменила бы проверяемую механику.
## Запись в поля компонентов правило v9 не нарушает: оно про структурные
## изменения, а не про значения.
func _refill(player: Entity) -> void:
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life != null:
		life.current = life.effective_max(player)
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	if decay != null:
		decay.remaining = decay.effective_maximum(player)


func _say(text: String) -> void:
	_report.text = text
	_report_timer.start()


func _get_player() -> Entity:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()
