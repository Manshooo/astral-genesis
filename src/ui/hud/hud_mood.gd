# res://src/ui/hud/hud_mood.gd
## Общая математика HUD «Отголосок»: палитра, кривая распада, смятение T, шум.
##
## Зачем отдельным файлом: дуга, эффекты экрана, прицел и строки-мысли обязаны
## «дышать» одной и той же кривой и в одном такте. Распад у порога — это и
## виньетка, и пульс дуги, и сердцебиение; разойдись формулы по узлам, удар
## сердца на экране и на дуге пришёлся бы в разные моменты. Числа — из спеки
## «HUD — спека» (§3, §8, §9), здесь их единственное место в коде.
##
## Только статика и без состояния: такт берётся с часов движка, а не с
## накопленного delta, поэтому любой узел получает одну и ту же фазу, не
## договариваясь с остальными.
class_name UI_HudMood
extends RefCounted

# --- Палитра (§3) ------------------------------------------------------------

const SOUL := Color(0.79, 0.66, 0.95)
const SOUL_KEY := Color(0.83, 0.72, 0.97)
const OVER := Color(0.95, 0.91, 1.0)
## Янтарь притушен против прежней полосы (1, 0.85, 0.4): ярким он спорил с
## аварийными лампами комплекса.
const BODY := Color(0.94, 0.75, 0.38)
const DOT := Color(0.95, 0.93, 0.97, 0.85)
## Крестик захвата — сиреневый, а не красный: красный теперь значит тело и кровь.
const CROSS := Color(0.86, 0.77, 1.0, 0.95)
const TRACK := Color(0.93, 0.91, 0.95, 0.14)
const DECAY_TINT := Color(0.07, 0.04, 0.12)
const BODY_TINT := Color(0.11, 0.07, 0.02)
const BODY_SEPIA := Color(1.0, 0.85, 0.62)
const BLOOD := Color(0.43, 0.05, 0.05)
const SHADOW_BLOB := Color(0.02, 0.02, 0.04, 0.55)

# --- Пороги дуги (§7) --------------------------------------------------------

## Ниже — дуга горит всегда и бьётся в такт сердцу.
const DANGER := 0.15
## Ниже — дуга видна постоянно, но спокойно.
const LOW := 0.35


## Снимок запасов игрока на кадр — то, что читают дуга и эффекты экрана.
class Vitals:
	extends RefCounted
	## Убывает карман тела, а не душа. По НАЛИЧИЮ кармана (C_BodyDecay), а не по
	## флагу «во плоти» — тем же правилом решает S_Lifespan, что тикает: тело без
	## кармана укрытия не даёт, и показывать его пустую шкалу было бы враньём.
	var body_pocket := false
	## Доля запаса души, излишек срезан до 1 — шкала не растягивается (§7).
	var soul := 1.0
	## Излишек сверх максимума в долях максимума, 0…1.
	var overflow := 0.0
	var body := 1.0
	## Доля HP тела; 1, если тела нет — у души прочности нет вовсе.
	var health := 1.0
	var has_health := false
	## Максимум того кармана, что убывает: его скачок (перк) — «заметное изменение».
	var maximum := 0.0

	## Доля того кармана, что сейчас убывает, — её и показывает дуга.
	func active() -> float:
		return body if body_pocket else soul


## Снимок с игрока. null — игрока нет (загрузка, смерть): HUD гаснет.
static func read_vitals(player: Entity) -> Vitals:
	if player == null:
		return null
	var v := Vitals.new()
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life:
		# Потолок эффективный, а не авторский: перк на запас обязан сдвинуть
		# дугу, иначе прокачка читается как «ничего не изменилось».
		var soul_max := maxf(life.effective_max(player), 0.001)
		v.soul = minf(life.current / soul_max, 1.0)
		v.overflow = minf(life.overflow(player) / soul_max, 1.0)
		v.maximum = soul_max
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	if decay:
		var body_max := maxf(decay.effective_maximum(player), 0.001)
		v.body_pocket = true
		v.body = clampf(decay.remaining / body_max, 0.0, 1.0)
		v.maximum = body_max
	var hp := player.get_component(C_Health) as C_Health
	if hp:
		v.has_health = true
		v.health = clampf(hp.current / maxf(hp.effective_maximum(player), 0.001), 0.0, 1.0)
	return v


