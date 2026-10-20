## Экран настроек «Отголосок» (§9 «Меню — спека»): черновик + три вкладки. Контролы собираются обходом поддерева по утиному контракту (setting_key + get/set_setting_value + setting_changed) — перенос настройки на вкладку правка сцены,
## не скрипта. Вкладки — ряд кнопок-мыслей над TabContainer со скрытыми ярлыками (у ярлыка нет эха, штриха, фокуса, §5). Содержимое вкладки в ScrollContainer ради минимального размера (TabContainer запрашивает все вкладки сразу).
## Подсказка строки — в колонке справа (§9). Вкладка по умолчанию всегда первая, откуда бы ни пришли. Вики: [[Конвенции проекта]] §6.
extends UI_MenuScreen

const CALIBRATION_SCENE := preload("res://src/ui/brightness_calibration/brightness_calibration.tscn")

var caller_node: Control = null

@onready var apply_button: Button = %Apply
## Корень обхода, а не список: настройки лежат по вкладкам произвольной глубины.
@onready var settings_list: Control = %Pages
@onready var _pages: TabContainer = %Pages
@onready var _tab_buttons: HBoxContainer = %TabButtons
@onready var _dirty_label: Label = %Dirty
@onready var _hint_title: Label = %HintTitle
@onready var _hint_text: Label = %HintText
@onready var _keybinds: Control = %Keybinds

var _controls: Array = []

## Поля пресета графики: правка любого вручную переводит graphics_preset_id на CUSTOM_PRESET_ID. vsync_enabled не входит — независимая калибровка под монитор (RS_GraphicsPreset).
const GRAPHICS_PRESET_FIELDS := [
	"render_scale", "shadow_quality", "screen_effects", "glow_enabled", "aa_mode",
]
const GRAPHICS_PRESET_KEY := "graphics_preset_id"
const CUSTOM_PRESET_ID := &"custom"
## Настройки окна, которые встроенная в редактор игра применить не может.
const WINDOW_LOCKED_KEYS := ["window_mode", "resolution"]

## Список пресетов — отдельно от _controls: после отката на CUSTOM обновляем его в обход setting_changed (иначе остальные поля перезатёрлись бы покинутым пресетом).
var _preset_control: Control = null

## Черновик — независимая копия; SettingsManager.settings трогается один раз, в _on_apply_pressed().
var _draft: RS_Settings
var _baseline: Dictionary = {}

func _ready() -> void:
	super._ready()
	_collect_controls(settings_list)
	_load_values()
	_connect_tabs()
	_connect_hints(settings_list)
	_lock_window_rows()
	_show_hint("", "")


## Во встроенной игре режим и разрешение не применяются (SettingsManager.is_window_locked) — строки гаснут, подсказка говорит почему; значения в черновике остаются.
func _lock_window_rows() -> void:
	if not SettingsManager.is_window_locked():
		return
	for control in _controls:
		var row := (control as Node).get_parent() as UI_SettingRow
		if row and control.setting_key in WINDOW_LOCKED_KEYS:
			row.set_row_disabled(true)
			row.hint_key = "SETTINGS_HINT_WINDOW_EMBEDDED"


## Кнопка-вкладка N открывает страницу N: порядок один.
func _connect_tabs() -> void:
	var i := 0
	for button in _tab_buttons.get_children():
		(button as BaseButton).pressed.connect(_pages.set_current_tab.bind(i))
		i += 1
	(_tab_buttons.get_child(0) as BaseButton).button_pressed = true
	_pages.current_tab = 0


func _connect_hints(node: Node) -> void:
	for child in node.get_children():
		if child is UI_SettingRow:
			(child as UI_SettingRow).looked_at.connect(_on_row_looked_at)
		_connect_hints(child)


func _on_row_looked_at(row: UI_SettingRow) -> void:
	_show_hint(row.title(), row.hint_key)


