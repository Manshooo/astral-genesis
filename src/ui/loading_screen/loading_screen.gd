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
## Сцены под него нет по той же причине, что у шторки UIManager.fade_to_black:
## прямоугольник и подпись, открывать в редакторе нечего. Вид — вариация темы
## (MenuWhisper), а не своя тема ([[Конвенции проекта]] §3).
class_name UI_LoadingScreen
extends CanvasLayer

## Над HUD (его слои −1 и −3) и под отладочным оверлеем (128): читы нужны и во
## время загрузки.
const LAYER := 120
## Сколько кадров шторка держится после входа: первый кадр нового слоя
## компилирует пайплайны шейдеров и бьёт рывком — пусть он пройдёт под шторкой.
const SETTLE_FRAMES := 2
const FADE_OUT := 0.25
## Период «дыхания» строки, секунды.
const PULSE_PERIOD := 1.6

var _root: Control
var _label: Label
var _time := 0.0


func _init() -> void:
	layer = LAYER
	# Загрузка не должна вставать, если что-то поставит дерево на паузу.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var backdrop := ColorRect.new()
	backdrop.color = UI_MenuStyle.BG_VOID
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)

	_label = Label.new()
	_label.theme_type_variation = &"MenuWhisper"
	_label.text = "LOADING_COMPLEX"
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_root.add_child(_label)


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
