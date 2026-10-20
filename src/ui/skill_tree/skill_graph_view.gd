# res://src/ui/skill_tree/skill_graph_view.gd
## Граф дерева навыков — нейросеть вокруг ядра души (§9 «Меню — спека»): нейроны, синапсы-требования, подписи веток, панорама и зум. Показывает изученное, доступное (is_revealed) и ровно один шаг за ним — пунктирным
## предпросмотром (is_previewed); дальше для игрока дерева нет (решение 02.10). Место скрытого нейрона закреплено (раскладка SkillGraphLayout по всему дереву) — двигается только камера. Синапс — там, где менеджер
## проверяет SKILL_RANK (сумма рангов ветки синапсов не даёт — веер был бы шумом); от ядра — к корням. Нажатие нейрона выбирает навык, покупка — кнопкой карточки.
class_name UI_SkillGraph
extends Control

## Выбрали нейрон — мышью или фокусом с клавиатуры.
signal skill_selected(id: StringName)

@export_group("Панорама")
@export var zoom_min := 0.45
@export var zoom_max := 1.6
@export var zoom_step := 1.12
@export var fit_padding := 48.0
## Длительность наведения камеры на новое.
@export var fit_duration := 0.35

## Знак комплекса под деревом Архитектора: улучшения мира растут на нём (§9).
const SIGN_TEXTURE := preload("res://assets/ui/menu/x16_sign.svg")
## Знак ×2.2 от поля 250, полупрозрачный — фон, не узор.
const SIGN_SIZE := 550.0
const SIGN_ALPHA := 0.07
## Ядро души в центре сети: точка как у прицела HUD и дышащий ореол.
const CORE_RADIUS := 4.0
const BREATH_PERIOD := 3.2
## Нейроны не дальше этого от края кадра при вписывании — под подписи.
const LABEL_MARGIN := Vector2(150.0, 40.0)

## Нейроны и подписи веток — экземплярами своих сцен («Конвенции проекта» §7).
const NEURON_SCENE := preload("res://src/ui/skill_tree/skill_neuron.tscn")
const BRANCH_LABEL_SCENE := preload("res://src/ui/skill_tree/branch_label.tscn")

var _manager
var _tree_data: RS_SkillTree
var _layout: SkillGraphLayout

@onready var _canvas: Control = %Canvas
@onready var _sign: TextureRect = %Sign
@onready var _core: Control = %Core
@onready var _links_host: Control = %Links
@onready var _labels_host: Control = %BranchLabels
@onready var _nodes_host: Control = %Nodes

var _nodes: Dictionary = {}  ## StringName -> UI_SkillNeuron
var _links: Dictionary = {}  ## "требование→навык" -> UI_SkillSynapse
var _selected: StringName = &""

var _panning := false
var _fitted := false
var _fit_tween: Tween

## Отдельным свойством, не _canvas.scale: масштаб твиним как число вместе с позицией.
var zoom: float = 1.0:
	set = _set_zoom


func _ready() -> void:
	resized.connect(_on_resized)
	_core.draw.connect(_draw_core)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_core.queue_redraw()


## Сеть дерева с прокачкой manager; зовётся и при смене вкладки — старая сносится целиком. [param show_sign] — знак комплекса (Архитектор).
func setup(manager, tree_data: RS_SkillTree, show_sign: bool = false) -> void:
	_manager = manager
	_tree_data = tree_data
	_layout = SkillGraphLayout.build(tree_data)
	for host in [_links_host, _labels_host, _nodes_host]:
		for child in host.get_children():
			child.queue_free()
	_nodes.clear()
	_links.clear()
	_selected = &""
	_fitted = false
	_sign.visible = show_sign
	_sign.texture = SIGN_TEXTURE
	_sign.size = Vector2(SIGN_SIZE, SIGN_SIZE)
	_sign.position = -_sign.size / 2.0
	_sign.modulate = Color(UI_MenuStyle.TEXT, SIGN_ALPHA)
	_build_branch_labels()
	refresh()


func _build_branch_labels() -> void:
	for branch in _layout.branches:
		var label: Label = BRANCH_LABEL_SCENE.instantiate()
		label.text = tr(_tree_data.branch_display_name(branch["branch"]))
		label.set_meta(&"branch", branch["branch"])
		_labels_host.add_child(label)
		label.size = label.get_combined_minimum_size()
		label.position = (branch["label"] as Vector2) - label.size / 2.0


