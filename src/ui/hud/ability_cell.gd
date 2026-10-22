# res://src/ui/hud/ability_cell.gd
## Ячейка слота или банка способностей — единственная рамка в HUD: без контура пустой и закрытый слот не прочитать ([[HUD — спека]] §7б).
## Цвет говорит, откуда способность: янтарь — тело, сирень — поглощена. Подписи — в ability_cell.tscn, рамка, иконка и откат рисуются.
class_name UI_AbilityCell
extends Control

enum State { EMPTY, LOCKED, BODY, SOUL }

## Затемнение отката снизу вверх — цвет «тени мысли».
const COOLDOWN_SHADE := Color(0.02, 0.02, 0.04, 0.62)
const FILL := Color(0.02, 0.02, 0.04, 0.4)
## Точка спящей поглощённой под способностью тела.
const SLEEP_DOT_RADIUS := 2.0
const DASH := 3.0
const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")

## Ячейка банка: меньше, без номера.
@export var compact := false

var state := State.EMPTY
var icon: Texture2D
var sleeping := false
## Доля оставшегося отката, 0 — готова.
var cooldown_share := 0.0

@onready var _number: Label = %Number
@onready var _cooldown: Label = %Cooldown


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number.visible = not compact


## [param number] — номер клавиши; 0 — без номера (банк).
func show_ability(
	next_state: State, ability: C_Ability, number: int = 0, is_sleeping: bool = false
) -> void:
	state = next_state
	icon = ability.icon if ability else null
	sleeping = is_sleeping
	cooldown_share = 0.0
	var seconds := 0.0
	if ability and ability.cooldown > 0.0 and next_state != State.LOCKED:
		seconds = ability.cooldown_left
		cooldown_share = clampf(seconds / ability.cooldown, 0.0, 1.0)
	_cooldown.text = str(ceili(seconds)) if seconds > 0.0 else ""
	_number.text = str(number) if number > 0 else ""
	_number.modulate.a = 0.4 if next_state in [State.LOCKED, State.EMPTY] else 1.0
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	match state:
		State.BODY:
			draw_rect(box, FILL)
			draw_rect(box.grow(-0.5), _alpha(UI_HudMood.BODY, 0.6), false, 1.0)
		State.SOUL:
			draw_rect(box, FILL)
			draw_rect(box.grow(-0.5), _alpha(UI_HudMood.SOUL, 0.5), false, 1.0)
		State.EMPTY:
			draw_rect(box.grow(-0.5), _alpha(UI_HudMood.TEXT, 0.2), false, 1.0)
		State.LOCKED:
			_draw_dashed_box(box.grow(-0.5), _alpha(UI_HudMood.TEXT, 0.2))
	if state == State.LOCKED:
		_draw_icon(LOCK_ICON, 10.0 if compact else 14.0, _alpha(UI_HudMood.TEXT, 0.4))
	elif icon:
		var tint := UI_HudMood.BODY if state == State.BODY else UI_HudMood.SOUL
		_draw_icon(icon, 16.0 if compact else 22.0, tint)
	if cooldown_share > 0.0:
		var shade := box.size.y * cooldown_share
		draw_rect(Rect2(0.0, box.size.y - shade, box.size.x, shade), COOLDOWN_SHADE)
	if sleeping:
		draw_circle(box.size - Vector2(5.0, 5.0), SLEEP_DOT_RADIUS, UI_HudMood.SOUL)


func _draw_icon(texture: Texture2D, side: float, tint: Color) -> void:
	var rect := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	draw_texture_rect(texture, rect, false, tint)


## Закрытый слот — пунктиром: сплошная рамка читалась бы как «пусто, но доступно».
func _draw_dashed_box(box: Rect2, color: Color) -> void:
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in corners.size():
		draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], color, 1.0, DASH)


static func _alpha(color: Color, alpha: float) -> Color:
	return Color(color, alpha)
