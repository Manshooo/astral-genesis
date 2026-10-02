# res://src/ui/skill_tree/skill_neuron.gd
## Нейрон — узел дерева навыков (§9 «Меню — спека»): ядро Ø14, вокруг кольцо
## рангов сегментами, сбоку имя и «ранг/из». Вместо прежней карточки: дерево
## теперь сеть, а подробности навыка живут в карточке справа экрана
## (UI_SkillCard), куда нейрон лишь указывает выбором.
##
## Это Button: узел кликабелен целиком и держит фокус с клавиатуры, а соседей
## по стрелкам Godot находит сам — по геометрии, как бы сеть ни легла. Рисует
## нейрон сам (_draw), тема ему не нужна: ядро и кольцо — не StyleBox.
##
## Нейрон ничего не решает сам: состояние ему приносит граф вызовом refresh().
## Так у «можно ли купить» остаётся один источник правды — can_unlock.
class_name UI_SkillNeuron
extends Button

enum State { LOCKED, AVAILABLE, PARTIAL, MAXED }
## Где подпись: сбоку (наружу сети) или под нейроном.
enum LabelSide { RIGHT, LEFT, BELOW }

const SIZE := Vector2(44.0, 44.0)
const CORE_RADIUS := 7.0
const RING_RADIUS := 17.0
## Зазор между сегментами кольца рангов, в градусах.
const RING_GAP_DEG := 16.0
## Подпись — в 26 px от центра нейрона, по ту сторону, что дальше от ядра.
const LABEL_OFFSET := 26.0
## Кольцо-отклик открытия ранга (§7): дважды по секунде, 0.5 → 2.4 радиуса.
const PULSE_TIME := 1.0
const FLASH_TIME := 1.2

var definition: RS_SkillDefinition
var state := State.LOCKED
## Предпросмотр «на шаг вперёд»: нейрон виден, но требования ещё не выполнены.
var previewed := false
var can_buy := false
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _rank := 0
var _labels: VBoxContainer
var _name: Label
var _rank_label: Label
var _pulse := -1.0
var _press := 0.0
var _painted: Array = []
var _flashing := false


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2.0
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_labels = VBoxContainer.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.add_theme_constant_override(&"separation", 0)
	add_child(_labels)
	_name = _make_label(&"MenuNodeName")
	_rank_label = _make_label(&"MenuSmall")


func _make_label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_labels.add_child(label)
	return label


## [param side] — где подпись. Выбирает граф: сбоку она смотрит наружу сети, а
## у ветви, растущей вбок, уходит под нейрон — сбоку она легла бы на его же
## потомков.
func setup(def: RS_SkillDefinition, side: LabelSide) -> void:
	definition = def
	name = "Neuron_" + String(def.id)
	_name.text = tr(def.display_name)
	var align := HORIZONTAL_ALIGNMENT_LEFT
	match side:
		LabelSide.LEFT:
			align = HORIZONTAL_ALIGNMENT_RIGHT
		LabelSide.BELOW:
			align = HORIZONTAL_ALIGNMENT_CENTER
	_name.horizontal_alignment = align
	_rank_label.horizontal_alignment = align
	_labels.size = _labels.get_combined_minimum_size()
	match side:
		LabelSide.RIGHT:
			_labels.position = Vector2(SIZE.x / 2.0 + LABEL_OFFSET, 2.0)
		LabelSide.LEFT:
			_labels.position = Vector2(SIZE.x / 2.0 - LABEL_OFFSET - _labels.size.x, 2.0)
		LabelSide.BELOW:
			_labels.position = Vector2((SIZE.x - _labels.size.x) / 2.0, SIZE.y / 2.0 + LABEL_OFFSET - 6.0)


func refresh(rank: int, unlockable: bool, is_previewed: bool) -> void:
	_rank = rank
	can_buy = unlockable
	previewed = is_previewed
	if rank >= definition.max_rank:
		state = State.MAXED
	elif rank > 0:
		state = State.PARTIAL
	elif is_previewed:
		state = State.LOCKED
	else:
		state = State.AVAILABLE
	_rank_label.text = "%d/%d" % [rank, definition.max_rank]
	queue_redraw()


## Ранг открыт: кольцо расходится от нейрона, имя вспыхивает.
func play_unlock() -> void:
	_pulse = 0.0
	_flashing = true
	var tween := create_tween()
	tween.tween_method(_set_name_color, UI_HudMood.OVER, UI_MenuStyle.TEXT, FLASH_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_end_flash)


func _set_name_color(color: Color) -> void:
	_name.add_theme_color_override(&"font_color", color)


