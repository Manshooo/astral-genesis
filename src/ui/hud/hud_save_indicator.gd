# res://src/ui/hud/hud_save_indicator.gd
## Отметка «Сохранено» в углу HUD. Появляется на КАЖДУЮ контрольную точку —
## смену комнаты, автосохранение по времени, смену воплощения — и гаснет сама.
##
## Зачем вообще: запись проходит между кадрами и ничем себя не выдаёт, поэтому
## игрок не знает ни что точка поставлена, ни где она была. Кнопка «Сохранить» в
## паузе такой отклик уже имеет (иначе выглядит сломанной) — здесь то же правило
## для точек, которые ставит игра сама.
##
## Слушаем сигнал СЕЙВА, а не RunManager: точку ставят из нескольких мест, а
## факт записи один. Скрипт на подложке, а не на Label — тот же приём, что у
## hud_message.gd: show()/hide() прячут плашку целиком.
class_name UI_HudSaveIndicator
extends PanelContainer

## Сколько держать отметку. Заметно, но не назойливо: контрольная точка на смене
## комнаты случается часто, и висящая надпись быстро стала бы частью интерфейса,
## которую перестают видеть.
const VISIBLE_SECONDS := 1.2

## Сколько гаснуть после этого.
const FADE_SECONDS := 0.4

var _tween: Tween


func _ready() -> void:
	hide()
	WorldSave.progress_saved.connect(_on_progress_saved)


func _on_progress_saved() -> void:
	# Точки идут подряд (смена комнаты сразу после захвата тела) — начинаем
	# показ заново, а не заводим вторую анимацию поверх первой.
	if _tween and _tween.is_valid():
		_tween.kill()

	modulate.a = 1.0
	show()

	_tween = create_tween()
	_tween.tween_interval(VISIBLE_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(hide)
