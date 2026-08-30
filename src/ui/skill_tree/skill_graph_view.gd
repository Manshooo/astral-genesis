# res://src/ui/skill_tree/skill_graph_view.gd
## Граф дерева навыков: карточки-узлы, связи-требования, панорама и зум.
##
## Показывает НЕ всё дерево, а изученное, следующее доступное
## (SkillManager.is_revealed) и ровно один шаг за ними — серым предпросмотром
## (SkillManager.is_previewed): игрок читает, куда ветка ведёт дальше, но купить
## это ещё не может. Дальше предпросмотра дерево для игрока не существует, и
## ветка, открывающаяся по сумме рангов, по-прежнему появляется целиком и сразу.
##
## Скрытый узел не рисуется, но МЕСТО за ним закреплено: раскладка считается по
## всему дереву разом (SkillGraphLayout), поэтому открытие соседа не двигает уже
## знакомые игроку карточки. Двигается только камера — и только тогда, когда
## новое иначе не поместилось бы в кадр.
##
## Связи берутся из требований: ребро существует ровно там, где SkillManager
## проверяет требование SKILL_RANK. Требование «сумма рангов в ветке» рёбер не
## даёт намеренно — оно про ветку целиком, и веер линий из всех её узлов
## сообщал бы не структуру, а шум.
##
## Что правится глазами и что кодом. Слои графа (полотно панорамы, дорожки,
## связи) лежат в skill_graph_view.tscn, карточка и дорожка ветки — своими
## сценами (skill_node_card.tscn, skill_lane.tscn), а размеры и цвета, которые
## нельзя нарисовать, вынесены в @export и правятся в инспекторе. Кодом остаётся
## только то, что зависит от данных: где стоит узел, что показано, куда идёт
## связь и какой прямоугольник заняла ветка.
class_name UI_SkillGraph
extends Control

## Нажали по карточке навыка. Что с этим делать — решает экран, граф не зовёт
## SkillManager.unlock сам: рисование и трата очков — разные обязанности.
signal skill_activated(id: StringName)

@export_group("Клетка")
@export var cell_gap := Vector2(68.0, 20.0)

@export_group("Дорожки")
## Насколько подложка дорожки выступает за крайние карточки ветки. Всё
## остальное в её виде — подложка, жёлоб, подпись — лежит в skill_lane.tscn.
@export var lane_padding := Vector2(18.0, 10.0)

@export_group("Панорама")
@export var zoom_min := 0.45
@export var zoom_max := 1.6
@export var zoom_step := 1.12
@export var fit_padding := 48.0
## Наведение камеры на новое. Единственная длительность, оставшаяся графу: она
## про движение кадра, а не про вид какого-то элемента — те живут в своих сценах.
@export var fit_duration := 0.35

## Сцена карточки-узла. Её же размер задаёт клетку сетки — см. _card_size().
const CARD_SCENE := preload("res://src/ui/skill_tree/skill_node_card.tscn")
## Сцена дорожки ветки. Её жёлоб задаёт левый отступ всей сетки — см. _lane_gutter().
const LANE_SCENE := preload("res://src/ui/skill_tree/skill_lane.tscn")
## Сцена связи-требования. Толщина, сглаживание и густота линии — в ней.
const LINK_SCENE := preload("res://src/ui/skill_tree/skill_link.tscn")

var _skill_manager
var _tree_data: RS_SkillTree
var _layout: SkillGraphLayout

## Размер клетки = размер карточки, и берётся он ИЗ ЕЁ СЦЕНЫ. Второе число
## здесь (@export на графе) означало бы, что карточку, растянутую в редакторе,
## сетка, связи и подложки дорожек считают по-старому.
var node_size := Vector2(196.0, 96.0)
## Левый жёлоб под подписи дорожек — тоже из сцены, см. _lane_gutter().
var lane_label_width := 136.0

@onready var _canvas: Control = %Canvas
@onready var _lanes_host: Control = %Lanes
@onready var _links_host: Control = %Links

var _nodes: Dictionary = {}  ## StringName -> UI_SkillNode
var _lanes: Dictionary = {}  ## StringName (ветка) -> UI_SkillLane
var _links: Dictionary = {}  ## "требование→навык" -> UI_SkillLink

var _panning := false
var _fitted := false
var _fit_tween: Tween

## Отдельным свойством, а не через _canvas.scale, чтобы масштаб можно было
## твинить как одно число: анимировать Vector2-масштаб и позицию раздельно
## значит ловить их рассинхрон в середине анимации.
var zoom: float = 1.0:
	set = _set_zoom


func _ready() -> void:
	resized.connect(_on_resized)


