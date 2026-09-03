## Экран настроек: черновик + вкладки. Настройки разложены по вкладкам
## («Графика», «Аудио», «Управление»), и меню про эту раскладку НИЧЕГО не знает —
## контролы собираются рекурсивным обходом поддерева по утиному контракту
## (setting_key + get/set_setting_value + сигнал setting_changed). Поэтому
## перенести настройку на другую вкладку или завести новую — правка сцены, а не
## этого скрипта.
##
## Содержимое вкладки лежит в ScrollContainer не ради прокрутки (её пока нет), а
## ради минимального размера: TabContainer запрашивает его по ВСЕМ вкладкам
## сразу, и самая длинная — «Управление» с восемью строками раскладки — иначе
## растягивала бы окно и на «Аудио» с единственным ползунком.
##
## Вкладка по умолчанию всегда первая и не зависит от того, откуда пришли (из
## главного меню или из паузы): экран один, и один и тот же экран, открывающийся
## по-разному, читался бы как две разные вещи.
extends Control

var caller_node: Control = null

@onready var apply_button: Button = $Panel/MarginContainer/VBox/Buttons/Apply
## Корень обхода, а не список: настройки лежат по вкладкам произвольной глубины.
@onready var settings_list: Control = $Panel/MarginContainer/VBox

var _controls: Array = []

## Поля, из которых складывается пресет графики. Правка любого из них вручную
## переводит graphics_preset_id на CUSTOM_PRESET_ID (см. _on_any_setting_changed) —
## список централизован здесь же, рядом с единственным местом, которое его читает.
## vsync_enabled сюда намеренно не входит: это не про качество картинки, а про
## разрыв кадров на конкретном мониторе — независимая настройка, пресет её не
## трогает (см. RS_GraphicsPreset).
const GRAPHICS_PRESET_FIELDS := [
	"render_scale", "shadows_enabled", "shadow_atlas_size", "aa_mode",
]
const GRAPHICS_PRESET_KEY := "graphics_preset_id"
const CUSTOM_PRESET_ID := &"custom"

## Контрол выпадающего списка пресетов — держим отдельно от _controls, чтобы
## после отката на CUSTOM обновить его отображение напрямую, в обход
## setting_changed (иначе правка одного поля привела бы к повторной подмене
## остальных полей значениями текущего, уже покинутого, пресета).
var _preset_control: Control = null

## Черновик — независимая копия настроек. Все контролы читают/пишут только сюда.
## SettingsManager.settings трогается один-единственный раз — в _on_apply_pressed().
var _draft: RS_Settings
var _baseline: Dictionary = {}

func _ready() -> void:
	_collect_controls(settings_list)
	_load_values()

func _collect_controls(node: Node) -> void:
	for child in node.get_children():
		if child.has_method("get_setting_value") and child.has_method("set_setting_value"):
			_controls.append(child)
			if child.setting_key == GRAPHICS_PRESET_KEY:
				_preset_control = child
			if child.has_signal("setting_changed"):
				child.setting_changed.connect(_on_any_setting_changed)
		else:
			_collect_controls(child)

func _load_values() -> void:
	# copy(), а не duplicate(): duplicate копирует ССЫЛКУ на keybinds, и правки
	# раскладки применялись бы мимо кнопки «Применить» (см. RS_Settings.copy).
	_draft = SettingsManager.settings.copy()
	_apply_draft_to_controls()
	_capture_baseline()

func _apply_draft_to_controls() -> void:
	for control in _controls:
		var key: String = control.setting_key
		if key != "" and key in _draft:
			control.set_setting_value(_draft.get(key))

func _capture_baseline() -> void:
	_baseline.clear()
	for control in _controls:
		_baseline[control.setting_key] = control.get_setting_value()
	_update_apply_button()

func _has_unsaved_changes() -> bool:
	for control in _controls:
		var current = control.get_setting_value()
		var base = _baseline.get(control.setting_key)
		if not _values_equal(current, base):
			return true
	return false

func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	if a is Dictionary and b is Dictionary:
		# Раскладка клавиш (keybinds) — словарь, а черновик и baseline это всегда
		# РАЗНЫЕ объекты; сверяем содержимое явно, не полагаясь на семантику ==.
		return _dicts_equal(a, b)
	return a == b

func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or a[key] != b[key]:
			return false
	return true

## disabled+flat по умолчанию ("невидимая" кнопка), становится обычной активной
## кнопкой, как только черновик отличается от последнего применённого состояния.
func _update_apply_button() -> void:
	var dirty := _has_unsaved_changes()
	apply_button.disabled = not dirty
	apply_button.flat = not dirty

func _on_any_setting_changed(control: Variant) -> void:
	var key: String = control.setting_key
	_draft.set(key, control.get_setting_value())
	if key == GRAPHICS_PRESET_KEY:
		_apply_preset_to_draft(control.get_setting_value())
	elif key in GRAPHICS_PRESET_FIELDS:
		_sync_preset_with_draft()
	_update_apply_button()

## Выбор пресета в списке раскатывает его значения на все поля черновика и
## обновляет соответствующие контролы — иначе выбор "Высокий" был бы виден
## только после Apply, а до тех пор слайдеры показывали бы старые цифры.
func _apply_preset_to_draft(preset_id: StringName) -> void:
	if preset_id == CUSTOM_PRESET_ID:
		return  # "Собственный" выбран руками — раскатывать нечего
	var preset := SettingsManager.preset_by_id(preset_id)
	if preset == null:
		return
	_draft.render_scale = preset.render_scale
	_draft.shadows_enabled = preset.shadows_enabled
	_draft.shadow_atlas_size = preset.shadow_atlas_size
	_draft.aa_mode = preset.aa_mode
	for control in _controls:
		var field_key: String = control.setting_key
		if field_key in GRAPHICS_PRESET_FIELDS:
			control.set_setting_value(_draft.get(field_key))

## Правка отдельного графического поля разошлась с применённым пресетом —
## список переводится на "Собственный". select() контрола не эмитит
## setting_changed (в отличие от Range/CheckButton), так что это безопасно от
## повторного заезда в _apply_preset_to_draft.
func _sync_preset_with_draft() -> void:
	var preset := SettingsManager.preset_by_id(_draft.graphics_preset_id)
	if preset != null and _draft_matches_preset(preset):
		return
	_draft.graphics_preset_id = CUSTOM_PRESET_ID
	if _preset_control:
		_preset_control.set_setting_value(CUSTOM_PRESET_ID)

func _draft_matches_preset(preset: RS_GraphicsPreset) -> bool:
	return (
		is_equal_approx(_draft.render_scale, preset.render_scale)
		and _draft.shadows_enabled == preset.shadows_enabled
		and _draft.shadow_atlas_size == preset.shadow_atlas_size
		and _draft.aa_mode == preset.aa_mode
	)

func _on_apply_pressed() -> void:
	SettingsManager.settings = _draft
	SettingsManager.save()
	_load_values()  # новый _draft = свежая копия применённых настроек, baseline сбрасывается

func _on_back_pressed() -> void:
	UIManager.close_top()
	

func _on_reset_pressed() -> void:
	_draft = SettingsManager.default_settings()
	_apply_draft_to_controls()
	_update_apply_button()  # baseline НЕ трогаем — Reset это тоже "незафиксированное" изменение
