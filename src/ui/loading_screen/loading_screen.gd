# res://src/ui/loading_screen/loading_screen.gd
## Загрузочный экран входа в забег: шторка цвета фона и одна дышащая строка, пока RunManager.enter_complex_async строит комплекс в фоне; ставит и снимает main.gd. Процентов нет намеренно
## (честного «сколько осталось» нет) — движение строки отличает загрузку от зависания. Слой 120 — над HUD, под отладочным оверлеем (128); process_mode «всегда». Вид — MenuWhisper; создавать create(), не .new().
class_name UI_LoadingScreen
extends CanvasLayer

const SCENE_PATH := "res://src/ui/loading_screen/loading_screen.tscn"
## Кадров шторки после входа: первый кадр нового слоя компилирует шейдеры и бьёт рывком — пусть пройдёт под шторкой.
const SETTLE_FRAMES := 2
const FADE_OUT := 0.25
## Период «дыхания» строки, с.
const PULSE_PERIOD := 1.6

@onready var _root: Control = %Root
@onready var _label: Label = %Label

var _time := 0.0


## load(), а не preload(): сцена ссылается на этот скрипт — циклическая зависимость при разборе.
static func create() -> UI_LoadingScreen:
	return (load(SCENE_PATH) as PackedScene).instantiate()


func _process(delta: float) -> void:
	_time += delta
	_label.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(TAU * _time / PULSE_PERIOD))


## Снимает шторку: выжидает SETTLE_FRAMES кадров, гасит и освобождает себя; возвращает управление, когда шторки нет.
func dismiss() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	await tween.finished
	queue_free()
