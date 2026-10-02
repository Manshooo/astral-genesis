# res://src/ui/menu/echo_button.gd
## Кнопка-мысль языка «Отголосок» (§5 «Меню — спека»): без рамки и подложки.
## Тема даёт ей шрифт, цвета состояний и поля (вариации EchoButton,
## EchoButtonSmall, MenuTab); сама кнопка рисует то, чего StyleBox не умеет:
## сиреневое эхо текста, рваный штрих, прорисовывающийся слева направо, и точку
## фокуса с клавиатуры.
##
## Фокус обязан отличаться от наведения (§1): наведение — эхо и бледный штрих,
## фокус — ещё и точка души слева, штрих в полную силу. Поэтому и рисуется всё
## здесь: стиль focus у Button ложится поверх hover одинаковой рамкой и разницы
## «мышь тут / клавиатура тут» не передаёт.
##
## Положение точки и штриха — константы вариации темы (dot_x, dot_radius,
## rag_bottom, rag_hover_alpha, draw_rag), а не экспорты: у малой кнопки и
## вкладки они свои, и задаются один раз в теме, а не в каждой сцене. Константы
## темы целые, поэтому dot_radius — в десятых пикселя, rag_hover_alpha — в
## процентах.
class_name UI_EchoButton
extends Button

## Сколько длится появление эха (§7: 140 мс linear).
const ECHO_IN := 0.14
## Постоянная времени прорисовки штриха: к 220 мс он почти дорисован (§7).
const RAG_TAU := 0.07
## Появление точки фокуса (§7: 120 мс).
const FOCUS_IN := 0.12
## Период бегущего штриха «занято» (§7, возрождение: 1.4 с).
const BUSY_PERIOD := 1.4

## «Занято»: кнопка недоступна, а штрих под ней бежит — генерация идёт, игра не
## зависла. Отдельно от disabled, потому что недоступная кнопка рисует пунктир.
var busy := false:
	set(value):
		busy = value
		queue_redraw()

## Отметка на самой кнопке — «Сохранено» в паузе (§7): кнопка недоступна, пока
## отметка висит, но это не «нельзя», а «сделано», и вместо пунктира
## недоступного у неё горит эхо.
var marked := false:
	set(value):
		marked = value
		queue_redraw()

var _echo := 0.0
var _rag := 0.0
var _focus := 0.0
var _phase := 0.0


func _ready() -> void:
	# Фаза по месту в списке: соседние пункты не должны дрожать хором.
	_phase = float(get_index()) * 1.7


func _process(delta: float) -> void:
	var live := not disabled and not busy
	var selected := toggle_mode and button_pressed
	var echo_target := 1.0 if marked or (live and (is_hovered() or has_focus() or selected)) else 0.0
	_echo = move_toward(_echo, echo_target, delta / ECHO_IN)
	var rag_target := 0.0
	if live and (has_focus() or selected):
		rag_target = 1.0
	elif live and is_hovered():
		rag_target = _const(&"rag_hover_alpha", 55) / 100.0
	_rag = UI_HudMood.approach(_rag, rag_target, RAG_TAU, delta)
	_focus = move_toward(_focus, 1.0 if has_focus() else 0.0, delta / FOCUS_IN)
	# Каждый кадр, а не «пока что-то видно»: эхо дрожит постоянно, а гаснущему
	# состоянию нужен ещё один кадр, чтобы стереться. Кнопок на экране — единицы.
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var style := _current_style()
	var left := style.get_margin(SIDE_LEFT)
	var right := size.x - style.get_margin(SIDE_RIGHT)
	var y := size.y - float(_const(&"rag_bottom", 4))

	if busy:
		_draw_busy(left, right, y)
	elif disabled and not marked:
		UI_MenuStyle.draw_dotted(self, Vector2(left, y), Vector2(right, y),
				Color(UI_MenuStyle.TEXT, 0.22))
	elif _rag > 0.001 and _const(&"draw_rag", 1) != 0:
		# Штрих прорисовывается долей длины, а его яркость — тем же _rag:
		# наведение доводит его до α .55, фокус — до полной силы.
		var progress := clampf(_rag / maxf(_rag_cap(), 0.01), 0.0, 1.0)
		var points := UI_MenuStyle.rag_points(Vector2(left, y), Vector2(right, y), progress)
		if points.size() >= 2:
			draw_polyline(points, Color(UI_HudMood.SOUL, 0.85 * _rag), 1.2, true)

	if _echo > 0.0:
		_draw_echo(style)

	if _focus > 0.0:
		var center := Vector2(float(_const(&"dot_x", 10)), size.y / 2.0)
		var radius := _const(&"dot_radius", 30) / 10.0 * lerpf(0.4, 1.0, _focus)
		if disabled:
			# Фокус на недоступном пункте всё равно виден: клавиатура должна
			# знать, где она, — но без сиреневого, это не внимание души.
			draw_circle(center, radius, Color(UI_MenuStyle.TEXT_DIM, 0.5 * _focus))
		else:
			draw_circle(center, radius + 5.0, Color(UI_MenuStyle.HALO, UI_MenuStyle.HALO.a * _focus))
			draw_circle(center, radius, Color(UI_HudMood.SOUL, _focus))


