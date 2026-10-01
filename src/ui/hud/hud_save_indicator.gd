# res://src/ui/hud/hud_save_indicator.gd
## Отметка сохранения в углу HUD — иконка, без подписи. Появляется на КАЖДУЮ
## контрольную точку (смена комнаты, автосохранение по времени, смена
## воплощения) и гаснет сама. Вход в забег точкой не считается и сюда не
## приходит — см. RunManager._enter_node.
##
## Зачем вообще: запись проходит между кадрами и ничем себя не выдаёт, поэтому
## игрок не знает ни что точка поставлена, ни где она была. Кнопка «Сохранить» в
## паузе такой отклик уже имеет (иначе выглядит сломанной) — здесь то же правило
## для точек, которые ставит игра сама.
##
## Иконкой, а не текстом: подпись пришлось бы переводить, она шире и читается как
## сообщение, которое требует внимания. Значок — `assets/ui/icons/save.svg`. Без
## подложки (язык «Отголосок») и не в полную силу: α 0.75 — отметка, а не
## событие.
##
## Слушаем сигнал СЕЙВА, а не RunManager: точку ставят из нескольких мест, а
## факт записи один.
class_name UI_HudSaveIndicator
extends TextureRect

## Проявление: в макете штрих прорисовывается, здесь — проявляется за то же время.
const APPEAR_SECONDS := 0.35
## Сколько держать отметку, считая проявление. Заметно, но не назойливо:
## контрольная точка на смене комнаты случается часто, и висящий значок быстро
## стал бы частью интерфейса, которую перестают видеть.
const VISIBLE_SECONDS := 1.15
## Сколько гаснуть после этого.
const FADE_SECONDS := 0.4
const ALPHA := 0.75

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	WorldSave.progress_saved.connect(_on_progress_saved)


func _on_progress_saved() -> void:
	# Точки идут подряд (смена комнаты сразу после захвата тела) — начинаем
	# показ заново, а не заводим вторую анимацию поверх первой.
	if _tween and _tween.is_valid():
		_tween.kill()

	modulate.a = 0.0
	show()

	_tween = create_tween()
	# TWEEN_PAUSE_PROCESS: сохранить можно из ПАУЗЫ (кнопка в меню), а твин по
	# умолчанию идёт вместе с миром — на паузе он замирал, и, сняв паузу, игрок
	# обнаруживал значок, который так и висит с прошлого сохранения.
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", ALPHA, APPEAR_SECONDS)
	_tween.tween_interval(VISIBLE_SECONDS - APPEAR_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(hide)
