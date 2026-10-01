# res://src/ui/hud/hud_message.gd
## Экранное сообщение: короткий текст-реакция на действие («Заперто…»,
## «Прохода нет»). Появляется на добавление C_ScreenMessage на игрока.
##
## Подаётся мыслью, которая проявляется и растворяется (§6 «HUD — спека»):
## 0.3 с проявления, 1.7 с на месте, 0.9 с растворения — буквы расходятся, строка
## уходит вверх. Своя строка ниже подсказки, даже когда подсказки нет: иначе
## сообщение прыгало бы, смотря на что игрок глядит.
##
## Таймлайн свой, а не «пока висит компонент»: на снятие компонента строка
## должна раствориться, а не исчезнуть, и S_ScreenMessage держит компонент ровно
## столько же (C_ScreenMessage.remaining), чтобы состояние мира не врало.
##
## Текст — ключ перевода или уже собранная строка (с подстановкой): tr() вернёт
## готовую строку как есть.
class_name UI_HudMessage
extends Control

const APPEAR := 0.3
const HOLD := 1.7
const FADE := 0.9
const TOTAL := APPEAR + HOLD + FADE
## Сообщение длиннее переносится на вторую строку.
const MAX_WIDTH := 720.0
## Растворение: насколько расходятся буквы (доля кегля) и куда уходит строка.
const SPREAD_EM := 0.14
const DRIFT := -6.0
const RISE := 3.0
## Размытие, px: строка фокусируется на проявлении и расплывается, растворяясь.
const BLUR_IN := 4.0
const BLUR_OUT := 5.0

@onready var _shadow: TextureRect = $Blur/ThoughtShadow
@onready var _label: UI_ThoughtLabel = $Blur/Text
@onready var _blur: CanvasGroup = $Blur

## Время показа по часам HUD; -INF — сообщения нет.
var _started := -INF
## Своя копия шрифта: межбуквенный интервал анимируется только у этой строки.
var _font: FontVariation
var _blur_now := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.texture = UI_HudMood.thought_shadow_texture()
	_blur.material = UI_HudMood.blur_material()
	_font = FontVariation.new()
	_font.base_font = _label.get_theme_font(&"font")
	_label.add_theme_font_override(&"font", _font)
	visible = false
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)


func _on_world_changed(world: World) -> void:
	_started = -INF
	visible = false
	if world:
		_connect_world_signals(world)


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_added):
		world.component_added.connect(_on_component_added)


func _on_component_added(_entity: Entity, component: Variant) -> void:
	if component is C_ScreenMessage:
		show_line((component as C_ScreenMessage).text)


## Показать строку заново — новое сообщение перебивает старое с начала.
func show_line(line: String) -> void:
	_label.text = tr(line)
	_started = UI_HudMood.now()
	_apply(0.0)


## Что сейчас на экране — для проверок. Пусто — сообщения нет.
func shown_text() -> String:
	return _label.text if visible else ""


func _process(_delta: float) -> void:
	if _started == -INF:
		return
	_apply(UI_HudMood.now() - _started)


## Состояние строки через [param elapsed] секунд после показа.
func _apply(elapsed: float) -> void:
	if elapsed >= TOTAL:
		_started = -INF
		visible = false
		return
	visible = true
	var fade := clampf((elapsed - APPEAR - HOLD) / FADE, 0.0, 1.0)
	var alpha := clampf(elapsed / APPEAR, 0.0, 1.0) * (1.0 - fade)
	var appear := clampf(elapsed / APPEAR, 0.0, 1.0)
	modulate.a = alpha
	_font.spacing_glyph = roundi(SPREAD_EM * fade * _label.get_theme_font_size(&"font_size"))
	_blur_now = BLUR_IN * (1.0 - appear) + BLUR_OUT * fade
	(_blur.material as ShaderMaterial).set_shader_parameter(&"blur_px", _blur_now)
	_layout(RISE * (1.0 - appear) + DRIFT * fade)


## Текущее размытие, px — для проверок.
func blur_px() -> float:
	return _blur_now


## Ширина — по тексту, но не шире MAX_WIDTH: короткая реакция не должна тащить
## за собой пятно тени на пол-экрана, а длинная — уходить за край.
func _layout(offset_y: float) -> void:
	var font_size := _label.get_theme_font_size(&"font_size")
	var natural := _font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := minf(ceilf(natural) + 4.0, MAX_WIDTH)
	_label.size = Vector2(width, 0.0)
	_label.size.y = _label.get_minimum_size().y
	_label.position = Vector2(-width / 2.0, offset_y)
	var margin := Vector2(46.0, 16.0)
	_shadow.position = _label.position - margin
	_shadow.size = _label.size + margin * 2.0