## Пересобрать сеть под текущее состояние; нейроны не удаляются — показанный остаётся показанным.
func refresh() -> void:
	if _tree_data == null:
		return
	var appeared := false
	for def in _tree_data.skills:
		if def == null:
			continue
		var previewed: bool = not _manager.is_revealed(def.id)
		if previewed and not _manager.is_previewed(def.id):
			continue
		var skill_node: UI_SkillNeuron = _nodes.get(def.id)
		if skill_node == null:
			skill_node = _create_neuron(def)
			appeared = true
		skill_node.refresh(_manager.get_rank(def.id), _manager.can_unlock(def.id), previewed)
	_update_links()
	_update_branch_labels()
	if appeared:
		_request_fit(_fitted)


func _create_neuron(def: RS_SkillDefinition) -> UI_SkillNeuron:
	var skill_node: UI_SkillNeuron = NEURON_SCENE.instantiate()
	_nodes_host.add_child(skill_node)
	var center: Vector2 = _layout.positions.get(def.id, Vector2.ZERO)
	skill_node.setup(def, _label_side(def))
	skill_node.position = center - skill_node.size / 2.0
	skill_node.pressed.connect(select.bind(def.id))
	skill_node.focus_entered.connect(select.bind(def.id))
	skill_node.selected = def.id == _selected
	_nodes[def.id] = skill_node
	return skill_node


## Подпись — наружу сети: у ветви вверх/вниз сбоку (влево, если нейрон левее ядра); у растущей вбок — под нейроном (иначе легла бы на потомков).
func _label_side(def: RS_SkillDefinition) -> UI_SkillNeuron.LabelSide:
	var direction := Vector2.UP
	for branch in _layout.branches:
		if branch["branch"] == def.branch:
			direction = Vector2.from_angle(branch["angle"])
	if absf(direction.x) > 0.6:
		return UI_SkillNeuron.LabelSide.BELOW
	var center: Vector2 = _layout.positions.get(def.id, Vector2.ZERO)
	return UI_SkillNeuron.LabelSide.LEFT if center.x < -0.5 else UI_SkillNeuron.LabelSide.RIGHT


## Выбрать навык: подсветить нейрон и сообщить экрану.
func select(id: StringName) -> void:
	if not _nodes.has(id):
		return
	_selected = id
	for key in _nodes:
		(_nodes[key] as UI_SkillNeuron).selected = key == id
	skill_selected.emit(id)


func selected_id() -> StringName:
	return _selected


func neuron(id: StringName) -> UI_SkillNeuron:
	return _nodes.get(id)


## Первый навык при открытии: что можно купить сейчас, иначе первый показанный.
func default_selection() -> StringName:
	var first: StringName = &""
	for def in _tree_data.skills:
		if def == null or not _nodes.has(def.id):
			continue
		if first == &"":
			first = def.id
		if _manager.can_unlock(def.id):
			return def.id
	return first


## Отклик открытия ранга: кольцо от нейрона и прорисовка синапсов к нему.
func play_unlock_effect(id: StringName) -> void:
	var target: UI_SkillNeuron = _nodes.get(id)
	if target != null:
		target.play_unlock()
	if _manager.get_rank(id) != 1:
		return
	for key in _links:
		if String(key).ends_with("→" + String(id)):
			(_links[key] as UI_SkillSynapse).play_fresh()


func _update_branch_labels() -> void:
	for label in _labels_host.get_children():
		var any := false
		for def in _tree_data.get_branch_skills(label.get_meta(&"branch")):
			if _nodes.has(def.id):
				any = true
				break
		label.visible = any


## Синапс — где менеджер проверяет SKILL_RANK и оба нейрона показаны; от ядра — к корням веток.
func _update_links() -> void:
	for def in _tree_data.skills:
		if def == null or not _nodes.has(def.id):
			continue
		var state := _link_state(def)
		var has_parent := false
		for req in def.requires:
			if req == null or req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			has_parent = true
			if _nodes.has(req.target_skill):
				_link(String(req.target_skill), def, state)
		if not has_parent:
			_link("", def, state)


