# res://src/ui/hud/effect_row.gd
## Строка эффекта слева ([[HUD — спека]] §7в): значок цветом источника и имя; у временного эффекта — остаток в секундах и линия по доле остатка.
## Устройство — effect_row.tscn; создавать instantiate(), не .new().
class_name UI_EffectRow
extends HBoxContainer

@onready var _icon: TextureRect = %Icon
@onready var _name: Label = %Name
@onready var _line: Control = %Line
@onready var _timer: Label = %Timer

var _tint := UI_HudMood.SOUL
var _share := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line.draw.connect(_draw_line)


## [param duration] 0 — постоянный эффект: без остатка и линии.
func show_effect(icon: Texture2D, tint: Color, name_key: StringName, left: float, duration: float) -> void:
	_tint = tint
	_icon.texture = icon
	_icon.modulate = tint
	_name.text = tr(name_key)
	var timed := duration > 0.0
	_timer.visible = timed
	_line.visible = timed
	if timed:
		_timer.text = tr("HUD_EFFECT_SECONDS") % ceili(left)
		_share = clampf(left / duration, 0.0, 1.0)
		_line.queue_redraw()


## Что видно строкой — для проверок.
func plain_text() -> String:
	return _name.text + (" " + _timer.text if _timer.visible else "")


func _draw_line() -> void:
	var track := UI_HudMood.TRACK
	_line.draw_rect(Rect2(Vector2.ZERO, _line.size), track)
	_line.draw_rect(Rect2(Vector2.ZERO, Vector2(_line.size.x * _share, _line.size.y)), _tint)