func _end_flash() -> void:
	_flashing = false
	_painted = []


func _process(delta: float) -> void:
	if _pulse >= 0.0:
		_pulse += delta / PULSE_TIME
		if _pulse >= 2.0:
			_pulse = -1.0
	_press = 1.0 if is_pressed() else move_toward(_press, 0.0, delta / 0.08)
	_paint_name()
	if is_visible_in_tree():
		queue_redraw()


## Имя: наведённое, в фокусе и выбранное — светлое и с эхом, закрытое —
## приглушено. Только на смене состояния: переопределение цвета зовёт у подписи
## пересчёт темы, а нейронов в сети — десяток. Пока имя вспыхивает после
## открытия ранга, цветом владеет вспышка.
func _paint_name() -> void:
	var hot := is_hovered() or has_focus() or selected
	var key := [hot, state == State.LOCKED]
	if key == _painted or _flashing:
		return
	_painted = key
	var color := UI_MenuStyle.TEXT if hot else UI_MenuStyle.TEXT_MSG
	if state == State.LOCKED and not hot:
		color = Color(UI_MenuStyle.TEXT_MSG, 0.4)
	_name.add_theme_color_override(&"font_color", color)
	_name.add_theme_color_override(&"font_shadow_color", Color(UI_MenuStyle.ECHO, 0.4) if hot else Color(0, 0, 0, 0))


func _draw() -> void:
	var c := SIZE / 2.0
	var hot := is_hovered() or has_focus()
	# Ореол выбранного и освоенного.
	if selected:
		draw_circle(c, 21.0, Color(UI_HudMood.SOUL, 0.16))
	elif state == State.MAXED:
		draw_circle(c, 21.0, Color(UI_HudMood.SOUL, 0.14))

	_draw_ring(c)

	var core_scale := 1.0 - 0.15 * _press
	var r := CORE_RADIUS * core_scale
	match state:
		State.MAXED, State.PARTIAL:
			draw_circle(c, r, UI_HudMood.SOUL)
		State.AVAILABLE:
			draw_circle(c, r, UI_MenuStyle.BG_VOID)
			if can_buy and not hot:
				_draw_dashed_circle(c, r, UI_HudMood.SOUL, 1.5, 2.0, 2.0)
			else:
				draw_arc(c, r, 0.0, TAU, 32, UI_MenuStyle.TEXT if hot else Color(UI_MenuStyle.TEXT, 0.7), 1.5, true)
		State.LOCKED:
			draw_circle(c, r, UI_MenuStyle.BG_VOID)
			_draw_dashed_circle(c, r, Color(UI_MenuStyle.TEXT, 0.5 if hot else 0.28), 1.5, 1.0, 3.0)

	if has_focus():
		_draw_dashed_circle(c, 21.5, UI_HudMood.SOUL, 1.0, 2.0, 3.0)

	if _pulse >= 0.0:
		var k := fmod(_pulse, 1.0)
		var radius := 20.0 * lerpf(0.5, 2.4, ease(k, 0.4))
		draw_arc(c, radius, 0.0, TAU, 48, Color(UI_HudMood.SOUL, 0.85 * (1.0 - k)), 1.5, true)


## Кольцо рангов: сегмент на ранг с зазором 16°; открытые — сиреневым штрихом,
## неоткрытые — пунктиром 1:3, как пустой трек дуги HUD.
func _draw_ring(c: Vector2) -> void:
	var count := maxi(definition.max_rank if definition else 1, 1)
	var seg := TAU / count
	var gap := deg_to_rad(RING_GAP_DEG) if count > 1 else 0.0
	for k in count:
		var from := -PI / 2.0 + k * seg + gap / 2.0
		var to := -PI / 2.0 + (k + 1) * seg - gap / 2.0
		if k < _rank:
			draw_arc(c, RING_RADIUS, from, to, 24, UI_HudMood.SOUL, 2.0, true)
		else:
			_draw_dotted_arc(c, RING_RADIUS, from, to, Color(UI_MenuStyle.TEXT, 0.32))


func _draw_dotted_arc(c: Vector2, radius: float, from: float, to: float, color: Color) -> void:
	var step := 4.0 / radius
	var a := from
	while a < to:
		draw_circle(c + Vector2.from_angle(a) * radius, 0.6, color)
		a += step


func _draw_dashed_circle(c: Vector2, radius: float, color: Color, width: float, dash: float, gap: float) -> void:
	var step := (dash + gap) / radius
	var dash_angle := dash / radius
	var a := 0.0
	while a < TAU:
		draw_arc(c, radius, a, minf(a + dash_angle, TAU), 4, color, width, true)
		a += step