func setup(skill_manager, tree_data: RS_SkillTree) -> void:
	_skill_manager = skill_manager
	_tree_data = tree_data
	_layout = SkillGraphLayout.build(tree_data)
	node_size = _card_size()
	lane_label_width = _lane_gutter()
	_build_lanes()

	refresh()


## Клетка сетки — это карточка, поэтому её размер спрашивается у самой сцены
## карточки, а не хранится вторым числом в графе. Пробный экземпляр дешевле
## любой синхронизации руками: сцену правят в редакторе, и разъехаться нечему.
func _card_size() -> Vector2:
	var probe: Control = CARD_SCENE.instantiate()
	var probe_size := Vector2(
		maxf(probe.size.x, probe.custom_minimum_size.x),
		maxf(probe.size.y, probe.custom_minimum_size.y)
	)
	probe.free()
	return probe_size


## Тем же приёмом, что и клетка: ширину жёлоба под подписи держит сцена дорожки,
## а граф лишь отодвигает на неё карточки.
func _lane_gutter() -> float:
	var probe: UI_SkillLane = LANE_SCENE.instantiate()
	var width := probe.gutter_width()
	probe.free()
	return width


## Дорожка заводится на КАЖДУЮ ветку раскладки сразу и навсегда: ветка без
## показанных карточек просто спрятана. Создавать её в момент появления первой
## карточки значило бы решать одно и то же дважды — здесь и в refresh().
func _build_lanes() -> void:
	for lane in _layout.lanes:
		var branch_id: StringName = lane["branch"]
		var view: UI_SkillLane = LANE_SCENE.instantiate()
		_lanes_host.add_child(view)
		view.setup(_tree_data.branch_display_name(branch_id), _tree_data.branch_color(branch_id))
		view.visible = false
		_lanes[branch_id] = view


## Пересобрать граф под текущее состояние навыков. Узлы не удаляются никогда:
## показанная карточка остаётся показанной (см. SkillManager.is_revealed).
func refresh() -> void:
	if _tree_data == null:
		return

	var appeared := false
	for def in _tree_data.skills:
		if def == null:
			continue
		var previewed: bool = not _skill_manager.is_revealed(def.id)
		if previewed and not _skill_manager.is_previewed(def.id):
			continue
		var card: UI_SkillNode = _nodes.get(def.id)
		if card == null:
			card = _create_node(def)
			# Первая сборка — не «появление»: анимировать въезд десятка карточек
			# при открытии экрана значит показать анимацию вместо дерева.
			if _fitted:
				card.play_reveal()
			appeared = true
		card.refresh(
			_skill_manager.get_rank(def.id),
			_skill_manager.can_unlock(def.id),
			previewed,
			_requirement_hint(def)
		)

	_update_lanes()
	_update_links()
	if appeared:
		_request_fit(_fitted)


## Прямоугольник дорожки — по показанным карточкам её ветки, поэтому он и
## пересчитывается на каждом refresh(), а не выдаётся раз при сборке.
func _update_lanes() -> void:
	for lane in _layout.lanes:
		var view: UI_SkillLane = _lanes.get(lane["branch"])
		if view == null:
			continue
		var band := _lane_band(lane)
		view.visible = band.size.y > 0.0
		if not view.visible:
			continue
		view.position = band.position
		view.size = band.size


func play_unlock_effect(id: StringName) -> void:
	var card: UI_SkillNode = _nodes.get(id)
	if card != null:
		card.play_unlock_effect()


func _create_node(def: RS_SkillDefinition) -> UI_SkillNode:
	var card: UI_SkillNode = CARD_SCENE.instantiate()
	# В дерево сцены — ДО setup(): начинку карточки держат @onready-ссылки, а они
	# поднимаются только на входе в дерево.
	_canvas.add_child(card)
	card.setup(def, _tree_data.branch_color(def.branch))
	card.size = node_size
	card.pivot_offset = node_size * 0.5
	card.position = _cell_to_pixel(_layout.cells.get(def.id, Vector2i.ZERO))
	card.pressed.connect(_on_card_pressed.bind(def.id))
	_nodes[def.id] = card
	return card


func _on_card_pressed(id: StringName) -> void:
	skill_activated.emit(id)


