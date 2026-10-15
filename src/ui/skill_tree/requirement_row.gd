# res://src/ui/skill_tree/requirement_row.gd
## Строка требования в карточке навыка (§9 «Меню — спека»): отметка и подпись.
## Выполненное — сиреневый кружок, нет — пунктирный, и подпись приглушена:
## смысл несёт отметка, а не только цвет.
##
## Устройство — в requirement_row.tscn; строк столько, сколько требований у
## навыка, поэтому карточка создаёт их instantiate() из сцены. Отметка рисуется
## (_draw) — рисование правилу сцены не подчиняется.
class_name UI_RequirementRow
extends HBoxContainer

@onready var _mark: Control = %Mark
@onready var _label: Label = %Label

var _met := false


func _ready() -> void:
	_mark.draw.connect(_draw_mark)


## [param text] уже переведён карточкой: имена навыков и веток вклеены в него,
## автоперевод подписи до них не достал бы.
func setup(text: String, met: bool) -> void:
	_met = met
	_label.text = text
	_label.modulate.a = 1.0 if met else 0.5
	_mark.queue_redraw()


func _draw_mark() -> void:
	var c := _mark.size / 2.0
	if _met:
		_mark.draw_circle(c, 4.0, UI_HudMood.SOUL)
	else:
		var a := 0.0
		while a < TAU:
			_mark.draw_arc(c, 4.0, a, a + 0.25, 3, Color(UI_MenuStyle.TEXT, 0.5), 1.0, true)
			a += 0.75
