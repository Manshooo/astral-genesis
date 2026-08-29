# res://src/ui/skill_tree/skill_node_card.gd
## Карточка одного навыка — узел графа дерева.
##
## Это Button, а не составной Control с кнопкой внутри: узел графа кликабелен
## целиком, и наведение с подсказкой обязано ловиться всей площадью карточки.
## Поэтому же вся начинка помечена MOUSE_FILTER_IGNORE — иначе подпись под
## курсором «съедала» бы и hover, и tooltip у своего же узла.
##
## Карточка ничего не знает про SkillManager и ничего не решает сама: состояние
## ей приносит граф вызовом refresh(). Так у «можно ли купить» остаётся один
## источник правды — SkillManager.can_unlock.
class_name UI_SkillNode
extends Button

## Ранговые деления: заполненные — купленные ранги.
const PIP_SIZE := Vector2(14.0, 6.0)
const PIP_GAP := 4.0

## Серый оттенок карточки-предпросмотра. Приглушаются только каналы цвета, а
## альфа сохраняется: ею анимируется появление узла, и запись целого Color
## оборвала бы въезд карточки на середине.
const PREVIEW_TINT := Color(0.62, 0.64, 0.68)
## Переход из предпросмотра в доступный навык.
const UNGREY_DURATION := 0.25

var definition: RS_SkillDefinition
var accent: Color = RS_SkillBranch.DEFAULT_COLOR
## Навык показан «на шаг вперёд»: описание читается, купить нельзя.
var previewed: bool = false

var _pips: Control
var _status: Label
var _rank: int = 0


func setup(def: RS_SkillDefinition, accent_color: Color) -> void:
	definition = def
	accent = accent_color
	name = "Node_" + String(def.id)
	clip_text = false

	# Полоска ветки: цвет дорожки на самой карточке, иначе на панораме с
	# отъехавшими подписями дорожек уже не понять, из какой ветки узел.
	var stripe := ColorRect.new()
	stripe.color = accent
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	stripe.offset_right = 4.0
	add_child(stripe)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var title := Label.new()
	title.text = def.display_name
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(title)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 8)
	box.add_child(bottom)

	_pips = Control.new()
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.custom_minimum_size = Vector2(
		def.max_rank * PIP_SIZE.x + maxi(0, def.max_rank - 1) * PIP_GAP, PIP_SIZE.y
	)
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pips.draw.connect(_draw_pips)
	bottom.add_child(_pips)

	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_status)


## Состояние приносит граф: ранг, «можно ли купить прямо сейчас» и показан ли
## навык лишь предпросмотром. [param requirement_hint] — чего не хватает; граф
## складывает его из требований, потому что имена соседних навыков знает он.
func refresh(
	rank: int, unlockable: bool, is_preview: bool = false, requirement_hint: String = ""
) -> void:
	_rank = rank
	var was_previewed := previewed
	previewed = is_preview
	var maxed := rank >= definition.max_rank

	if previewed:
		# Стоимость не показывается намеренно: пока условие не выполнено, цена
		# игроку не решение, а шум — ему нужно знать, ЧТО открывает навык.
		_status.text = "Недоступно"
	elif maxed:
		_status.text = "Максимум"
	else:
		_status.text = _points_text(definition.cost_for_next_rank(rank))

	# disabled, а не своя проверка в обработчике нажатия: нужен именно
	# «выключенный» вид из темы, а подсказка на disabled-кнопке всё равно
	# показывается — она про наведение, а не про нажатие.
	disabled = previewed or maxed or not unlockable
	if was_previewed and not previewed:
		# Узел не появился, а ОЖИЛ — это событие того же порядка, что и въезд
		# новой карточки, и мгновенная смена цвета читалась бы как перерисовка.
		create_tween().tween_property(
			self, "modulate", Color(Color.WHITE, modulate.a), UNGREY_DURATION
		)
	else:
		modulate = Color(PREVIEW_TINT if previewed else Color.WHITE, modulate.a)
	tooltip_text = _tooltip_for(rank, requirement_hint)
	_pips.queue_redraw()


## Подсказка при наведении. Пока это движковый tooltip с общей задержкой
## (gui/timers/tooltip_delay_sec) — свой таймер на 300 мс заведён отдельной
## задачей версии; здесь важно лишь то, что подсказка висит на ВСЕЙ карточке.
func _tooltip_for(rank: int, requirement_hint: String) -> String:
	var lines := PackedStringArray([definition.display_name])
	if not definition.description.is_empty():
		lines.append(definition.description)
	if previewed:
		# Ради этой строки предпросмотр и заведён: карточка обязана объяснить,
		# что именно откроет доступ, иначе серый узел — просто дразнилка.
		if not requirement_hint.is_empty():
			lines.append("Требуется: " + requirement_hint)
		return "\n".join(lines)
	if rank >= definition.max_rank:
		lines.append("Ранг %d/%d — максимум" % [rank, definition.max_rank])
	else:
		var cost := definition.cost_for_next_rank(rank)
		lines.append(
			"Ранг %d/%d · следующий за %s" % [rank, definition.max_rank, _points_text(cost)]
		)
	return "\n".join(lines)


func _draw_pips() -> void:
	var filled := accent
	var empty := Color(accent, 0.22)
	for i in definition.max_rank:
		var rect := Rect2(Vector2(i * (PIP_SIZE.x + PIP_GAP), 0.0), PIP_SIZE)
		_pips.draw_rect(rect, filled if i < _rank else empty)


## «1 очко / 2 очка / 5 очков» — стоимость показывается игроку, а не логу.
func _points_text(amount: int) -> String:
	var tail := amount % 100
	if tail >= 11 and tail <= 14:
		return "%d очков" % amount
	match amount % 10:
		1:
			return "%d очко" % amount
		2, 3, 4:
			return "%d очка" % amount
	return "%d очков" % amount
