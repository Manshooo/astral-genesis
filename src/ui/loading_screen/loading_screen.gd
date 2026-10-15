# res://src/ui/loading_screen/loading_screen.gd
## Загрузочный экран входа в забег: непрозрачная шторка цвета фона вне забега и
## одна дышащая строка, пока RunManager.enter_complex_async строит комплекс в
## фоновом потоке. Ставит и снимает его игровая сцена (main.gd).
##
## Прогресса в процентах нет намеренно: генерация — один вызов в другом потоке,
## и честного «сколько осталось» у неё нет. Живое движение строки — то, что
## отличает загрузку от зависания; раньше на этом месте кадр просто замирал на
## секунду-две.
##
## Устройство — в loading_screen.tscn: слой 120 — над HUD (его слои −1 и −3) и
## под отладочным оверлеем (128), читы нужны и во время загрузки; process_mode
## «всегда» — загрузка не должна вставать, если что-то поставит дерево на
## паузу. Вид — вариация темы (MenuWhisper), а не своя тема ([[Конвенции
## проекта]] §3). Создавать — create(): .new() дал бы слой без шторки.
class_name UI_LoadingScreen
extends CanvasLayer

const SCENE_PATH := "res://src/ui/loading_screen/loading_screen.tscn"
## Сколько кадров шторка держится после входа: первый кадр нового слоя
## компилирует пайплайны шейдеров и бьёт рывком — пусть он пройдёт под шторкой.
const SETTLE_FRAMES := 2
const FADE_OUT := 0.25
## Период «дыхания» строки, секунды.
const PULSE_PERIOD := 1.6

@onready var _root: Control = %Root
@onready var _label: Label = %Label

var _time := 0.0


## load(), а не preload(): сцена ссылается на этот же скрипт, и preload
## собственной сцены из него — циклическая зависимость при разборе.
static func create() -> UI_LoadingScreen:
	return (load(SCENE_PATH) as PackedScene).instantiate()


func _process(delta: float) -> void:
	_time += delta
	_label.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(TAU * _time / PULSE_PERIOD))


## Снимает шторку: выжидает SETTLE_FRAMES кадров, гасит и освобождает себя.
## Возвращает управление, когда шторки уже нет.
func dismiss() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	await tween.finished
	queue_free()
