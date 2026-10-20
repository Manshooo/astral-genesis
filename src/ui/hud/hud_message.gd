# res://src/ui/hud/hud_message.gd
## Экранное сообщение («Заперто…», «Прохода нет») на добавление C_ScreenMessage на игрока; подаётся мыслью — проявляется, держится, растворяется (§6 «HUD — спека»). Своя строка ниже подсказки.
## Таймлайн свой: на снятие компонента строка должна раствориться, S_ScreenMessage держит компонент столько же (TOTAL). Текст — ключ перевода или готовая строка (tr() вернёт как есть).
class_name UI_HudMessage
extends Control

const APPEAR := 0.3
const HOLD := 1.7
const FADE := 0.9
const TOTAL := APPEAR + HOLD + FADE
## Длиннее переносится на вторую строку.
const MAX_WIDTH := 720.0
## Растворение: растяжение вширь (доля ширины) и сдвиг — трансформ группы Blur, не поля Label (те округляются до пикселей и дают ступеньки).
const SPREAD := 0.22
const DRIFT := -6.0
const RISE := 3.0
## Размытие, px: фокусируется на проявлении, расплывается в растворении.
const BLUR_IN := 4.0
const BLUR_OUT := 5.0

@onready var _shadow: TextureRect = $Blur/ThoughtShadow
@onready var _label: UI_ThoughtLabel = $Blur/Text
@onready var _blur: CanvasGroup = $Blur

## Время показа по часам HUD; -INF — сообщения нет.
var _started := -INF
var _blur_now := 0.0


func _ready() -> void:
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


## Показать заново — новое сообщение перебивает старое.
func show_line(line: String) -> void:
	_label.text = tr(line)
	_started = UI_HudMood.now()
	_apply(0.0)


## Что сейчас на экране — для проверок.
func shown_text() -> String:
	return _label.text if visible else ""


func _process(_delta: float) -> void:
	if _started == -INF:
		return
	_apply(UI_HudMood.now() - _started)


## Состояние строки через elapsed секунд после показа.
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
	# Группа в центре сообщения — растяжение по X идёт от середины.
	_blur.scale = Vector2(1.0 + SPREAD * fade, 1.0)
	_blur.position.y = RISE * (1.0 - appear) + DRIFT * fade
	_blur_now = BLUR_IN * (1.0 - appear) + BLUR_OUT * fade
	(_blur.material as ShaderMaterial).set_shader_parameter(&"blur_px", _blur_now)
	_layout()


## Текущее размытие, px — для проверок.
func blur_px() -> float:
	return _blur_now


## Ширина — по тексту, не шире MAX_WIDTH (пятно тени коротких реакций).
func _layout() -> void:
	var font_size := _label.get_theme_font_size(&"font_size")
	var natural := _label.get_theme_font(&"font").get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var width := minf(ceilf(natural) + 4.0, MAX_WIDTH)
	_label.size = Vector2(width, 0.0)
	_label.size.y = _label.get_minimum_size().y
	_label.position = Vector2(-width / 2.0, 0.0)
	var margin := Vector2(46.0, 16.0)
	_shadow.position = _label.position - margin
	_shadow.size = _label.size + margin * 2.0
