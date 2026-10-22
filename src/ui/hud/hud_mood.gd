# res://src/ui/hud/hud_mood.gd
## Общая математика HUD «Отголосок» (числа из «HUD — спека» §3, §8, §9): палитра, кривая распада, смятение T, шум. Отдельным файлом, чтобы дуга, эффекты, прицел и строки-мысли дышали одной кривой
## и тактом. Статика без состояния: такт — с часов движка, а не с накопленного delta.
class_name UI_HudMood
extends RefCounted

# --- Палитра (§3) ------------------------------------------------------------
# Токены — «Конвенции проекта» §3; тема и шейдеры повторяют числа (ссылаться на константу не могут).

const SOUL := Color(0.79, 0.66, 0.95)
const SOUL_KEY := Color(0.83, 0.72, 0.97)
const OVER := Color(0.95, 0.91, 1.0)
## Янтарь притушен: ярким спорил с аварийными лампами комплекса.
const BODY := Color(0.94, 0.75, 0.38)
const TEXT := Color(0.93, 0.91, 0.95)
const TEXT_DIM := Color(0.71, 0.68, 0.75)
const DOT := Color(0.95, 0.93, 0.97, 0.85)
## Крестик захвата — сиреневый: красный теперь значит тело и кровь.
const CROSS := Color(0.86, 0.77, 1.0, 0.95)
const TRACK := Color(0.93, 0.91, 0.95, 0.14)
const DECAY_TINT := Color(0.07, 0.04, 0.12)
const BODY_TINT := Color(0.11, 0.07, 0.02)
const BODY_SEPIA := Color(1.0, 0.85, 0.62)
const BLOOD := Color(0.43, 0.05, 0.05)
## Заливка шкалы здоровья: кровь светлее — тёмно-бордовая тонула в полумраке.
const HEALTH := Color(0.78, 0.18, 0.16)
## Градиент «тени мысли» (thought_shadow.tres) повторяет это число.
const SHADOW_BLOB := Color(0.02, 0.02, 0.04, 0.55)

# --- Пороги дуги (§7) ---

## Ниже — дуга горит всегда и бьётся в такт сердцу.
const DANGER := 0.15
## Ниже — дуга видна постоянно, но спокойно.
const LOW := 0.35


## Снимок запасов игрока на кадр — для дуги и эффектов экрана.
class Vitals:
	extends RefCounted
	## Убывает карман тела, а не душа — по НАЛИЧИЮ C_BodyDecay (как решает S_Lifespan).
	var body_pocket := false
	## Доля запаса души, излишек срезан до 1 (§7).
	var soul := 1.0
	## Излишек сверх максимума в долях максимума, 0…1.
	var overflow := 0.0
	var body := 1.0
	## Доля HP тела; 1, если тела нет.
	var health := 1.0
	var has_health := false
	## Максимум убывающего кармана: его скачок (перк) — «заметное изменение».
	var maximum := 0.0

	## Доля убывающего кармана — её показывает дуга.
	func active() -> float:
		return body if body_pocket else soul


## Снимок с игрока; null — игрока нет (HUD гаснет).
static func read_vitals(player: Entity) -> Vitals:
	if player == null:
		return null
	var v := Vitals.new()
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life:
		# Потолок эффективный: перк на запас обязан сдвинуть дугу.
		var soul_max := maxf(life.effective_max(player), 0.001)
		v.soul = minf(life.current / soul_max, 1.0)
		v.overflow = minf(life.overflow(player) / soul_max, 1.0)
		v.maximum = soul_max
	var body_decay := player.get_component(C_BodyDecay) as C_BodyDecay
	if body_decay:
		var body_max := maxf(body_decay.effective_maximum(player), 0.001)
		v.body_pocket = true
		v.body = clampf(body_decay.remaining / body_max, 0.0, 1.0)
		v.maximum = body_max
	var hp := player.get_component(C_Health) as C_Health
	if hp:
		v.has_health = true
		v.health = clampf(hp.current / maxf(hp.effective_maximum(player), 0.001), 0.0, 1.0)
	return v


## smoothstep от a к b, в том числе при a > b — спека пишет пороги распада «сверху вниз».
static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Сила распада d по доле запаса f (§8): плавная треть до 0.15 и резкий рост ниже — эффекты не давят постоянно.
static func decay(f: float) -> float:
	return 0.35 * sstep(LOW, DANGER, f) + 0.65 * pow(sstep(DANGER, 0.0, f), 1.5)


## Сердцебиение 0…1: пик раз в период, который сжимается с распадом.
static func beat(d: float, t: float = now()) -> float:
	var period := 1.2 - 0.65 * d
	return pow(maxf(0.0, sin(TAU * t / period)), 6.0)


## Смятение T (§9): рваность дуги, дрожь эха, излом крестика; тает с числом поглощённых за забег.
static func turmoil() -> float:
	var stats := RunStats.current
	var absorbed := stats.value(RS_RunStats.BODIES) if stats else 0.0
	return 0.25 + 0.75 * exp(-absorbed / 6.0)


## Три синусоиды вместо шума из текстуры: гладкий периодический по углу, без шва на замыкании дуги.
static func noise(a: float, s: float) -> float:
	return 0.5 * sin(3.0 * a + s) + 0.3 * sin(7.0 * a + 1.7 + 1.3 * s) + 0.2 * sin(13.0 * a + 0.4 + 0.7 * s)


## Общие часы HUD, секунды — с движка, не накопленным delta.
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Экспонента к цели с постоянной времени tau (появление и угасание); не зависит от частоты кадров.
static func approach(value: float, target: float, tau: float, delta: float) -> float:
	return value + (target - value) * (1.0 - exp(-delta / maxf(tau, 0.0001)))


## «Эхо» мысли — тень Label, сдвинутая и дрожащая на смятение (§5); [param phase] разводит строки.
static func apply_echo(label: Label, phase: float = 0.0) -> void:
	var offset := echo_offset(turmoil(), phase)
	label.add_theme_constant_override("shadow_offset_x", roundi(offset.x))
	label.add_theme_constant_override("shadow_offset_y", roundi(offset.y))


## Сдвиг эха при смятении: одна формула на HUD и меню («Меню — спека» §1), при T = 0.6 даёт амплитуду макетов меню.
static func echo_offset(turmoil_now: float, phase: float = 0.0) -> Vector2:
	var t := now()
	return Vector2(
		1.0 + 2.0 * turmoil_now + 1.2 * turmoil_now * noise(t * 9.0 + phase, 0.3),
		0.6 * turmoil_now * noise(t * 7.0 + phase, 1.9),
	)
