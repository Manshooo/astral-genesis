# res://src/ui/map/map_stratum.gd
## Полоса одного слоя в срезе комплекса (§9 «Меню — спека»): слева «L3» и
## подпись, справа этажи слоя тонкими линиями одна над другой, комнаты на них —
## штрихами по своей ширине в плане, отметка игрока — точкой. Вместо прежнего
## списка слоёв кнопками: срез показывает сам комплекс — сколько у слоя этажей,
## где на них изведано и где ты, — а не только имя слоя.
##
## Закрытый на этом уровне карты слой виден штриховкой с подписью «нет данных»
## и не выбирается: игрок видит, что знание можно докупить, а не гадает, сколько
## слоёв вообще бывает. Что именно рисовать, считает экран (UI_ComplexMap) —
## полоса только кладёт отданное на себя, как UI_MapFloor на плане.
class_name UI_MapStratum
extends Button

## Высота полосы и её внутренние поля (§4 «Карта»).
const HEIGHT := 86.0
## Где начинаются линии этажей: левее — имя слоя.
const LINES_X := 46.0
## Сверху — место под подпись слоя.
const LINES_TOP := 24.0
const ROOM_STROKE := 3.0
const BREATH_PERIOD := 3.2

var depth := 0
## Открыт ли слой на этом уровне карты.
var open := true
var selected := false:
	set(value):
		selected = value
		queue_redraw()
## Этажи снизу вверх: [{ "rooms": [{ "from", "to", "explored" }] }], from/to — доли
## ширины полосы линий.
var floors: Array = []
## Отметка игрока: этаж и доля ширины; -1 — игрока на этом слое нет.
var player_floor := -1
var player_x := 0.0

var _name: Label
var _sub: Label


func _ready() -> void:
	flat = true
	toggle_mode = false
	custom_minimum_size = Vector2(364.0, HEIGHT)
	add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	_name = _make_label(&"MenuStratum", Vector2(0, 0))
	_sub = _make_label(&"MenuSmall", Vector2(34, 3))


func _make_label(variation: StringName, at: Vector2) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = at
	add_child(label)
	return label


## [param subtitle] — «поверхность», «глубина» или «нет данных», пусто — без
## подписи.
func setup(layer_depth: int, is_open: bool, subtitle: String) -> void:
	depth = layer_depth
	open = is_open
	disabled = not is_open
	focus_mode = Control.FOCUS_ALL if is_open else Control.FOCUS_NONE
	_name.text = tr("MAP_LAYER") % layer_depth
	_sub.text = subtitle
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var hot := (is_hovered() or has_focus() or selected) and open
	_name.modulate = Color(1, 1, 1, 1.0 if hot else (0.7 if open else 0.3))
	_name.add_theme_color_override(&"font_shadow_color", Color(UI_MenuStyle.ECHO, 0.45) if selected else Color(0, 0, 0, 0))
	if player_floor >= 0:
		queue_redraw()


func _draw() -> void:
	var width := size.x
	var bottom := HEIGHT - 4.0
	if selected:
		draw_circle(Vector2(-12.0, 11.0), 2.5, UI_HudMood.SOUL)
	if has_focus():
		var under := _name.position.y + _name.size.y + 1.0
		draw_line(Vector2(0, under), Vector2(_name.size.x, under), UI_HudMood.SOUL, 1.0)

	if not open:
		_draw_fog(Rect2(LINES_X, LINES_TOP - 2.0, width - LINES_X, bottom - LINES_TOP - 4.0))
	else:
		var count := maxi(floors.size(), 1)
		var step := (bottom - LINES_TOP) / count
		var line_color := Color(UI_MenuStyle.TEXT, 0.30 if selected else 0.12)
		for i in floors.size():
			# Этажи стоят один над другим: верхний — последний в списке.
			var y := LINES_TOP + step * (count - 1 - i + 0.6)
			draw_line(Vector2(LINES_X, y), Vector2(width, y), line_color, 1.0)
			for room: Dictionary in floors[i]["rooms"]:
				var from := LINES_X + float(room["from"]) * (width - LINES_X - 8.0)
				var to := maxf(from + ROOM_STROKE, LINES_X + float(room["to"]) * (width - LINES_X - 8.0) - 3.0)
				var color := Color(UI_HudMood.SOUL, 0.75) if room["explored"] else Color(UI_MenuStyle.TEXT, 0.4)
				draw_line(Vector2(from, y), Vector2(to, y), color, ROOM_STROKE)
			if i == player_floor:
				var center := Vector2(LINES_X + player_x * (width - LINES_X - 8.0), y - 8.0)
				var k := 0.5 + 0.5 * sin(TAU * UI_HudMood.now() / BREATH_PERIOD)
				draw_circle(center, 7.0 * lerpf(0.92, 1.08, k), Color(UI_HudMood.DOT, 0.14))
				draw_circle(center, 3.2, UI_HudMood.DOT)
	# Граница слоёв — пунктир 1:3, как пустой трек дуги HUD.
	UI_MenuStyle.draw_dotted(self, Vector2(0, HEIGHT - 0.5), Vector2(width, HEIGHT - 0.5), Color(UI_MenuStyle.TEXT, 0.16))


## Штриховка −28° поверх неизвестного слоя: «здесь что-то есть, но не для тебя».
func _draw_fog(rect: Rect2) -> void:
	var slope := tan(deg_to_rad(28.0))
	var x := rect.position.x - rect.size.y * slope
	while x < rect.end.x:
		var a := Vector2(x, rect.end.y)
		var b := Vector2(x + rect.size.y * slope, rect.position.y)
		# Обрезаем отрезок по прямоугольнику по X.
		if a.x < rect.position.x:
			a = a.lerp(b, (rect.position.x - a.x) / (b.x - a.x))
		if b.x > rect.end.x:
			b = a.lerp(b, (rect.end.x - a.x) / (b.x - a.x))
		draw_line(a, b, Color(UI_MenuStyle.TEXT, 0.05), 1.0)
		x += 8.0
