# res://src/ui/menu/menu_style.gd
## Общее для меню «Отголосок»: токены палитры, смятение T вне забега, рваный штрих (числа — «Меню — спека» §2, §4). Общее с HUD (сиреневый, эхо, часы) берётся из UI_HudMood. Статика без состояния.
class_name UI_MenuStyle
extends RefCounted

# Палитра (§2); токены — «Конвенции проекта» §3.

const BG_VOID := Color(0.043, 0.039, 0.051)
const TEXT := Color(0.93, 0.91, 0.95)
const TEXT_MSG := Color(0.86, 0.84, 0.89)
const TEXT_DIM := Color(0.71, 0.68, 0.75)
## Недоступное: смысл несёт пунктир и подпись причины, а не цвет.
const TEXT_OFF := Color(0.93, 0.91, 0.95, 0.28)
const TRACK := Color(0.93, 0.91, 0.95, 0.34)
const ECHO := Color(0.79, 0.66, 0.95, 0.30)
const HALO := Color(0.79, 0.66, 0.95, 0.14)

# --- Смятение ---

## Смятение вне забега: формула HUD без забега дала бы максимум, а меню — передышка; 0.6 — амплитуда макетов.
const OUT_OF_RUN_TURMOIL := 0.6


## T для меню: в забеге — как у HUD (в одном такте), вне забега — постоянное; «в забеге» решает UIManager.enabled.
static func turmoil() -> float:
	if UIManager.enabled:
		return UI_HudMood.turmoil()
	return OUT_OF_RUN_TURMOIL


## Сдвиг эха строки меню — формула HUD с T меню.
static func echo_offset(phase: float = 0.0) -> Vector2:
	return UI_HudMood.echo_offset(turmoil(), phase)


# --- Рваный штрих (§4) ---

## 15 изломов rag_line.svg: x — доли длины, y — px при T = 0.6; излом статичен, амплитуда растёт со смятением.
const RAG := [
	Vector2(0.0, 0.15), Vector2(0.068, -0.65), Vector2(0.136, 0.55),
	Vector2(0.205, -0.15), Vector2(0.273, 0.75), Vector2(0.341, -0.45),
	Vector2(0.409, 0.25), Vector2(0.477, -0.85), Vector2(0.545, 0.45),
	Vector2(0.614, -0.25), Vector2(0.682, 0.85), Vector2(0.75, -0.35),
	Vector2(0.818, 0.35), Vector2(0.886, -0.55), Vector2(1.0, 0.05),
]


## Точки штриха от from до to, прорисованного на долю progress слева направо.
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
			# Последний отрезок обрезается внутри излома, иначе штрих шёл бы рывками по 15 шагов.
			var k := (progress - previous.x) / maxf(p.x - previous.x, 0.0001)
			var y := lerpf(previous.y, p.y, k)
			points.append(Vector2(from.x + progress * length, from.y + y * amplitude))
			break
		points.append(Vector2(from.x + p.x * length, from.y + p.y * amplitude))
		previous = p
	return points


## Пунктир 1:3 — пустой трек дуги HUD: недоступное и выноски итогов.
static func draw_dotted(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var x := from.x
	while x < to.x:
		canvas.draw_rect(Rect2(x, from.y - 0.5, 1.0, 1.0), color)
		x += 4.0
