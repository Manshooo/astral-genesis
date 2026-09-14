# res://src/ui/skill_tree/skill_graph_view.gd
## Граф дерева навыков: карточки-узлы, связи-требования, панорама и зум.
##
## Показывает НЕ всё дерево, а только изученное и следующее доступное
## (SkillManager.is_revealed) — правило карточки Skill Tree. Отсюда главный
## приём версии: ветка, открывающаяся по сумме рангов, не висит серыми
## заглушками, а появляется целиком в момент, когда условие выполнилось.
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
class_name UI_SkillGraph
extends Control

## Нажали по карточке навыка. Что с этим делать — решает экран, граф не зовёт
## SkillManager.unlock сам: рисование и трата очков — разные обязанности.
signal skill_activated(id: StringName)

@export_group("Клетка")
@export var node_size := Vector2(196.0, 80.0)
@export var cell_gap := Vector2(68.0, 20.0)
## Левый жёлоб под подписи дорожек.
@export var lane_label_width := 136.0

@export_group("Дорожки")
@export var lane_fill_alpha := 0.06
@export var lane_label_alpha := 0.8

@export_group("Связи")
@export var link_width := 2.0
@export var link_alpha := 0.5
## Сегментов на кривую связи. Больше — глаже, но связи пересчитываются на каждой
## перерисовке, а на глаз разница выше десятка уже не видна.
@export var link_segments := 14

@export_group("Панорама")
@export var zoom_min := 0.45
@export var zoom_max := 1.6
@export var zoom_step := 1.12
@export var fit_padding := 48.0

## Появление новой карточки: подъезд из полупрозрачности, чтобы открытие ветки
## читалось как событие, а не как «граф моргнул».
const REVEAL_DURATION := 0.35
const FIT_DURATION := 0.35

## Цвет вспышки карточки и искр при разблокировке — тёплый golden, не из темы:
## тема несёт форму контролов, а разовый эффект-реакция к ней не относится.
const FLASH_COLOR := Color(1.6, 1.35, 0.7)
const FLASH_DURATION := 0.5
const SPARK_COUNT := 16
const SPARK_LIFETIME := 0.5

var _skill_manager
var _tree_data: RS_SkillTree
var _layout: SkillGraphLayout

var _canvas: Control
var _links: Control
var _nodes: Dictionary = {}  ## StringName -> UI_SkillNode

var _panning := false
var _fitted := false
var _fit_tween: Tween

## Отдельным свойством, а не через _canvas.scale, чтобы масштаб можно было
## твинить как одно число: анимировать Vector2-масштаб и позицию раздельно
## значит ловить их рассинхрон в середине анимации.
var zoom: float = 1.0:
	set = _set_zoom


func _ready() -> void:
	clip_contents = true
	resized.connect(_on_resized)


func setup(skill_manager, tree_data: RS_SkillTree) -> void:
	_skill_manager = skill_manager
	_tree_data = tree_data
	_layout = SkillGraphLayout.build(tree_data)

	_canvas = Control.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	_links = Control.new()
	_links.name = "Links"
	_links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_links.draw.connect(_draw_links)
	_canvas.add_child(_links)

	refresh()


## Пересобрать граф под текущее состояние навыков. Узлы не удаляются никогда:
## показанная карточка остаётся показанной (см. SkillManager.is_revealed).
func refresh() -> void:
	if _tree_data == null:
		return

	var appeared := false
	for def in _tree_data.skills:
		if def == null:
			continue
		if not _skill_manager.is_revealed(def.id):
			continue
		var card: UI_SkillNode = _nodes.get(def.id)
		if card == null:
			card = _create_node(def)
			# Первая сборка — не «появление»: анимировать въезд десятка карточек
			# при открытии экрана значит показать анимацию вместо дерева.
			if _fitted:
				_animate_reveal(card)
			appeared = true
		card.refresh(_skill_manager.get_rank(def.id), _skill_manager.can_unlock(def.id))

	_links.queue_redraw()
	if appeared:
		_request_fit(_fitted)


func play_unlock_effect(id: StringName) -> void:
	var card: UI_SkillNode = _nodes.get(id)
	if card == null:
		return
	_flash(card)
	_spawn_sparks(card)


func _create_node(def: RS_SkillDefinition) -> UI_SkillNode:
	var card := UI_SkillNode.new()
	card.setup(def, _tree_data.branch_color(def.branch))
	card.custom_minimum_size = node_size
	card.size = node_size
	card.pivot_offset = node_size * 0.5
	card.position = _cell_to_pixel(_layout.cells.get(def.id, Vector2i.ZERO))
	card.pressed.connect(_on_card_pressed.bind(def.id))
	_canvas.add_child(card)
	_nodes[def.id] = card
	return card


