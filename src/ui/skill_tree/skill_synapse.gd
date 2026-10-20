# res://src/ui/skill_tree/skill_synapse.gd
## Синапс — связь-требование между нейронами (§9 «Меню — спека»): рваная линия от края до края. Состояния: горит (зависимый изучен) — сиреневый 1.8 px; доступна — светлая 1.2 px; закрыта — пунктир 1:3.
## Рваность статична (живая рябила бы), амплитуда растёт со смятением T; узор у каждого свой (seed).
class_name UI_SkillSynapse
extends Control

enum State { LOCKED, AVAILABLE, LIT }

## Амплитуда излома при T = 0.6 и шаг излома вдоль линии.
const AMPLITUDE := 3.2
const KINK_STEP := 14.0
## Синапс упирается в край нейрона, а не в центр.
const NEURON_RADIUS := 22.0
## Прорисовка зажжённого покупкой синапса (§7: 600 мс).
const FRESH_TIME := 0.6

var state := State.LOCKED
var seed_value := 0.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _fresh := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Концы — центры нейронов в координатах полотна.
func connect_points(from_center: Vector2, to_center: Vector2, new_state: State) -> void:
	_from = from_center
	_to = to_center
	state = new_state
	queue_redraw()


## Только что открытый навык: синапс к нему прорисовывается от требования.
func play_fresh() -> void:
	_fresh = 0.0


func points(progress: float = 1.0) -> PackedVector2Array:
	var direction := _to - _from
	var length := direction.length()
	var result := PackedVector2Array()
	if length <= NEURON_RADIUS * 2.0:
		return result
	var unit := direction / length
	var normal := Vector2(-unit.y, unit.x)
	var start := _from + unit * NEURON_RADIUS
	var span := length - NEURON_RADIUS * 2.0
	var steps := maxi(2, int(span / KINK_STEP))
	var amplitude := AMPLITUDE * UI_MenuStyle.turmoil() / UI_MenuStyle.OUT_OF_RUN_TURMOIL
	var last := int(steps * clampf(progress, 0.0, 1.0))
	for i in last + 1:
		var k := float(i) / steps
		# Концы ровные: излом гаснет к нейронам.
		var fade := sin(k * PI)
		var offset := UI_HudMood.noise(k * 9.0, seed_value) * amplitude * fade
		result.append(start + unit * span * k + normal * offset)
	return result


func _process(delta: float) -> void:
	if _fresh >= 0.0:
		_fresh += delta / FRESH_TIME
		if _fresh >= 1.0:
			_fresh = -1.0
		queue_redraw()


func _draw() -> void:
	var line := points()
	if line.size() < 2:
		return
	match state:
		State.LIT:
			draw_polyline(line, Color(UI_HudMood.SOUL, 0.85), 1.8, true)
		State.AVAILABLE:
			draw_polyline(line, Color(UI_MenuStyle.TEXT, 0.45), 1.2, true)
		State.LOCKED:
			_draw_dotted(line, Color(UI_MenuStyle.TEXT, 0.22))
	if _fresh >= 0.0:
		var drawn := points(ease(_fresh, 0.5))
		if drawn.size() >= 2:
			draw_polyline(drawn, UI_HudMood.OVER, 2.2, true)


## Пунктир 1:3 вдоль ломаной.
func _draw_dotted(line: PackedVector2Array, color: Color) -> void:
	var carry := 0.0
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var length := a.distance_to(b)
		var d := carry
		while d < length:
			draw_circle(a.lerp(b, d / length), 0.6, color)
			d += 4.0
		carry = d - length
