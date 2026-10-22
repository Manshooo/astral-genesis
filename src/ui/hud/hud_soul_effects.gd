# res://src/ui/hud/hud_soul_effects.gd
## Эффекты «Бесплотности» — врождённой способности БФЖ — в левой части экрана: полёт и просачивание вне тела. Слотов не занимают (решение 22.10), дизайна эффектов
## ещё нет — временно строками-мыслями в стиле управления. Строка на эффект — инстанс thought_line.tscn: число эффектов задаёт сцена души.
class_name UI_HudSoulEffects
extends Control

const THOUGHT_LINE := preload("res://src/ui/hud/thought_line.tscn")
const LINE_STEP := 28.0
const IDLE_ALPHA := 0.55
const BRIGHT_FOR := 2.5
const APPEAR_TAU := 0.12
const FADE_TAU := 0.4

@onready var _title: UI_ThoughtLine = %Title

var target_alpha := 0.0
var _lines: Array[UI_ThoughtLine] = []
var _bright_until := -INF
var _shown: PackedStringArray = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0
	_title.set_line("", tr("HUD_SOUL_INCORPOREAL"))


func _process(delta: float) -> void:
	var keys := active_effects(E_Player.find())
	if keys != _shown:
		_shown = keys
		_rebuild(keys)
		_bright_until = UI_HudMood.now() + BRIGHT_FOR
	if keys.is_empty():
		target_alpha = 0.0
	else:
		target_alpha = 1.0 if UI_HudMood.now() < _bright_until else IDLE_ALPHA
	var tau := APPEAR_TAU if target_alpha > modulate.a else FADE_TAU
	modulate.a = UI_HudMood.approach(modulate.a, target_alpha, tau, delta)


## Ключи эффектов надетых возможностей души; во плоти они спят — список пуст.
static func active_effects(player: Entity) -> PackedStringArray:
	var keys := PackedStringArray()
	if player == null:
		return keys
	for component in player.components.values():
		var trait_ := component as C_SoulTrait
		if trait_ and trait_.effect_key() != &"":
			keys.append(trait_.effect_key())
	keys.sort()
	return keys


## Видимые строки эффектов — для проверок.
func effect_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for line in _lines:
		lines.append(line.plain_text())
	return lines


func _rebuild(keys: PackedStringArray) -> void:
	for line in _lines:
		line.queue_free()
	_lines.clear()
	for i in keys.size():
		var line: UI_ThoughtLine = THOUGHT_LINE.instantiate()
		line.style = UI_ThoughtLine.Style.CONTROLS
		line.centered = false
		line.shadow_margin = Vector2(30.0, 8.0)
		line.echo_phase = float(i + 2)
		add_child(line)
		line.set_line("", "· " + tr(keys[i]))
		line.position = Vector2(12.0, (i + 1) * LINE_STEP)
		_lines.append(line)
