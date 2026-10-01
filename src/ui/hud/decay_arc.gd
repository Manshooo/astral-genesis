# res://src/ui/hud/decay_arc.gd
## Дуга у прицела — единственный показатель запаса (§7 «HUD — спека»). Одна на
## всё: показывает тот карман, что сейчас убывает. Вне тела — запас души, во
## плоти — карман тела; кто из них, говорит цвет, а не подпись.
##
## Видна не всегда: загорается на заметное изменение и у порога, гаснет, когда
## всё спокойно. Ровное убывание заметным не считается — иначе в ранней игре,
## где минута запаса тает на глазах, дуга не гасла бы никогда.
##
## Значения меняются непрерывно, поэтому опрашиваем игрока каждый кадр — как
## прежние полосы: событийная модель тут проигрывает простому поллингу.
class_name UI_DecayArc
extends Control

const RADIUS := 22.0
## Раствор и начало дуги: зазор 80° внизу оставлен под подсказку, чтобы
## строка под прицелом не упиралась в шкалу.
const SWEEP_DEG := 280.0
const START_DEG := 130.0
## Шаг ломаной, градусы: мельче — не видно разницы, крупнее — видны изломы.
const STEP_DEG := 3.0
## Сколько держать дугу после заметного изменения.
const HOLD_SECONDS := 1.4
## Заметное изменение: столько доли за окно.
const NOTABLE_DELTA := 0.05
const NOTABLE_WINDOW := 0.5
const APPEAR_TAU := 0.12
const FADE_TAU := 0.5
## Кроссфейд сиреневого и янтаря на вселении и выходе.
const TINT_SECONDS := 0.25

## Прозрачность, к которой дуга идёт сейчас. Открыта для проверок: правило
## «когда видна» — главное, что здесь можно сломать молча.
var target_alpha := 0.0

var _alpha := 0.0
## 0 — тон души, 1 — тон тела.
var _body_mix := 0.0
var _vitals: UI_HudMood.Vitals
var _last_notable := -INF
var _sample_value := -1.0
var _sample_time := -INF
var _last_pocket := false
var _last_maximum := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	update_state(UI_HudMood.read_vitals(E_Player.find()), UI_HudMood.now(), delta)
	if _alpha > 0.002 or target_alpha > 0.0:
		queue_redraw()


## Шаг логики отдельно от _process: проверка подаёт запасы и время сама, не
## дожидаясь кадров движка и не собирая игрока.
func update_state(vitals: UI_HudMood.Vitals, t: float, delta: float) -> void:
	_vitals = vitals
	if _vitals == null:
		target_alpha = 0.0
		_alpha = UI_HudMood.approach(_alpha, 0.0, FADE_TAU, delta)
		return

	var active := _vitals.active()
	_track_notable(active, t)

	if active < UI_HudMood.DANGER:
		target_alpha = 1.0
	elif active < UI_HudMood.LOW:
		target_alpha = 0.75
	elif t - _last_notable < HOLD_SECONDS or _vitals.overflow > 0.0:
		# Излишек виден всё время, пока он есть: он утекает быстрее обычного
		# запаса, и игрок должен видеть, что тратит именно его.
		target_alpha = 0.9
	else:
		target_alpha = 0.0
	var tau := APPEAR_TAU if target_alpha > _alpha else FADE_TAU
	_alpha = UI_HudMood.approach(_alpha, target_alpha, tau, delta)

	var mix_target := 1.0 if _vitals.body_pocket else 0.0
	_body_mix = move_toward(_body_mix, mix_target, delta / TINT_SECONDS)


## Заметно: смена кармана (вселение, выход, пересадка), скачок максимума (перк)
## или сдвиг доли на NOTABLE_DELTA за окно. Окно, а не сравнение с прошлым
## кадром: за кадр любое изменение крошечное.
func _track_notable(active: float, t: float) -> void:
	var pocket_changed := _vitals.body_pocket != _last_pocket
	var max_changed := absf(_vitals.maximum - _last_maximum) > 0.01 * maxf(_last_maximum, 1.0)
	if pocket_changed or max_changed or _sample_value < 0.0:
		_last_notable = t
		_sample_value = active
		_sample_time = t
	elif t - _sample_time >= NOTABLE_WINDOW:
		if absf(active - _sample_value) >= NOTABLE_DELTA:
			_last_notable = t
		_sample_value = active
		_sample_time = t
	_last_pocket = _vitals.body_pocket
	_last_maximum = _vitals.maximum


