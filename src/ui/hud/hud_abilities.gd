# res://src/ui/hud/hud_abilities.gd
## Раскладка управления «на сейчас»: что риг умеет ПРЯМО СЕЙЧАС — ход/полёт всегда, прыжок, бег и удар только пока есть C_Jump/C_Sprint/C_Attack (у безногого строки нет, а не серая).
## Видна несколько секунд после смены набора (§6 «HUD — спека»), потом гаснет. Клавиши резолвятся из InputMap по action_name и обновляются после переназначения. События component_added/removed,
## не поллинг: набор дискретен. Четыре строки (UI_ThoughtLine) — в hud.tscn, раскладка кодом (строки въезжают по одной со сдвигом).
class_name UI_HudAbilities
extends Control

const APPEAR := 0.35
## Строки появляются с шагом — список «проговаривается».
const STAGGER := 0.09
const HOLD_UNTIL := 4.0
const FADE := 1.0
const SLIDE := -6.0
## Шаг строк, px, и высота последней: низ последней стоит на точке узла.
const LINE_STEP := 28.0
const LINE_HEIGHT := 22.0

@onready var _move: UI_ThoughtLine = %Move
@onready var _jump: UI_ThoughtLine = %Jump
@onready var _sprint: UI_ThoughtLine = %Sprint
@onready var _attack: UI_ThoughtLine = %Attack
## Время последней смены набора; -INF — показывать нечего.
var _started := -INF
## Набор, который показан: «полёт/ход, прыжок?, бег?». Сравниваем его, а не факт события.
var _signature := ""


func _ready() -> void:
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_render()


func _on_world_changed(world: World) -> void:
	if world:
		_connect_world_signals(world)
	_render()


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_changed):
		world.component_added.connect(_on_component_changed)
	if not world.component_removed.is_connected(_on_component_changed):
		world.component_removed.connect(_on_component_changed)


## Один обработчик на оба события: важно, сменился ли набор возможностей рига.
func _on_component_changed(_entity: Entity, component: Variant) -> void:
	if (
		component is C_Walk
		or component is C_Flight
		or component is C_Jump
		or component is C_Sprint
		or component is C_Attack
		or component is C_Embodied
	):
		_render()


## Переназначили клавишу — строка показывает новую немедленно.
func _on_settings_changed(_settings: RS_Settings) -> void:
	_render()


func _render() -> void:
	var player := E_Player.find()
	if player == null:
		_signature = ""
		_started = -INF
		return

	var flying := player.has_component(C_Flight)
	_move.set_line("", tr("HUD_CTRL_FLIGHT" if flying else "HUD_CTRL_MOVE"))

	var jump := player.get_component(C_Jump) as C_Jump
	_jump.visible = jump != null
	if jump != null:
		_jump.set_line(SettingsManager.action_display_name(jump.action_name), tr("HUD_CTRL_JUMP"))

	var sprint := player.get_component(C_Sprint) as C_Sprint
	_sprint.visible = sprint != null
	if sprint != null:
		_sprint.set_line(SettingsManager.action_display_name(sprint.action_name), tr("HUD_CTRL_SPRINT"))

	var attack := player.get_component(C_Attack) as C_Attack
	_attack.visible = attack != null
	if attack != null:
		_attack.set_line(SettingsManager.action_display_name(attack.action_name), tr("HUD_CTRL_ATTACK"))

	var signature := "%s|%s|%s|%s|%s" % [
		flying, jump != null, sprint != null, attack != null, player.has_component(C_Embodied)
	]
	if signature != _signature:
		_signature = signature
		_started = UI_HudMood.now()


## Видимые строки, по одной на строку — для проверок.
func visible_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for line in _lines():
		lines.append(line.plain_text())
	return lines


## Идёт ли показ (а не догорел ли он).
func is_showing() -> bool:
	return UI_HudMood.now() - _started < HOLD_UNTIL + FADE + STAGGER * 2.0


func _lines() -> Array[UI_ThoughtLine]:
	var lines: Array[UI_ThoughtLine] = []
	for line: UI_ThoughtLine in [_move, _jump, _sprint, _attack]:
		if line.visible:
			lines.append(line)
	return lines


func _process(_delta: float) -> void:
	var elapsed := UI_HudMood.now() - _started
	var lines := _lines()
	var top := -((lines.size() - 1) * LINE_STEP + LINE_HEIGHT)
	for i in lines.size():
		var e := elapsed - i * STAGGER
		var alpha := 0.0
		if e >= 0.0 and e < HOLD_UNTIL + FADE:
			alpha = clampf(e / APPEAR, 0.0, 1.0) * clampf((HOLD_UNTIL + FADE - e) / FADE, 0.0, 1.0)
		var slide := SLIDE * (1.0 - clampf(e / APPEAR, 0.0, 1.0))
		lines[i].modulate.a = alpha
		lines[i].position = Vector2(slide, top + i * LINE_STEP)