## smoothstep, растущий от [param a] к [param b] — в том числе когда a > b:
## спека пишет пороги распада «сверху вниз» (S(0.35→0.15, f)), и разворачивать
## их в голове при каждом чтении — верный способ ошибиться знаком.
static func sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Сила распада d по доле запаса f (§8). Две ступени, а не одна кривая: ранний
## запас — около минуты, и игрок почти всегда «на исходе». Плавная треть силы до
## 0.15 и резкий рост ниже — чтобы эффекты не давили постоянно.
static func decay(f: float) -> float:
	return 0.35 * sstep(LOW, DANGER, f) + 0.65 * pow(sstep(DANGER, 0.0, f), 1.5)


## Сердцебиение 0…1: короткий пик раз в период, который сжимается по мере
## распада — сердце частит у порога.
static func beat(d: float, t: float = now()) -> float:
	var period := 1.2 - 0.65 * d
	return pow(maxf(0.0, sin(TAU * t / period)), 6.0)


## Смятение T (§9): рваность дуги, дрожь эха, излом крестика. Тает с числом
## поглощённых за забег сознаний — первое тело резкое и безумное, к шестому
## спокойнее, но не до мёртвой ровности.
static func turmoil() -> float:
	var stats := RunStats.current
	var absorbed := stats.value(RS_RunStats.BODIES) if stats else 0.0
	return 0.25 + 0.75 * exp(-absorbed / 6.0)


## Три синусоиды вместо шума из текстуры: дуга и крестик рисуются ломаной в
## _draw(), и гладкий периодический шум по углу не даёт шва там, где дуга
## замыкается сама на себя.
static func noise(a: float, s: float) -> float:
	return 0.5 * sin(3.0 * a + s) + 0.3 * sin(7.0 * a + 1.7 + 1.3 * s) + 0.2 * sin(13.0 * a + 0.4 + 0.7 * s)


## Общие часы HUD, секунды. С движка, а не накопленным delta: см. шапку файла.
static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Экспонента к цели с постоянной времени [param tau] — так в спеке заданы
## появление и угасание (τ). Не зависит от частоты кадров.
static func approach(value: float, target: float, tau: float, delta: float) -> float:
	return value + (target - value) * (1.0 - exp(-delta / maxf(tau, 0.0001)))


## «Эхо» мысли — тень Label, сдвинутая и дрожащая на смятение (§5). Тема даёт
## статичные (2, 0); здесь — переопределение узла, а не своя тема сцены.
## [param phase] разводит строки, чтобы эхо управления не дрожало хором.
static func apply_echo(label: Label, phase: float = 0.0) -> void:
	var offset := echo_offset(turmoil(), phase)
	label.add_theme_constant_override("shadow_offset_x", roundi(offset.x))
	label.add_theme_constant_override("shadow_offset_y", roundi(offset.y))


## Сдвиг эха от строки при смятении [param turmoil_now]. Одна формула на HUD и
## меню («Меню — спека» §1): эхо меню обязано успокаиваться вместе с HUD, а две
## копии формулы разошлись бы при первой же правке. При T = 0.6 даёт (1.2…2.8,
## −0.4…0.6) — ровно амплитуду макетов меню.
static func echo_offset(turmoil_now: float, phase: float = 0.0) -> Vector2:
	var t := now()
	return Vector2(
		1.0 + 2.0 * turmoil_now + 1.2 * turmoil_now * noise(t * 9.0 + phase, 0.3),
		0.6 * turmoil_now * noise(t * 7.0 + phase, 1.9),
	)


## Материал размытия строки-мысли для её CanvasGroup. Свой на каждую группу:
## размытие у подсказки и у сообщения идёт по разным часам.
static func blur_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/ui/hud/thought_blur.gdshader")
	return material


## Пятно «тени мысли» позади строки (§2): радиальный градиент без формы вместо
## подложки. Строится кодом, потому что нужен один и тот же везде, где HUD
## говорит текстом.
static func thought_shadow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	var clear := SHADOW_BLOB
	clear.a = 0.0
	gradient.set_color(0, SHADOW_BLOB)
	gradient.set_color(1, clear)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 64
	return texture
