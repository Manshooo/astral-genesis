# res://src/ui/hud/health_bar.gd
## Шкала здоровья тела внизу по центру: кровь по краю говорит «больно», шкала —
## «сколько осталось». [[HUD — спека]] §7а.
class_name UI_HealthBar
extends Control

const WIDTH := 240.0
const THICKNESS := 4.0
## Полное тело — тусклая шкала, раненое — в полную силу.
const IDLE_ALPHA := 0.35
const HURT_ALPHA := 0.95
const APPEAR_TAU := 0.12
const FADE_TAU := 0.4
## След потерянного догоняет текущее HP: удар читается величиной, а не только
## новым концом шкалы.
const TRAIL_TAU := 0.6
const TRAIL_ALPHA := 0.45

## Прозрачность, к которой шкала идёт сейчас (для проверок).
var target_alpha := 0.0

var _alpha := 0.0
var _health := 1.0
var _trail := 1.0
var _shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	update_state(UI_HudMood.read_vitals(E_Player.find()), delta)
	if _alpha > 0.002 or target_alpha > 0.0:
		queue_redraw()


func update_state(vitals: UI_HudMood.Vitals, delta: float) -> void:
	var embodied := vitals != null and vitals.has_health
	if embodied:
		# Новое тело — не лечение: след не тянется вверх от прошлого.
		if not _shown or vitals.health > _health:
			_trail = vitals.health
		_health = vitals.health
		target_alpha = IDLE_ALPHA if _health >= 0.999 else HURT_ALPHA
	else:
		target_alpha = 0.0
	_shown = embodied
	_trail = maxf(_health, UI_HudMood.approach(_trail, _health, TRAIL_TAU, delta))
	_alpha = UI_HudMood.approach(_alpha, target_alpha, APPEAR_TAU if target_alpha > _alpha else FADE_TAU, delta)


func health() -> float:
	return _health


func trail() -> float:
	return _trail


func _draw() -> void:
	if _alpha <= 0.002:
		return
	var from := Vector2((size.x - WIDTH) / 2.0, size.y / 2.0)
	var to := from + Vector2(WIDTH, 0.0)
	var at := func(share: float) -> Vector2: return from.lerp(to, share)
	var track := UI_HudMood.TRACK
	track.a *= _alpha / HURT_ALPHA
	draw_line(from, to, track, THICKNESS)
	var hurt := UI_HudMood.HEALTH
	if _trail > _health:
		var trail_color := hurt
		trail_color.a = TRAIL_ALPHA * _alpha
		draw_line(at.call(_health), at.call(_trail), trail_color, THICKNESS)
	# У порога шкала бьётся в такт сердцу — тем же тактом, что дуга и кровь.
	var pulse := UI_HudMood.beat(UI_HudMood.decay(_health)) if _health < UI_HudMood.LOW else 0.0
	var fill := hurt.lerp(UI_HudMood.OVER, 0.35 * pulse)
	fill.a = _alpha
	if _health > 0.0:
		draw_line(from, at.call(_health), fill, THICKNESS + pulse)
