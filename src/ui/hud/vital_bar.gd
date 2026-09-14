# res://src/ui/hud/vital_bar.gd
## Полоса витального показателя: форма из темы, вся палитра — из одного цвета.
##
## Зачем скрипт вместо вариантов темы: StyleBox — это Resource, а тема хранит
## ресурсы целиком. Вариант либо задаёт свой стиль полностью, либо берёт
## родительский полностью — «переопределить только bg_color» система тем не
## умеет, и три варианта ради трёх цветов означали бы три копии геометрии,
## расходящиеся при первой же правке.
##
## Поэтому граница ответственности такая:
##   - тема (тип ProgressBar) — ФОРМА: скругления, толщина рамки, отступ
##     заливки внутрь рамки (content_margin у background);
##   - этот скрипт — ЦВЕТ: заливка, фон и рамка выводятся из fill_color, чтобы
##     полоса всегда была одного тона и три цвета не подбирались вручную.
## Цвета из темы при этом не читаются вообще — красить бар через тему
## бесполезно, правь fill_color на ноде.
@tool
class_name UI_VitalBar
extends ProgressBar

## Насколько фон (незаполненная часть) темнее заливки. Не чёрный и не
## прозрачный: тот же тон, уведённый в тень, — полоса читается как один объект.
const BACKGROUND_DARKEN := 0.78
## Рамка держится между ними: заметно темнее заливки, но светлее фона —
## иначе на светлой заливке она пропадает, а на фоне сливается с ним.
const BORDER_DARKEN := 0.42

## Цвет заливки. Фон и рамка считаются от него.
@export var fill_color: Color = Color.WHITE:
	set(value):
		fill_color = value
		_apply_colors()

# add/remove_theme_stylebox_override сам шлёт NOTIFICATION_THEME_CHANGED —
# без флага получилась бы бесконечная рекурсия.
var _applying: bool = false


func _ready() -> void:
	_apply_colors()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_THEME_CHANGED:
			if not _applying:
				_apply_colors()
		# theme_override_styles/* — обычные свойства ноды, и редактор пишет их
		# в .tscn при сохранении. Без этой пары сцена копила бы SubResource'ы,
		# слепленные с темы в момент сохранения, и они бы её же и перекрывали:
		# правишь тему — ничего не меняется, потому что победил слепок в сцене.
		# Поэтому на время записи снимаем свои override'ы и возвращаем после.
		NOTIFICATION_EDITOR_PRE_SAVE:
			_clear_overrides()
		NOTIFICATION_EDITOR_POST_SAVE:
			_apply_colors()


func _apply_colors() -> void:
	if not is_inside_tree():
		return
	_applying = true

	var fill := _theme_flat(&"fill")
	if fill != null:
		fill.bg_color = fill_color
		add_theme_stylebox_override(&"fill", fill)

	var background := _theme_flat(&"background")
	if background != null:
		background.bg_color = fill_color.darkened(BACKGROUND_DARKEN)
		background.border_color = fill_color.darkened(BORDER_DARKEN)
		add_theme_stylebox_override(&"background", background)

	_applying = false


func _clear_overrides() -> void:
	_applying = true
	for item in [&"fill", &"background"]:
		if has_theme_stylebox_override(item):
			remove_theme_stylebox_override(item)
	_applying = false


## Копия стиля из ТЕМЫ, а не из собственного override: иначе на втором проходе
## прочитали бы свою же копию и правки формы в теме перестали бы доезжать.
func _theme_flat(item: StringName) -> StyleBoxFlat:
	if has_theme_stylebox_override(item):
		remove_theme_stylebox_override(item)
	var base := get_theme_stylebox(item)
	if base is StyleBoxFlat:
		return (base as StyleBoxFlat).duplicate() as StyleBoxFlat
	return null
