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
## Что правится глазами и что кодом. Слои графа (полотно панорамы и слой
## дорожек-со-связями) лежат в skill_graph_view.tscn, карточка — своей сценой
## skill_node_card.tscn, а размеры и цвета, которые нельзя нарисовать, вынесены
## в @export и правятся в инспекторе. Кодом остаётся только то, что зависит от
## данных: где стоит узел, что показано, куда идёт связь.
class_name UI_SkillGraph
extends Control

## Нажали по карточке навыка. Что с этим делать — решает экран, граф не зовёт
## SkillManager.unlock сам: рисование и трата очков — разные обязанности.
signal skill_activated(id: StringName)

@export_group("Клетка")
@export var cell_gap := Vector2(68.0, 20.0)
## Левый жёлоб под подписи дорожек.
@export var lane_label_width := 136.0

@export_group("Дорожки")
@export var lane_fill_alpha := 0.06
@export var lane_label_alpha := 0.8
## Насколько подложка дорожки выступает за крайние карточки ветки.
@export var lane_padding := Vector2(18.0, 10.0)

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

@export_group("Эффекты")
## Появление новой карточки: подъезд из полупрозрачности, чтобы открытие ветки
## читалось как событие, а не как «граф моргнул».
@export var reveal_duration := 0.35
@export var fit_duration := 0.35
## Цвет вспышки карточки и искр при разблокировке — тёплый golden, не из темы:
## тема несёт форму контролов, а разовый эффект-реакция к ней не относится.
@export var flash_color := Color(1.6, 1.35, 0.7)
@export var flash_duration := 0.5
@export var spark_count := 16
@export var spark_lifetime := 0.5

## Сцена карточки-узла. Её же размер задаёт клетку сетки — см. _card_size().
const CARD_SCENE := preload("res://src/ui/skill_tree/skill_node_card.tscn")

var _skill_manager
var _tree_data: RS_SkillTree
var _layout: SkillGraphLayout

## Размер клетки = размер карточки, и берётся он ИЗ ЕЁ СЦЕНЫ. Второе число
## здесь (@export на графе) означало бы, что карточку, растянутую в редакторе,
## сетка, связи и подложки дорожек считают по-старому.
var node_size := Vector2(196.0, 96.0)

@onready var _canvas: Control = %Canvas
@onready var _links: Control = %Links

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
	resized.connect(_on_resized)
	_links.draw.connect(_draw_links)


func setup(skill_manager, tree_data: RS_SkillTree) -> void:
	_skill_manager = skill_manager
	_tree_data = tree_data
	_layout = SkillGraphLayout.build(tree_data)
	node_size = _card_size()

	# Размер слою нужен, хотя всё рисуется вручную: свой прямоугольник Control
	# отдаёт движку как область видимости, и при нулевом ректе весь слой
	# отсекается, едва точка (0,0) уходит за край экрана. Рисование за пределы
	# ректа не обрезается, но КУЛЛИТСЯ по нему — от этого подложки дорожек и
	# связи разом пропадали, стоило увести камеру с верхней дорожки («Захват»).
	_links.size = _content_size()

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
				_animate_reveal(card)
			appeared = true
		card.refresh(
			_skill_manager.get_rank(def.id),
			_skill_manager.can_unlock(def.id),
			previewed,
			_requirement_hint(def)
		)

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


func _animate_reveal(card: UI_SkillNode) -> void:
	card.modulate.a = 0.0
	card.scale = Vector2(0.86, 0.86)
	var tween := create_tween().set_parallel()
	tween.tween_property(card, "modulate:a", 1.0, reveal_duration)
	tween.tween_property(card, "scale", Vector2.ONE, reveal_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _flash(card: Control) -> void:
	card.modulate = flash_color
	var tween := create_tween()
	tween.tween_property(card, "modulate", Color.WHITE, flash_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _spawn_sparks(anchor: Control) -> void:
	var particles := CPUParticles2D.new()
	anchor.add_child(particles)
	particles.position = anchor.size / 2.0
	particles.z_index = 10
	particles.one_shot = true
	particles.amount = spark_count
	particles.lifetime = spark_lifetime
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

	get_tree().create_timer(spark_lifetime).timeout.connect(particles.queue_free)


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


## Место, забронированное под ВСЁ дерево, а не под открытую его часть: слой
## дорожек и связей живёт всю жизнь экрана, и пересчитывать его рект на каждом
## открытии ветки незачем — раскладка всё равно посчитана разом.
func _content_size() -> Vector2:
	if _layout == null:
		return Vector2.ZERO
	return Vector2(
		_content_width(),
		maxf(0.0, _layout.rows * (node_size.y + cell_gap.y) - cell_gap.y)
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


func _draw_links() -> void:
	if _layout == null:
		return
	_draw_lanes()

	for def in _tree_data.skills:
		if def == null or not _nodes.has(def.id):
			continue
		# Связь в предпросмотр бледнее самой связи: она ведёт туда, куда игрок
		# пока не может пойти, и наравне с рабочими рёбрами читалась бы как путь.
		var node_alpha := link_alpha * (0.45 if _nodes[def.id].previewed else 1.0)
		var color := Color(_tree_data.branch_color(def.branch), node_alpha)
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

	for lane in _layout.lanes:
		var band := _lane_band(lane)
		if band.size.y <= 0.0:
			continue
		var color := _tree_data.branch_color(lane["branch"])
		_links.draw_rect(band, Color(color, lane_fill_alpha))
		if font == null:
			continue
		_links.draw_string(
			font,
			Vector2(0.0, band.get_center().y + font_size * 0.35),
			_tree_data.branch_display_name(lane["branch"]),
			HORIZONTAL_ALIGNMENT_RIGHT,
			lane_label_width - 18.0,
			font_size,
			Color(color, lane_label_alpha)
		)


## Подложка дорожки — по ПОКАЗАННЫМ карточкам ветки, а не по забронированным
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
	_fit_tween.tween_property(self, "zoom", target_zoom, fit_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fit_tween.tween_property(_canvas, "position", target_position, fit_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _stop_fit_tween() -> void:
	if _fit_tween != null and _fit_tween.is_valid():
		_fit_tween.kill()
	_fit_tween = null
