# res://src/ui/skill_tree/skill_node_card.gd
## Карточка одного навыка — узел графа дерева.
##
## Вёрстка живёт в skill_node_card.tscn, а не в этом файле: карточку правят
## глазами (отступы, шрифт, полоска ветки, место под деления рангов), и код,
## собирающий её из new(), означал бы, что каждая такая правка — правка кода.
## Скрипт держит только то, что вёрсткой не выражается: текст состояния,
## подсказку и деления рангов, которых столько, сколько у навыка рангов.
##
## Это Button, а не составной Control с кнопкой внутри: узел графа кликабелен
## целиком, и наведение с подсказкой обязано ловиться всей площадью карточки.
## Поэтому же вся начинка помечена MOUSE_FILTER_IGNORE (в сцене) — иначе подпись
## под курсором «съедала» бы и hover, и tooltip у своего же узла.
##
## Карточка ничего не знает про SkillManager и ничего не решает сама: состояние
## ей приносит граф вызовом refresh(). Так у «можно ли купить» остаётся один
## источник правды — SkillManager.can_unlock.
class_name UI_SkillNode
extends Button

@export_group("Деления рангов")
## Одно деление ранга. Заполненные — купленные ранги.
@export var pip_size := Vector2(14.0, 6.0)
@export var pip_gap := 4.0
## Непрожитый ранг тем же цветом ветки, но еле видный.
@export var pip_empty_alpha := 0.22

@export_group("Предпросмотр")
## Серость карточки-предпросмотра. Приглушаются только каналы цвета, а альфа
## сохраняется: ею анимируется появление узла, и запись целого Color оборвала бы
## въезд карточки на середине.
@export var preview_tint := Color(0.62, 0.64, 0.68)
## Переход из предпросмотра в доступный навык.
@export var ungrey_duration := 0.25
## Что стоит в строке состояния, пока навык только показан.
@export var preview_status_text := "Недоступно"
@export var maxed_status_text := "Максимум"

@onready var _stripe: ColorRect = %Stripe
@onready var _title: Label = %Title
@onready var _pips: Control = %Pips
@onready var _status: Label = %Status

var definition: RS_SkillDefinition
var accent: Color = RS_SkillBranch.DEFAULT_COLOR
## Навык показан «на шаг вперёд»: описание читается, купить нельзя.
var previewed: bool = false

var _rank: int = 0


func _ready() -> void:
	_pips.draw.connect(_draw_pips)


## Зовётся графом ПОСЛЕ добавления карточки в дерево сцены: до этого @onready
## ссылки на начинку ещё не подняты.
func setup(def: RS_SkillDefinition, accent_color: Color) -> void:
	definition = def
	accent = accent_color
	name = "Node_" + String(def.id)

	_title.text = def.display_name
	_stripe.color = accent
	# Делений столько, сколько у навыка рангов, — единственный размер в карточке,
	# который вёрсткой не задать: он приходит из данных навыка.
	_pips.custom_minimum_size = Vector2(
		def.max_rank * pip_size.x + maxi(0, def.max_rank - 1) * pip_gap, pip_size.y
	)


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
		_status.text = preview_status_text
	elif maxed:
		_status.text = maxed_status_text
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
			self, "modulate", Color(Color.WHITE, modulate.a), ungrey_duration
		)
	else:
		modulate = Color(preview_tint if previewed else Color.WHITE, modulate.a)
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
	var empty := Color(accent, pip_empty_alpha)
	for i in definition.max_rank:
		var rect := Rect2(Vector2(i * (pip_size.x + pip_gap), 0.0), pip_size)
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
