# res://src/ui/hud/thought_line.gd
## Строка «[клавиша] действие» без подложки: подсказка взаимодействия и строки
## управления тела (§2, §4 «HUD — спека»).
##
## Клавиша — отдельные подписи, а не часть строки: строка перевода хранит только
## действие, а клавиша приходит из настроек управления и бывает буквой, словом
## («ЛКМ», «Пробел») — склеенная в одну строку, она не дала бы покрасить скобки
## и клавишу по-своему и заставила бы переводчика сохранять «[%s]».
##
## Читаемость держит не плашка, а «тень мысли» — размытое пятно без формы позади
## строки. Его размер — от строки, поэтому английский на треть длиннее ничего не
## ломает: ширины нигде не фиксированы.
##
## Дети строятся кодом: это механизм раскладки, а не авторский контент — вид
## задают вариации темы, и настраивать в сцене здесь нечего.
class_name UI_ThoughtLine
extends Control

## Кегль управления (16) вместо кегля мысли (19).
@export var small := false
## Насколько пятно тени шире строки с каждой стороны.
@export var shadow_margin := Vector2(46.0, 16.0)
## Строка центрируется по своей точке (подсказка под прицелом) или стоит от неё
## левым краем (управление в углу).
@export var centered := true

var _shadow: TextureRect
var _row: HBoxContainer
var _open: UI_ThoughtLabel
var _key: UI_ThoughtLabel
var _close: UI_ThoughtLabel
var _text: UI_ThoughtLabel


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow = TextureRect.new()
	_shadow.name = "ThoughtShadow"
	_shadow.texture = UI_HudMood.thought_shadow_texture()
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)

	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 1)
	add_child(_row)

	var prefix := "HudControls" if small else "Hud"
	_open = _add_label(prefix + "KeyBracket", "[")
	_key = _add_label(prefix + "Key", "")
	_close = _add_label(prefix + "KeyBracket", "]")
	_text = _add_label("HudControls" if small else "HudThought", "")
	set_line("", "")


func _add_label(variation: StringName, text: String) -> UI_ThoughtLabel:
	var label := UI_ThoughtLabel.new()
	label.theme_type_variation = variation
	label.text = text
	_row.add_child(label)
	return label


## [param key] — отображаемое имя клавиши; пусто — строка без клавиши («Ход»,
## «Нужно тело: …»).
func set_line(key: String, text: String) -> void:
	var has_key := key != ""
	_open.visible = has_key
	_key.visible = has_key
	_close.visible = has_key
	_key.text = key
	# Пробел после «]» — внутри подписи действия: у HBox один отступ на всех, а
	# между скобками и клавишей он должен быть тоньше, чем перед словом.
	_text.text = (" " + text) if has_key else text
	_layout()


## Что видно на экране, одной строкой — для проверок и отладки.
func plain_text() -> String:
	if _key.visible:
		return "[%s]%s" % [_key.text, _text.text]
	return _text.text


## Фаза эха — разводит соседние строки управления.
func set_echo_phase(phase: float) -> void:
	for label: UI_ThoughtLabel in [_open, _key, _close, _text]:
		label.echo_phase = phase


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_layout()


## Каждый кадр, а не по сигналу: размер подписи становится известен после
## шейпинга, а он у Label ленивый. Строка одна и короткая — пересчёт дешёвый.
func _layout() -> void:
	_row.size = _row.get_combined_minimum_size()
	_row.position = Vector2(-_row.size.x / 2.0 if centered else 0.0, 0.0)
	_shadow.position = _row.position - shadow_margin
	_shadow.size = _row.size + shadow_margin * 2.0
