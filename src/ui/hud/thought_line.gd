# res://src/ui/hud/thought_line.gd
## Строка «[клавиша] действие» без подложки (§2, §4, §10 «HUD — спека»): подсказка взаимодействия, управление тела, подсказка мини-карты. Клавиша — отдельные подписи (приходит из настроек).
## Читаемость — «тень мысли», пятно позади, размером от строки. Устройство — в thought_line.tscn («Конвенции проекта» §7); стиль скрипт выставляет по [member style]; создавать instantiate(), не .new().
class_name UI_ThoughtLine
extends Control

## Вариации темы: мысль (19), управление (16) или подпись мини-карты (14).
enum Style { THOUGHT, CONTROLS, MAP }

const _VARIATIONS := {
	Style.THOUGHT: ["HudKeyBracket", "HudKey", "HudThought"],
	Style.CONTROLS: ["HudControlsKeyBracket", "HudControlsKey", "HudControls"],
	Style.MAP: ["HudMapKeyBracket", "HudMapKey", "HudMapLabel"],
}

@export var style := Style.THOUGHT
## Насколько пятно тени шире строки с каждой стороны.
@export var shadow_margin := Vector2(46.0, 16.0)
## Центрируется по точке (под прицелом) или стоит левым краем (управление в углу).
@export var centered := true
## Фаза эха — разводит соседние строки управления.
@export var echo_phase := 0.0

@onready var _shadow: TextureRect = %ThoughtShadow
@onready var _row: HBoxContainer = %Row
@onready var _open: UI_ThoughtLabel = %Open
@onready var _key: UI_ThoughtLabel = %Key
@onready var _close: UI_ThoughtLabel = %Close
@onready var _text: UI_ThoughtLabel = %Text


func _ready() -> void:
	# Подпись мини-карты лежит на её общем пятне — своё рисовало бы пятно в пятне.
	_shadow.visible = style != Style.MAP
	var variations: Array = _VARIATIONS[style]
	for label: UI_ThoughtLabel in [_open, _close]:
		label.theme_type_variation = variations[0]
	_key.theme_type_variation = variations[1]
	_text.theme_type_variation = variations[2]
	for label: UI_ThoughtLabel in [_open, _key, _close, _text]:
		label.echo_phase = echo_phase
	set_line("", "")


## [param key] — имя клавиши; пусто — строка без клавиши («Ход», «Нужно тело: …»).
func set_line(key: String, text: String) -> void:
	var has_key := key != ""
	_open.visible = has_key
	_key.visible = has_key
	_close.visible = has_key
	_key.text = key
	# Пробел после «]» — внутри подписи действия: между скобками и клавишей отступ тоньше.
	_text.text = (" " + text) if has_key else text
	_layout()


## Что видно на экране одной строкой — для проверок.
func plain_text() -> String:
	if _key.visible:
		return "[%s]%s" % [_key.text, _text.text]
	return _text.text


## Ширина строки на экране.
func width() -> float:
	_layout()
	return _row.size.x


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_layout()


## Каждый кадр, а не по сигналу: размер подписи известен после ленивого шейпинга Label; пересчёт дешёвый.
func _layout() -> void:
	_row.size = _row.get_combined_minimum_size()
	_row.position = Vector2(-_row.size.x / 2.0 if centered else 0.0, 0.0)
	_shadow.position = _row.position - shadow_margin
	_shadow.size = _row.size + shadow_margin * 2.0