## Эхо — копия строки сиреневым со сдвигом. Рисуется поверх текста кнопки, как
## ::after в прототипе: α .30 текст не прячет. При нажатии эхо встаёт на место
## строки (§7) — мысль «схлопнулась» в действие.
func _draw_echo(style: StyleBox) -> void:
	var shown := atr(text)
	if shown == "":
		return
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	var content_h := size.y - style.get_margin(SIDE_TOP) - style.get_margin(SIDE_BOTTOM)
	var baseline := Vector2(
		style.get_margin(SIDE_LEFT),
		style.get_margin(SIDE_TOP) + (content_h - font.get_height(font_size)) / 2.0
				+ font.get_ascent(font_size),
	)
	var offset := Vector2.ZERO if is_pressed() and not toggle_mode else UI_MenuStyle.echo_offset(_phase)
	var color := UI_MenuStyle.ECHO
	color.a *= _echo
	draw_string(font, baseline + offset, shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Бегущий штрих: окно в 40 % длины едет слева направо и уходит за край.
func _draw_busy(left: float, right: float, y: float) -> void:
	var t := fmod(UI_HudMood.now(), BUSY_PERIOD) / BUSY_PERIOD
	var head := ease(t, 0.6)
	var points := UI_MenuStyle.rag_points(Vector2(left, y), Vector2(right, y), 1.0)
	var window := PackedVector2Array()
	var length := right - left
	for p in points:
		var k := (p.x - left) / maxf(length, 1.0)
		if k >= head - 0.4 and k <= head:
			window.append(p)
	if window.size() >= 2:
		draw_polyline(window, Color(UI_HudMood.SOUL, 0.85), 1.2, true)


## Предел _rag в текущем состоянии: доля прорисовки считается от него, иначе
## штрих наведения (α .55) так и остался бы недорисованным наполовину.
func _rag_cap() -> float:
	if has_focus() or (toggle_mode and button_pressed):
		return 1.0
	return _const(&"rag_hover_alpha", 55) / 100.0


func _current_style() -> StyleBox:
	match get_draw_mode():
		DRAW_PRESSED:
			return get_theme_stylebox(&"pressed")
		DRAW_HOVER:
			return get_theme_stylebox(&"hover")
		DRAW_DISABLED:
			return get_theme_stylebox(&"disabled")
		DRAW_HOVER_PRESSED:
			return get_theme_stylebox(&"hover_pressed")
	return get_theme_stylebox(&"normal")


## Константа вариации или запасное значение, если тема её не объявила.
func _const(name: StringName, fallback: int) -> int:
	if has_theme_constant(name):
		return get_theme_constant(name)
	return fallback