func _show_hint(title: String, hint_key: String) -> void:
	_hint_title.text = title
	_hint_text.text = tr(hint_key) if hint_key != "" else ""


## Раскладка — целый блок: подсказку показываем, пока мышь или фокус внутри.
func _process(_delta: float) -> void:
	if not _keybinds.is_visible_in_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	var hovered := _keybinds.get_global_rect().has_point(_keybinds.get_global_mouse_position())
	var focused := focus != null and _keybinds.is_ancestor_of(focus)
	if (hovered or focused) and _hint_title.text != tr("SETTINGS_KEYS"):
		_show_hint(tr("SETTINGS_KEYS"), "SETTINGS_HINT_KEYS")


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
	# copy(), а не duplicate(): тот копирует ССЫЛКУ на keybinds (RS_Settings.copy).
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
		# keybinds — словарь, черновик и baseline всегда РАЗНЫЕ объекты; сверяем содержимое явно.
		return _dicts_equal(a, b)
	return a == b

func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or a[key] != b[key]:
			return false
	return true

## «Применить» недоступна, пока черновик совпадает с применённым; строка рядом объясняет, когда загорится.
func _update_apply_button() -> void:
	var dirty := _has_unsaved_changes()
	apply_button.disabled = not dirty
	_dirty_label.visible = dirty

func _on_any_setting_changed(control: Variant) -> void:
	var key: String = control.setting_key
	_draft.set(key, control.get_setting_value())
	if key == GRAPHICS_PRESET_KEY:
		_apply_preset_to_draft(control.get_setting_value())
	elif key in GRAPHICS_PRESET_FIELDS:
		_sync_preset_with_draft()
	_update_apply_button()

## Выбор пресета раскатывает его значения на поля черновика и контролы (иначе виден только после Apply).
func _apply_preset_to_draft(preset_id: StringName) -> void:
	if preset_id == CUSTOM_PRESET_ID:
		return  # "Собственный" выбран руками — раскатывать нечего
	var preset := SettingsManager.preset_by_id(preset_id)
	if preset == null:
		return
	preset.apply_to(_draft)
	for control in _controls:
		var field_key: String = control.setting_key
		if field_key in GRAPHICS_PRESET_FIELDS:
			control.set_setting_value(_draft.get(field_key))

## Правка графического поля разошлась с пресетом — список переводится на «Собственный»; select() не эмитит setting_changed, повторного заезда нет.
func _sync_preset_with_draft() -> void:
	var preset := SettingsManager.preset_by_id(_draft.graphics_preset_id)
	if preset != null and preset.matches(_draft):
		return
	_draft.graphics_preset_id = CUSTOM_PRESET_ID
	if _preset_control:
		_preset_control.set_setting_value(CUSTOM_PRESET_ID)

func _on_apply_pressed() -> void:
	SettingsManager.settings = _draft
	SettingsManager.save()
	_load_values()  # новый _draft = свежая копия применённых настроек, baseline сбрасывается

func _on_back_pressed() -> void:
	UIManager.close_top()


## Калибровка подбирает яркость черновика: «Применить» — единственная дверь в SettingsManager. Подобранное возвращается в ползунок, и тот сам зажигает «Применить».
func _on_calibration_pressed() -> void:
	var screen := CALIBRATION_SCENE.instantiate() as UI_BrightnessCalibration
	screen.brightness = _draft.brightness
	screen.confirmed.connect(_on_calibration_confirmed)
	UIManager.push_screen(screen)


func _on_calibration_confirmed(brightness: float) -> void:
	_draft.brightness_calibrated = true
	for control in _controls:
		if control.setting_key == "brightness":
			control.set_setting_value(brightness)


func _on_reset_pressed() -> void:
	_draft = SettingsManager.default_settings()
	_apply_draft_to_controls()
	_update_apply_button()  # baseline НЕ трогаем — Reset это тоже "незафиксированное" изменение