func _draw() -> void:
	if _vitals == null or _alpha <= 0.002:
		return
	var t := UI_HudMood.now()
	var turmoil := UI_HudMood.turmoil()
	var center := size / 2.0
	var active := _vitals.active()
	var radius := RADIUS + 0.6 * sin(t * 2.1)
	var amp := 0.4 + 1.8 * turmoil
	var seed := t * 0.6
	var color := UI_HudMood.SOUL.lerp(UI_HudMood.BODY, _body_mix)

	# У порога дуга бьётся в такт сердцу. У тела такт свой и ровный: распад тела
	# не убивает, а выбрасывает, и частить ему незачем.
	var danger := active < UI_HudMood.DANGER
	var beat := (
		pow(maxf(0.0, sin(TAU * t / 0.8)), 4.0) if _vitals.body_pocket
		else UI_HudMood.beat(UI_HudMood.decay(active), t)
	)
	var alpha := _alpha * (0.6 + 0.4 * beat if danger else 1.0)

	_draw_track(center, radius, alpha)
	var echo := _arc(center, radius + 1.3, active, amp * 1.5, seed * 1.4 + 3.2)
	_stroke(echo, _with_alpha(color, 0.35 * alpha), 1.0)
	var main := _arc(center, radius, active, amp, seed)
	_stroke(main, _with_alpha(color, alpha), 2.0 + 0.8 * beat if danger else 2.0)

	var over := not _vitals.body_pocket and _vitals.overflow > 0.0
	if not main.is_empty():
		draw_circle(main[-1], 1.8, _with_alpha(UI_HudMood.OVER if over else color, alpha))
	if over:
		_draw_overflow(center, radius, amp, seed, t, alpha)


## Излишек — внешней дугой, а не растяжкой шкалы: «полный» остаётся там же, где
## был, а сверху видно, сколько принесено из тела. Искры уходят наружу —
## излишек утекает быстрее (lifespan_overflow_leak), и это должно читаться.
func _draw_overflow(center: Vector2, radius: float, amp: float, seed: float, t: float, alpha: float) -> void:
	var extra := _vitals.overflow
	_stroke(_arc(center, radius + 7.0, extra, amp * 0.8, seed + 5.1), _with_alpha(UI_HudMood.OVER, alpha), 1.3)
	_stroke(
		_arc(center, radius + 8.5, extra, amp * 1.6, seed * 1.3 + 6.3),
		_with_alpha(UI_HudMood.OVER, 0.35 * alpha), 1.0
	)
	for i in 5:
		var phase := fmod(t * 0.55 + i / 5.0, 1.0)
		var along := fmod(i * 0.37 + 0.11, 1.0)
		var angle := deg_to_rad(START_DEG + SWEEP_DEG * extra * along)
		var spark := center + Vector2.from_angle(angle) * (radius + 7.0 + 14.0 * phase)
		draw_circle(spark, 1.1, _with_alpha(UI_HudMood.OVER, (1.0 - phase) * 0.8 * alpha))


## Пустая часть — пунктиром 1:3 по всей длине, чтобы было видно, сколько
## дуге ещё есть куда убывать.
func _draw_track(center: Vector2, radius: float, alpha: float) -> void:
	var color := _with_alpha(UI_HudMood.TRACK, UI_HudMood.TRACK.a * alpha)
	var dash := 1.0 / radius
	var step := 4.0 / radius
	var a := deg_to_rad(START_DEG)
	var end := deg_to_rad(START_DEG + SWEEP_DEG)
	var segments := PackedVector2Array()
	while a < end:
		var r := radius + 0.2 * UI_HudMood.noise(a, 1.0)
		segments.append(center + Vector2.from_angle(a) * r)
		segments.append(center + Vector2.from_angle(a + dash) * r)
		a += step
	if not segments.is_empty():
		draw_multiline(segments, color, 1.0)


## Ломаная дуги с рваным радиусом. Доля ≤ 0.002 — пусто: точка-огрызок на
## нуле читалась бы как «ещё немного есть».
func _arc(center: Vector2, radius: float, fraction: float, amp: float, seed: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if fraction <= 0.002:
		return points
	var count := maxi(2, floori(SWEEP_DEG * fraction / STEP_DEG) + 1)
	for i in count + 1:
		var angle := deg_to_rad(START_DEG + SWEEP_DEG * fraction * i / count)
		var r := radius + amp * UI_HudMood.noise(angle, seed)
		points.append(center + Vector2.from_angle(angle) * r)
	return points


## Скруглённые концы: у draw_polyline их нет, а рубленый торец на 2 px толщины
## выглядит прибором, а не ощущением.
func _stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, color, width, true)
	draw_circle(points[0], width / 2.0, color)
	draw_circle(points[-1], width / 2.0, color)


static func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
