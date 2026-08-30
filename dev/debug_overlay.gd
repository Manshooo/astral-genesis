# res://dev/debug_overlay.gd
## Отладочный оверлей: горячие клавиши, чтобы смотреть механику, не проходя ради
## неё забег. Экран навыков открывается где угодно и с любым числом очков, слой
## меняется телепортом, распад БФЖ выключается.
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

## Глубина РАСТЁТ вниз (RS_LevelGraph: поверхность — 0, дом — 3), поэтому «ниже»
## это +1. Знак тут легко перепутать, и перепутанный он не падает, а увозит на
## поверхность вместо низа.
const STEP_DOWN := 1
const STEP_UP := -1

@onready var _panel: PanelContainer = %Panel
@onready var _keys: VBoxContainer = %Keys
@onready var _status: Label = %Status
@onready var _report: Label = %Report
@onready var _report_timer: Timer = %ReportTimer

## Клавиша → что она делает и как называется в шпаргалке. Собирается в _ready, а
## не инициализатором поля: Callable на собственный метод до готовности узла
## взять неоткуда.
var _actions: Array[Dictionary] = []

var _immortal := false


func _ready() -> void:
	# Читы обязаны работать и в меню паузы: там как раз и разглядывают то, что
	# иначе бежит.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# F5 в ряду пропущен: он занят встроенным действием ui_filedialog_refresh, а
	# чит, совпавший с действием InputMap, срабатывал бы вместе с ним. Дырку
	# держит ассерт в debug_overlay_check — заполнить её «для красоты» не выйдет
	# молча.
	_actions = [
		{"key": KEY_F1, "label": "свернуть панель", "call": _toggle_panel},
		{"key": KEY_F2, "label": "очки навыков +%d" % POINTS_PER_PRESS, "call": _add_points},
		{"key": KEY_F3, "label": "дерево навыков", "call": _open_skill_tree},
		{"key": KEY_F4, "label": "бессмертие", "call": _toggle_immortal},
		{"key": KEY_F6, "label": "слой ниже", "call": _travel_down},
		{"key": KEY_F7, "label": "слой выше", "call": _travel_up},
		{"key": KEY_F8, "label": "сбросить дерево", "call": _reset_skills},
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
		if event.keycode != action["key"]:
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


func _status_text() -> String:
	var depth := "—"
	if RunManager.current_depth != RunManager.NO_DEPTH:
		depth = str(RunManager.current_depth)
	return "слой %s · узел %s\nочки %d · бессмертие %s" % [
		depth,
		RunManager.current_node_id if RunManager.current_node_id != &"" else "—",
		SkillManager.save.skill_points,
		"вкл" if _immortal else "выкл",
	]


# --- Сами читы ---------------------------------------------------------------


func _toggle_panel() -> void:
	_panel.visible = not _panel.visible


func _add_points() -> void:
	SkillManager.add_skill_points(POINTS_PER_PRESS)
	_say("+%d очков" % POINTS_PER_PRESS)


## Дерево открывается напрямую через UIManager, минуя терминал в хабе: смысл
## оверлея в том, чтобы смотреть экран там, где стоишь.
func _open_skill_tree() -> void:
	UIManager.open_skill_tree(SkillManager, SkillManager.SKILL_TREE)


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