func _link(from_id: String, def: RS_SkillDefinition, state: UI_SkillSynapse.State) -> void:
	var key := "%s→%s" % [from_id, def.id]
	var link: UI_SkillSynapse = _links.get(key)
	if link == null:
		link = UI_SkillSynapse.new()
		link.seed_value = float(_links.size()) * 1.7 + 0.3
		_links_host.add_child(link)
		_links[key] = link
	var from: Vector2 = _layout.positions.get(StringName(from_id), Vector2.ZERO) if from_id != "" else Vector2.ZERO
	link.connect_points(from, _layout.positions.get(def.id, Vector2.ZERO), state)


func _link_state(def: RS_SkillDefinition) -> UI_SkillSynapse.State:
	if _manager.get_rank(def.id) > 0:
		return UI_SkillSynapse.State.LIT
	if _manager.requirements_met(def.id):
		return UI_SkillSynapse.State.AVAILABLE
	return UI_SkillSynapse.State.LOCKED


## Ядро — душа: точка прицела HUD и дышащий ореол (§7).
func _draw_core() -> void:
	var k := 0.5 + 0.5 * sin(TAU * UI_HudMood.now() / BREATH_PERIOD)
	_core.draw_circle(Vector2.ZERO, 11.0 * lerpf(0.92, 1.08, k), Color(UI_HudMood.SOUL, 0.10 + 0.08 * k))
	_core.draw_circle(Vector2.ZERO, CORE_RADIUS, UI_HudMood.DOT)


# --- Панорама и зум ---


## Границы показанного плюс поля под подписи: камера наводится на видимое.
func _revealed_bounds() -> Rect2:
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	for id in _nodes:
		var center: Vector2 = _layout.positions[id]
		bounds = bounds.expand(center)
	return bounds.grow_individual(LABEL_MARGIN.x, LABEL_MARGIN.y, LABEL_MARGIN.x, LABEL_MARGIN.y)


func _set_zoom(value: float) -> void:
	zoom = clampf(value, zoom_min, zoom_max)
	if _canvas != null:
		_canvas.scale = Vector2(zoom, zoom)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(event.position, zoom_step)
					accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(event.position, 1.0 / zoom_step)
					accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				# Тащить можно за пустое место: до _gui_input графа событие доходит, если его не забрал нейрон.
				_panning = event.pressed
				accept_event()
	elif event is InputEventMouseMotion and _panning:
		# Отпускание могло уйти нейрону — сверяемся с маской кнопок.
		if (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)) == 0:
			_panning = false
			return
		_canvas.position += event.relative
		_stop_fit_tween()
		accept_event()


## Зум «в курсор»: точка под мышью остаётся на месте.
func _zoom_at(pivot: Vector2, factor: float) -> void:
	_stop_fit_tween()
	var previous := zoom
	zoom = zoom * factor
	if is_equal_approx(previous, zoom):
		return
	_canvas.position = pivot - (pivot - _canvas.position) * (zoom / previous)


func _on_resized() -> void:
	if not _fitted:
		_request_fit(false)


## Кадр ожидания намеренный: сразу после setup() размер контрола нулевой.
func _request_fit(animated: bool) -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_fit(animated)


func _fit(animated: bool) -> void:
	var content := _revealed_bounds()
	if content.size.x <= 0.0 or content.size.y <= 0.0:
		return
	var available := size - Vector2(fit_padding, fit_padding) * 2.0
	if available.x <= 0.0 or available.y <= 0.0:
		return
	# Потолок 1.0: единственный нейрон не раздувается на весь экран.
	var target_zoom := clampf(
		minf(available.x / content.size.x, available.y / content.size.y), zoom_min, 1.0
	)
	var target_position := size * 0.5 - content.get_center() * target_zoom
	_fitted = true

	_stop_fit_tween()
	if not animated:
		zoom = target_zoom
		_canvas.position = target_position
		return
	_fit_tween = create_tween().set_parallel()
	_fit_tween.tween_property(self, "zoom", target_zoom, fit_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fit_tween.tween_property(_canvas, "position", target_position, fit_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_fit_tween() -> void:
	if _fit_tween != null and _fit_tween.is_valid():
		_fit_tween.kill()
	_fit_tween = null