func _on_card_pressed(id: StringName) -> void:
	skill_activated.emit(id)


func _animate_reveal(card: UI_SkillNode) -> void:
	card.modulate.a = 0.0
	card.scale = Vector2(0.86, 0.86)
	var tween := create_tween().set_parallel()
	tween.tween_property(card, "modulate:a", 1.0, REVEAL_DURATION)
	tween.tween_property(card, "scale", Vector2.ONE, REVEAL_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash(card: Control) -> void:
	card.modulate = FLASH_COLOR
	var tween := create_tween()
	tween.tween_property(card, "modulate", Color.WHITE, FLASH_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _spawn_sparks(anchor: Control) -> void:
	var particles := CPUParticles2D.new()
	anchor.add_child(particles)
	particles.position = anchor.size / 2.0
	particles.z_index = 10
	particles.one_shot = true
	particles.amount = SPARK_COUNT
	particles.lifetime = SPARK_LIFETIME
	particles.explosiveness = 1.0
	particles.direction = Vector2.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 140.0
	particles.gravity = Vector2(0.0, 220.0)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1.0, 0.85, 0.4)
	particles.emitting = true

	get_tree().create_timer(SPARK_LIFETIME).timeout.connect(particles.queue_free)


# --- Раскладка в пикселях ----------------------------------------------------


func _cell_to_pixel(cell: Vector2i) -> Vector2:
	return Vector2(
		lane_label_width + cell.x * (node_size.x + cell_gap.x),
		cell.y * (node_size.y + cell_gap.y)
	)


func _content_width() -> float:
	if _layout.columns <= 0:
		return lane_label_width
	return lane_label_width + _layout.columns * (node_size.x + cell_gap.x) - cell_gap.x


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


func _draw_links() -> void:
	if _layout == null:
		return
	_draw_lanes()

	for def in _tree_data.skills:
		if def == null or not _nodes.has(def.id):
			continue
		var color := Color(_tree_data.branch_color(def.branch), link_alpha)
		for req in def.requires:
			if req == null or req.type != RS_SkillRequirement.Type.SKILL_RANK:
				continue
			if not _nodes.has(req.target_skill):
				continue
			var source: UI_SkillNode = _nodes[req.target_skill]
			var target: UI_SkillNode = _nodes[def.id]
			_draw_link(source.position, target.position, color)


func _draw_lanes() -> void:
	var font := _links.get_theme_default_font()
	var font_size := _links.get_theme_default_font_size()
	var cell_height := node_size.y + cell_gap.y
	var width := _content_width()

	for lane in _layout.lanes:
		if not _lane_has_revealed(lane):
			continue
		var color := _tree_data.branch_color(lane["branch"])
		var top: float = lane["row"] * cell_height
		var height: float = lane["height"] * cell_height - cell_gap.y
		_links.draw_rect(Rect2(0.0, top, width, height), Color(color, lane_fill_alpha))
		if font == null:
			continue
		_links.draw_string(
			font,
			Vector2(0.0, top + height * 0.5 + font_size * 0.35),
			_tree_data.branch_display_name(lane["branch"]),
			HORIZONTAL_ALIGNMENT_RIGHT,
			lane_label_width - 18.0,
			font_size,
			Color(color, lane_label_alpha)
		)


func _lane_has_revealed(lane: Dictionary) -> bool:
	for def in _tree_data.get_branch_skills(lane["branch"]):
		if _nodes.has(def.id):
			return true
	return false


## Связь — кубическая кривая с горизонтальными «усами»: ветки лежат дорожками,
## и требование через дорожку прямой линией резало бы чужие карточки.
func _draw_link(from_position: Vector2, to_position: Vector2, color: Color) -> void:
	var a := from_position + Vector2(node_size.x, node_size.y * 0.5)
	var b := to_position + Vector2(0.0, node_size.y * 0.5)
	var handle := maxf((b.x - a.x) * 0.5, 40.0)
	var c1 := a + Vector2(handle, 0.0)
	var c2 := b - Vector2(handle, 0.0)

	var points := PackedVector2Array()
	for i in link_segments + 1:
		points.append(a.bezier_interpolate(c1, c2, b, float(i) / float(link_segments)))
	_links.draw_polyline(points, color, link_width, true)


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
	_fit_tween.tween_property(self, "zoom", target_zoom, FIT_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fit_tween.tween_property(_canvas, "position", target_position, FIT_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_fit_tween() -> void:
	if _fit_tween != null and _fit_tween.is_valid():
		_fit_tween.kill()
	_fit_tween = null
