# res://src/ui/menu/menu_style.gd
## Общее для меню языка «Отголосок»: токены палитры, смятение T вне забега,
## рваный штрих. Числа — из «Меню — спека» (§2, §4); то, что меню делит с HUD
## (сиреневый души, формула эха, часы), берётся из UI_HudMood, а не копируется:
## меню — продолжение HUD, и разойтись им нельзя ни цветом, ни тактом.
##
## Только статика и без состояния — по той же причине, что UI_HudMood.
class_name UI_MenuStyle
extends RefCounted

# --- Палитра (§2) -------------------------------------------------------------
# Справочник токенов — «Конвенции проекта» §3, как и у UI_HudMood.

const BG_VOID := Color(0.043, 0.039, 0.051)
const TEXT := Color(0.93, 0.91, 0.95)
const TEXT_MSG := Color(0.86, 0.84, 0.89)
const TEXT_DIM := Color(0.71, 0.68, 0.75)
## Недоступное: смысл несёт пунктир и подпись причины, а не цвет.
const TEXT_OFF := Color(0.93, 0.91, 0.95, 0.28)
const TRACK := Color(0.93, 0.91, 0.95, 0.34)
const ECHO := Color(0.79, 0.66, 0.95, 0.30)
const HALO := Color(0.79, 0.66, 0.95, 0.14)

# --- Смятение -----------------------------------------------------------------

## Смятение вне забега — главное меню, итоги, настройки из главного меню.
## Формула HUD считает T по телам текущего забега и без забега дала бы максимум,
## самое нервное эхо, а меню вне забега — передышка. 0.6 — амплитуда макетов.
const OUT_OF_RUN_TURMOIL := 0.6


## T для меню: в забеге — то же, что у HUD (пауза, навыки и карта дрожат с ним
## в одном такте), вне забега — постоянное. «В забеге» решает UIManager.enabled:
## его включает только игровая сцена, и он же решает, захватывать ли курсор.
static func turmoil() -> float:
	if UIManager.enabled:
		return UI_HudMood.turmoil()
	return OUT_OF_RUN_TURMOIL


## Сдвиг эха строки меню — формула HUD с T меню.
static func echo_offset(phase: float = 0.0) -> Vector2:
	return UI_HudMood.echo_offset(turmoil(), phase)


# --- Рваный штрих (§4) ----------------------------------------------------------

## 15 изломов штриха из rag_line.svg: x в долях длины, y — отклонение в px при
## T = 0.6. Излом статичен (живой штрих под каждой кнопкой рябил бы), но его
## амплитуда растёт со смятением — как рваность дуги и рамки мини-карты.
const RAG := [
	Vector2(0.0, 0.15), Vector2(0.068, -0.65), Vector2(0.136, 0.55),
	Vector2(0.205, -0.15), Vector2(0.273, 0.75), Vector2(0.341, -0.45),
	Vector2(0.409, 0.25), Vector2(0.477, -0.85), Vector2(0.545, 0.45),
	Vector2(0.614, -0.25), Vector2(0.682, 0.85), Vector2(0.75, -0.35),
	Vector2(0.818, 0.35), Vector2(0.886, -0.55), Vector2(1.0, 0.05),
]


## Точки штриха от [param from] до [param to] (одна высота), прорисованного на
## долю [param progress] слева направо.
static func rag_points(from: Vector2, to: Vector2, progress: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	if progress <= 0.0:
		return points
	var amplitude := turmoil() / OUT_OF_RUN_TURMOIL
	var length := to.x - from.x
	var previous: Vector2 = RAG[0]
	for i in RAG.size():
		var p: Vector2 = RAG[i]
		if p.x > progress:
			# Последний отрезок обрезается внутри излома, а не на нём, иначе
			# штрих прорисовывался бы рывками по 15 шагов.
			var k := (progress - previous.x) / maxf(p.x - previous.x, 0.0001)
			var y := lerpf(previous.y, p.y, k)
			points.append(Vector2(from.x + progress * length, from.y + y * amplitude))
			break
		points.append(Vector2(from.x + p.x * length, from.y + p.y * amplitude))
		previous = p
	return points


## Пунктир 1:3 — пустой трек дуги HUD, им же меню отмечает недоступное и
## выноски итогов.
static func draw_dotted(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var x := from.x
	while x < to.x:
		canvas.draw_rect(Rect2(x, from.y - 0.5, 1.0, 1.0), color)
		x += 4.0


## Пятно «тени мысли» за группой строк: радиальный градиент без формы. Свой
## у меню, а не HUD-овский: за меню пятно гуще и плавнее гаснет (.86 → .5 → 0).
static func thought_shadow(peak_alpha: float, mid_alpha: float = -1.0) -> GradientTexture2D:
	var gradient := Gradient.new()
	var color := UI_HudMood.SHADOW_BLOB
	color.a = peak_alpha
	gradient.set_color(0, color)
	var clear := color
	clear.a = 0.0
	gradient.set_color(1, clear)
	if mid_alpha >= 0.0:
		var mid := color
		mid.a = mid_alpha
		gradient.add_point(0.55, mid)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture
