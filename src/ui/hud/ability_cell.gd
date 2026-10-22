# res://src/ui/hud/ability_cell.gd
## Ячейка слота или банка способностей — единственная рамка в HUD: без контура пустой и закрытый слот не прочитать ([[HUD — спека]] §7б).
## Цвет говорит, откуда способность: янтарь — тело, сирень — поглощена. Подписи — в ability_cell.tscn, рамка, иконка и откат рисуются.
class_name UI_AbilityCell
extends Control

enum State { EMPTY, LOCKED, BODY, SOUL }

## Затемнение отката снизу вверх — цвет «тени мысли».
const COOLDOWN_SHADE := Color(0.02, 0.02, 0.04, 0.62)
const FILL := Color(0.02, 0.02, 0.04, 0.4)
const GRAFT_ALPHA := 0.28
## Точка спящей поглощённой под способностью тела.
const SLEEP_DOT_RADIUS := 2.0
const DASH := 3.0
const GLOW_STEPS := 5
const LOCK_ICON := preload("res://assets/ui/icons/lock.svg")

## Ячейка банка: меньше, без номера.
@export var compact := false

var state := State.EMPTY
var icon: Texture2D
var sleeping := false
## Новая способность на экране полного банка: полная сирень и свечение (макет 16).
var glowing := false:
	set(value):
		glowing = value
		queue_redraw()
## Наведённая ячейка банка там же: светлеет к over.
var hovered := false:
	set(value):
		hovered = value
		queue_redraw()
## Доля оставшегося отката, 0 — готова.
var cooldown_share := 0.0
## Доля прирастания после переноса из банка, 0…1; 0 — не прирастает (заливка soul снизу вверх, макет 14).
var graft_share := 0.0

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
	graft_share = 0.0
	var graft_time := GameConfig.config.ability_graft_time
	if ability and ability.graft_left > 0.0 and graft_time > 0.0:
		graft_share = clampf(1.0 - ability.graft_left / graft_time, 0.0, 1.0)
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
			draw_rect(box.grow(-0.5), UI_HudMood.OVER if hovered else _alpha(UI_HudMood.BODY, 0.6), false, 1.0)
		State.SOUL:
			if hovered:
				draw_rect(box, _alpha(UI_HudMood.SOUL, 0.14))
				_draw_glow(box, UI_HudMood.OVER, 0.25)
				draw_rect(box.grow(-0.5), UI_HudMood.OVER, false, 1.0)
			elif glowing:
				draw_rect(box, FILL)
				_draw_glow(box, UI_HudMood.SOUL, 0.3)
				draw_rect(box.grow(-0.5), UI_HudMood.SOUL, false, 1.0)
			else:
				draw_rect(box, FILL)
				draw_rect(box.grow(-0.5), _alpha(UI_HudMood.SOUL, 0.5), false, 1.0)
		State.EMPTY:
			var edge := UI_HudMood.OVER if hovered else _alpha(UI_HudMood.TEXT, 0.2)
			draw_rect(box.grow(-0.5), edge, false, 1.0)
		State.LOCKED:
			_draw_dashed_box(box.grow(-0.5), _alpha(UI_HudMood.TEXT, 0.2))
	if state == State.LOCKED:
		_draw_icon(LOCK_ICON, 10.0 if compact else 14.0, _alpha(UI_HudMood.TEXT, 0.4))
	elif icon:
		var tint := UI_HudMood.BODY if state == State.BODY else UI_HudMood.SOUL
		# Значок — половина ячейки: 22 у слота, 16 у банка, как в макете.
		_draw_icon(icon, size.x * 0.5, tint)
	if graft_share > 0.0:
		var grown := box.size.y * graft_share
		draw_rect(Rect2(0.0, box.size.y - grown, box.size.x, grown), _alpha(UI_HudMood.SOUL, GRAFT_ALPHA))
	if cooldown_share > 0.0:
		var shade := box.size.y * cooldown_share
		draw_rect(Rect2(0.0, box.size.y - shade, box.size.x, shade), COOLDOWN_SHADE)
	if sleeping:
		draw_circle(box.size - Vector2(5.0, 5.0), SLEEP_DOT_RADIUS, UI_HudMood.SOUL)


func _draw_icon(texture: Texture2D, side: float, tint: Color) -> void:
	var rect := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	draw_texture_rect(texture, rect, false, tint)


## Свечение — рамки наружу с убывающей альфой: StyleBox с тенью собирать в коде нельзя, а _draw — рисование.
func _draw_glow(box: Rect2, color: Color, alpha: float) -> void:
	for i in range(1, GLOW_STEPS + 1):
		var fade := 1.0 - float(i) / float(GLOW_STEPS + 1)
		draw_rect(box.grow(float(i) * 2.0), _alpha(color, alpha * fade * fade), false, 2.0)


## Закрытый слот — пунктиром: сплошная рамка читалась бы как «пусто, но доступно».
func _draw_dashed_box(box: Rect2, color: Color) -> void:
	var corners := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in corners.size():
		draw_dashed_line(corners[i], corners[(i + 1) % corners.size()], color, 1.0, DASH)


static func _alpha(color: Color, alpha: float) -> Color:
	return Color(color, alpha)
