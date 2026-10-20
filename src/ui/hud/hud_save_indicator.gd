# res://src/ui/hud/hud_save_indicator.gd
## Отметка сохранения в углу HUD — иконка без подписи (assets/ui/icons/save.svg), α 0.75: появляется на КАЖДУЮ контрольную точку и гаснет сама (вход в забег точкой не считается, RunManager._enter_node).
## Запись идёт между кадрами и ничем себя не выдаёт — отклик, как у кнопки «Сохранить». Слушаем сигнал СЕЙВА, не RunManager: точку ставят из нескольких мест.
class_name UI_HudSaveIndicator
extends TextureRect

## Проявление: в макете штрих прорисовывается, здесь — проявляется за то же время.
const APPEAR_SECONDS := 0.35
## Сколько держать отметку, считая проявление: точки на смене комнаты частые, висящий значок перестали бы видеть.
const VISIBLE_SECONDS := 1.15
## Сколько гаснуть.
const FADE_SECONDS := 0.4
const ALPHA := 0.75

var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()
	WorldSave.progress_saved.connect(_on_progress_saved)


func _on_progress_saved() -> void:
	# Точки идут подряд — показ начинаем заново, а не вторую анимацию поверх.
	if _tween and _tween.is_valid():
		_tween.kill()

	modulate.a = 0.0
	show()

	_tween = create_tween()
	# TWEEN_PAUSE_PROCESS: сохранить можно из паузы, а твин по умолчанию на паузе замирает — значок завис бы.
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(self, "modulate:a", ALPHA, APPEAR_SECONDS)
	_tween.tween_interval(VISIBLE_SECONDS - APPEAR_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
	_tween.tween_callback(hide)