## Требования словами — карточке-предпросмотру, чтобы серый узел объяснял, чем
## он открывается. Собирает граф, а не карточка: имена соседних навыков и веток
## лежат в дереве, а карточка знает только про себя.
func _requirement_hint(def: RS_SkillDefinition) -> String:
	var parts := PackedStringArray()
	for req in def.requires:
		if req == null:
			continue
		match req.type:
			RS_SkillRequirement.Type.SKILL_RANK:
				var target := _tree_data.get_definition(req.target_skill)
				var target_name := (
					target.display_name if target != null else String(req.target_skill)
				)
				parts.append("«%s» ранга %d" % [target_name, req.min_value])
			RS_SkillRequirement.Type.BRANCH_TOTAL_RANKS:
				parts.append(
					"%d рангов в ветке «%s»"
					% [req.min_value, _tree_data.branch_display_name(req.target_branch)]
				)
	return ", ".join(parts)


# --- Раскладка в пикселях ----------------------------------------------------


func _cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(
		lane_label_width + cell.x * (node_size.x + cell_gap.x),
		cell.y * (node_size.y + cell_gap.y)
	)


## Границы того, что реально показано, плюс жёлоб с подписями дорожек: камера
## наводится на видимое, а не на пустое место, забронированное под будущее.
func _revealed_bounds() -> Rect2:
	var bounds := Rect2()
	var first := true
	for id in _nodes:
		var card: UI_SkillNode = _nodes[id]
		var rect := Rect2(card.position, node_size)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if first:
		return Rect2()
	bounds.size.x += bounds.position.x
	bounds.position.x = 0.0
	return bounds


# --- Отрисовка дорожек и связей ----------------------------------------------


## Ребро есть ровно там, где SkillManager проверяет требование SKILL_RANK и обе
## карточки уже показаны. Связи, как и карточки, не удаляются: показанное
## остаётся показанным, поэтому существующие только обновляются.
func _update_links() -> void:
	for def in _tree_data.skills:
		if def == null or not _nodes.has(def.id):
			continue
		var target: UI_SkillNode = _nodes[def.id]
		for req in def.requires:
			if req == null or req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			if not _nodes.has(req.target_skill):
				continue
			var source: UI_SkillNode = _nodes[req.target_skill]
			var key := "%s→%s" % [req.target_skill, def.id]
			var link: UI_SkillLink = _links.get(key)
			if link == null:
				link = LINK_SCENE.instantiate()
				_links_host.add_child(link)
				_links[key] = link
			# Связь входит в карточку слева, а выходит справа: ветки лежат
			# дорожками, и требование через дорожку прямой линией резало бы
			# чужие карточки.
			link.connect_cards(
				source.position + Vector2(node_size.x, node_size.y * 0.5),
				target.position + Vector2(0.0, node_size.y * 0.5),
				_tree_data.branch_color(def.branch),
				target.previewed
			)


## Прямоугольник дорожки — по ПОКАЗАННЫМ карточкам ветки, а не по забронированным
## под неё клеткам. Место в раскладке закреплено за всем деревом, и подложка во
## всю его ширину означала бы полосу, уходящую в пустоту: игрок читает её как
## «здесь что-то есть», хотя там ничего нет и не показано. Левый край всё равно
## доводится до нуля — в жёлобе лежит подпись ветки, она часть дорожки.
func _lane_band(lane: Dictionary) -> Rect2:
	var band := Rect2()
	var first := true
	for def in _tree_data.get_branch_skills(lane["branch"]):
		var card: UI_SkillNode = _nodes.get(def.id)
		if card == null:
			continue
		var rect := Rect2(card.position, node_size)
		band = rect if first else band.merge(rect)
		first = false
	if first:
		return Rect2()

	band = band.grow_individual(0.0, lane_padding.y, lane_padding.x, lane_padding.y)
	band.size.x += band.position.x
	band.position.x = 0.0
	return band


# --- Панорама и зум ----------------------------------------------------------


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
				# Тащить можно только за пустое место: до _gui_input графа
				# событие доходит лишь тогда, когда его не забрала карточка.
				_panning = event.pressed
				accept_event()
	elif event is InputEventMouseMotion and _panning:
		# Отпускание кнопки могло уйти карточке (потащили с пустого места и
		# отпустили над узлом) — тогда «конец панорамы» до графа не доедет, и
		# он бы таскался за курсором без нажатой кнопки. Сверяемся с маской.
		if (event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE)) == 0:
			_panning = false
			return
		_canvas.position += event.relative
		_stop_fit_tween()
		accept_event()


## Зум «в курсор»: точка под мышью остаётся на месте, иначе граф уезжает
## из-под пальца и приближать приходится в два приёма.
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


## Кадр ожидания намеренный: сразу после setup() размер контрола ещё нулевой —
## контейнер разложит его только в следующем кадре, и «вписать» было бы не во что.
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

	# Потолок 1.0, а не zoom_max: единственную открытую карточку не нужно
	# раздувать во весь экран только потому, что она там одна.
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
