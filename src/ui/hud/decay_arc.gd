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
## Шаг ломаной, градусы: на виток жгута приходится ~20 точек — мельче не видно
## разницы, крупнее спираль ломается в зигзаг.
const STEP_DEG := 2.0
## Жгут: основная линия и её эхо вьются двойной спиралью вдоль дуги.
## Длина витка вдоль дуги, px, и сколько витков в секунду пробегает к концу.
const WAVE_PX := 16.0
const WAVE_RATE := 0.8
## Радиус витка, px: база плюс прибавка от смятения — первое тело вьётся
## размашисто, к шестому спокойнее.
const HELIX_PX := 0.9
const HELIX_TURMOIL_PX := 0.8
## Нить эха и задние куски обеих нитей — тусклее.
const ECHO_ALPHA := 0.45
const BACK_ALPHA := 0.45
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
	var helix := HELIX_PX + HELIX_TURMOIL_PX * turmoil
	var main := _strand(center, radius + 0.65, active, amp, seed, t, helix, 0.0)
	var echo := _strand(center, radius + 0.65, active, amp, seed, t, helix, PI)
	_draw_braid(
		main, _with_alpha(color, alpha), 2.0 + 0.8 * beat if danger else 2.0,
		echo, _with_alpha(color, ECHO_ALPHA * alpha), 1.0
	)

	var over := not _vitals.body_pocket and _vitals.overflow > 0.0
	var main_points: PackedVector2Array = main.points
	if not main_points.is_empty():
		draw_circle(main_points[-1], 1.8, _with_alpha(UI_HudMood.OVER if over else color, alpha))
	if over:
		_draw_overflow(center, radius, amp, seed, t, alpha, helix)


## Излишек — внешней дугой, а не растяжкой шкалы: «полный» остаётся там же, где
## был, а сверху видно, сколько принесено из тела. Искры уходят наружу —
## излишек утекает быстрее (lifespan_overflow_leak), и это должно читаться.
func _draw_overflow(
	center: Vector2, radius: float, amp: float, seed: float, t: float, alpha: float, helix: float
) -> void:
	var extra := _vitals.overflow
	# Свой жгут, свита в другую сторону: два жгута, бегущие одинаково, сливались
	# бы в одну широкую ленту.
	_draw_braid(
		_strand(center, radius + 7.75, extra, amp * 0.8, seed + 5.1, -t, helix, 0.0),
		_with_alpha(UI_HudMood.OVER, alpha), 1.3,
		_strand(center, radius + 7.75, extra, amp * 0.8, seed + 5.1, -t, helix, PI),
		_with_alpha(UI_HudMood.OVER, ECHO_ALPHA * alpha), 1.0
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


## Одна нить жгута: рваная средняя линия дуги плюс виток вокруг неё. Две нити
## с фазами 0 и π — двойная спираль. Виток бежит вдоль дуги от начала к концу,
## поэтому дуга не стоит, а течёт. depth — косинус витка: > 0 — нить спереди.
## Доля ≤ 0.002 — пусто: точка-огрызок на нуле читалась бы как «ещё немного
## есть».
func _strand(
	center: Vector2, radius: float, fraction: float, amp: float, seed: float,
	t: float, helix: float, phase: float
) -> Dictionary:
	var points := PackedVector2Array()
	var depth := PackedFloat32Array()
	if fraction > 0.002:
		var count := maxi(2, floori(SWEEP_DEG * fraction / STEP_DEG) + 1)
		var start := deg_to_rad(START_DEG)
		for i in count + 1:
			var angle := start + deg_to_rad(SWEEP_DEG * fraction) * i / count
			var turn := TAU * ((angle - start) * radius / WAVE_PX - t * WAVE_RATE) + phase
			var r := radius + amp * UI_HudMood.noise(angle, seed) + helix * sin(turn)
			points.append(center + Vector2.from_angle(angle) * r)
			depth.append(cos(turn))
	return {points = points, depth = depth}


## Две нити жгута, переплетённые: сначала задние куски обеих, тусклее, потом
## передние поверх. Порядок и тусклость и дают объём — одной толщиной спираль
## читалась бы плоской волной.
func _draw_braid(a: Dictionary, a_color: Color, a_width: float, b: Dictionary, b_color: Color, b_width: float) -> void:
	for front: bool in [false, true]:
		for strand: Array in [[a, a_color, a_width], [b, b_color, b_width]]:
			var color: Color = strand[1]
			if not front:
				color.a *= BACK_ALPHA
			# Скруглённые концы — рубленый торец на 2 px выглядит прибором, — но
			# только настоящие концы нити: кружок на каждом стыке переднего и
			# заднего куска ложился бы поверх нити светлой бусиной.
			var ends: PackedVector2Array = strand[0].points
			for run in _runs(strand[0], front):
				draw_polyline(run, color, strand[2], true)
				for cap: Vector2 in [run[0], run[-1]]:
					if cap == ends[0] or cap == ends[-1]:
						draw_circle(cap, strand[2] / 2.0, color)


## Куски нити, лежащие целиком спереди (или сзади). Граница — где виток уходит
## за соседку; точку на границе получают оба куска, чтобы нить не рвалась.
static func _runs(strand: Dictionary, front: bool) -> Array[PackedVector2Array]:
	var points: PackedVector2Array = strand.points
	var depth: PackedFloat32Array = strand.depth
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in points.size() - 1:
		if ((depth[i] + depth[i + 1]) > 0.0) == front:
			if run.is_empty():
				run.append(points[i])
			run.append(points[i + 1])
		elif not run.is_empty():
			runs.append(run)
			run = PackedVector2Array()
	if run.size() >= 2:
		runs.append(run)
	return runs


static func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
