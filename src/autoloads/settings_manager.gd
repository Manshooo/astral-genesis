# Настройки игрока: загрузка и сохранение, применение графики, окна, масштаба и раскладки клавиш.
# Вики: [[Конвенции проекта]] (устройство перепривязки).
extends Node

const SETTINGS_PATH := "user://settings.tres"
## Не preload: падает в debug/export на кастомном ресурсе (godotengine/godot#100100) — load() в _init.
const DEFAULT_SETTINGS_PATH := "res://data/settings.tres"
var DEFAULT_SETTINGS: RS_Settings

## Тот же обход preload-бага.
const GRAPHICS_PRESETS_PATH := "res://data/graphics_presets.tres"
var GRAPHICS_PRESETS: RS_GraphicsPresetLibrary

## Переназначаемые действия в порядке показа и ключи перевода подписей. pause_game не входит:
## Esc — инвариант UI (закрывает любой экран, в том числе захват клавиши).
const REBINDABLE_ACTIONS := {
	&"move_forward": "ACTION_MOVE_FORWARD",
	&"move_backward": "ACTION_MOVE_BACKWARD",
	&"move_left": "ACTION_MOVE_LEFT",
	&"move_right": "ACTION_MOVE_RIGHT",
	&"jump": "ACTION_JUMP",
	&"sprint": "ACTION_SPRINT",
	&"interact": "ACTION_INTERACT",
	&"snatch_body": "ACTION_SNATCH_BODY",
	&"attack": "ACTION_ATTACK",
	&"ability_1": "ACTION_ABILITY_1",
	&"ability_2": "ACTION_ABILITY_2",
	&"ability_3": "ACTION_ABILITY_3",
	&"ability_4": "ACTION_ABILITY_4",
	&"leave_body": "ACTION_LEAVE_BODY",
	&"map": "ACTION_MAP",
	&"map_mini": "ACTION_MAP_MINI",
	&"stats": "ACTION_STATS",
}

## Имена кнопок мыши — ключи перевода; прочие — KEY_MOUSE_N.
const MOUSE_BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "KEY_MOUSE_LEFT",
	MOUSE_BUTTON_RIGHT: "KEY_MOUSE_RIGHT",
	MOUSE_BUTTON_MIDDLE: "KEY_MOUSE_MIDDLE",
	MOUSE_BUTTON_WHEEL_UP: "KEY_WHEEL_UP",
	MOUSE_BUTTON_WHEEL_DOWN: "KEY_WHEEL_DOWN",
	MOUSE_BUTTON_XBUTTON1: "KEY_MOUSE_4",
	MOUSE_BUTTON_XBUTTON2: "KEY_MOUSE_5",
}

## Эмитится при любой смене settings (загрузка, Apply, Reset).
signal settings_changed(settings: RS_Settings)

var settings: RS_Settings:
	set(value):
		settings = value
		_apply_runtime_effects()

## Дефолтная раскладка project.godot: action -> код. Снимается один раз в _init, до переопределений.
var _default_codes: Dictionary = {}


func _init() -> void:
	DEFAULT_SETTINGS = load(DEFAULT_SETTINGS_PATH)
	GRAPHICS_PRESETS = load(GRAPHICS_PRESETS_PATH)
	# Автолоады создаются после InputMap из project.godot — в нём ещё дефолтная раскладка.
	_snapshot_default_codes()

func _ready() -> void:
	settings = _load()  # проходит через сеттер -> сразу применяет эффекты
	# Окно меняет не только «Применить»: его тянут руками и разворачивают.
	get_window().size_changed.connect(_apply_ui_scale)

func save() -> void:
	UserResourceFile.write(settings, SETTINGS_PATH, "SettingsManager")

func reset() -> void:
	settings = DEFAULT_SETTINGS.copy()  # тоже через сеттер

func default_settings() -> RS_Settings:
	return DEFAULT_SETTINGS.copy()

## Пресет по id или null — для &"custom" и неизвестного id.
func preset_by_id(id: StringName) -> RS_GraphicsPreset:
	return GRAPHICS_PRESETS.by_id(id) if GRAPHICS_PRESETS else null

## Ступень теней из настроек или null (тени выключены). Читают лампы (LevelLight).
func shadow_level() -> RS_ShadowLevel:
	if settings == null or GRAPHICS_PRESETS == null:
		return null
	return GRAPHICS_PRESETS.shadow_level(settings.shadow_quality)


## Ступень экранных эффектов или null; читает LevelEnvironment.
func effects_level() -> RS_ScreenEffectsLevel:
	if settings == null or GRAPHICS_PRESETS == null:
		return null
	return GRAPHICS_PRESETS.effects_level(settings.screen_effects)


## Сейв с именованным пресетом приводится к пресету, каким он стал; «Собственные» не трогаются.
func _load() -> RS_Settings:
	var loaded := UserResourceFile.read(SETTINGS_PATH, RS_Settings, "SettingsManager") as RS_Settings
	if loaded == null:
		return DEFAULT_SETTINGS.copy()
	var preset := preset_by_id(loaded.graphics_preset_id)
	if preset:
		preset.apply_to(loaded)
	return loaded

## Эффекты, применяемые сразу при смене настроек, а не только на старте.
func _apply_runtime_effects() -> void:
	if settings == null:
		return
	Engine.max_fps = settings.max_fps
	_apply_keybinds()
	_apply_display_settings()
	_apply_graphics_settings()
	settings_changed.emit(settings)


# Графика


## «Тени выкл» — занулённые атласы, а не свойство света: автолоад не знает про сцены.
## directional-атлас сжимаем до минимума (0 не валиден). Дальность теней ставят сами лампы.
func _apply_graphics_settings() -> void:
	var level := shadow_level()
	var atlas := level.atlas_size if level else 0
	if level:
		RenderingServer.positional_soft_shadow_filter_set_quality(level.soft_filter)
		RenderingServer.directional_soft_shadow_filter_set_quality(level.soft_filter)
	var viewport := get_viewport()
	if viewport:
		# Во весь экран «разрешение» — мельче рисуемое 3D, поверх «Масштаба разрешения».
		var scale_3d := settings.render_scale * render_resolution_factor()
		viewport.scaling_3d_scale = scale_3d
		# Ниже 100 % — FSR1 (дешёвый, возвращает резкость); выше — FSR не работает. Решает итоговый масштаб.
		viewport.scaling_3d_mode = (
			Viewport.SCALING_3D_MODE_FSR if scale_3d < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
		)
		viewport.positional_shadow_atlas_size = atlas
		if level:
			# Все четыре четверти одинаково — см. RS_ShadowLevel.cells_per_quadrant.
			viewport.positional_shadow_atlas_quad_0 = level.cells_per_quadrant
			viewport.positional_shadow_atlas_quad_1 = level.cells_per_quadrant
			viewport.positional_shadow_atlas_quad_2 = level.cells_per_quadrant
			viewport.positional_shadow_atlas_quad_3 = level.cells_per_quadrant
		match settings.aa_mode:
			RS_GraphicsPreset.AAMode.OFF:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
				viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			RS_GraphicsPreset.AAMode.FXAA:
				viewport.msaa_3d = Viewport.MSAA_DISABLED
				viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			RS_GraphicsPreset.AAMode.MSAA_2X:
				viewport.msaa_3d = Viewport.MSAA_2X
				viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			RS_GraphicsPreset.AAMode.MSAA_4X:
				viewport.msaa_3d = Viewport.MSAA_4X
				viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(maxi(atlas, 1), false)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if settings.vsync_enabled else DisplayServer.VSYNC_DISABLED
	)


# Экран: режим окна, разрешение, масштаб интерфейса

const WINDOW_WINDOWED := &"windowed"
const WINDOW_BORDERLESS := &"borderless"
const WINDOW_FULLSCREEN := &"fullscreen"

## Предлагаемые разрешения (16:9 и 16:10); показываются влезающие в экран.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1600, 900),
	Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1440),
	Vector2i(2560, 1600), Vector2i(3200, 1800), Vector2i(3840, 2160),
]
## Фиксированные масштабы интерфейса; целые — самые чёткие.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0]

## Режим и разрешение, последними применённые к окну ([] — ещё ни разу).
var _applied_window: Array = []


## Базовое окно проекта — единица размеров интерфейса.
func base_size() -> Vector2i:
	return Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)


## Разрешения для списка: влезающие в экран плюс сам экран.
func resolution_options() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var options: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			options.append(size)
	if screen.x > 0 and not options.has(screen):
		options.append(screen)
	return options


## Масштабы интерфейса, при которых базовое окно ещё влезает в экран.
func ui_scale_options() -> Array[float]:
	var screen := Vector2(DisplayServer.screen_get_size())
	var fit := minf(screen.x / base_size().x, screen.y / base_size().y)
	var options: Array[float] = []
	for scale in UI_SCALES:
		if scale <= fit + 0.001 or scale == 1.0:
			options.append(scale)
	return options


## Игра встроена во вкладку редактора: окно только оконное, режим и размер задаёт редактор —
## поэтому режим и разрешение не применяются, а меню их гасит.
func is_window_locked() -> bool:
	return Engine.is_embedded_in_editor()


## Режим и размер окна. Окно трогается, только когда режим или разрешение поменялись:
## иначе правка громкости сворачивала бы развёрнутое руками окно.
func _apply_display_settings() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return
	var wanted_window := [settings.window_mode, settings.resolution]
	if not is_window_locked() and wanted_window != _applied_window:
		_applied_window = wanted_window
		_apply_window_mode(window)
	_apply_ui_scale()


func _apply_window_mode(window: Window) -> void:
	match settings.window_mode:
		WINDOW_FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		WINDOW_BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		_:
			if window.mode != Window.MODE_WINDOWED:
				window.mode = Window.MODE_WINDOWED
			var wanted := settings.resolution if settings.resolution != Vector2i.ZERO else base_size()
			# Окно не больше рабочей области: иначе заголовок уезжает за край.
			var usable := DisplayServer.screen_get_usable_rect().size
			if usable.x > 0:
				wanted = wanted.min(usable)
			if window.size != wanted:
				window.size = wanted
				window.move_to_center()


## Во сколько раз 3D рисуется мельче экрана из-за разрешения при полном экране; в окне и
## во встроенной игре — 1; сверху зажато 1.
func render_resolution_factor() -> float:
	if settings == null or settings.window_mode == WINDOW_WINDOWED or settings.resolution == Vector2i.ZERO:
		return 1.0
	if is_window_locked():
		return 1.0
	var screen := DisplayServer.screen_get_size()
	if screen.y <= 0:
		return 1.0
	return minf(1.0, float(settings.resolution.y) / screen.y)


## Масштаб интерфейса: фиксированный k — тот же canvas_items с базой окно / k, без чёрных полей
## целого режима Godot. Пересчитывается при каждом изменении размера окна.
func _apply_ui_scale() -> void:
	var window := get_window()
	if window == null or settings == null or window.size.x <= 0 or window.size.y <= 0:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	window.content_scale_size = ui_content_size(window.size, base_size(), settings.ui_scale)


## Базовый размер холста для окна и масштаба. «Авто» и окно меньше базового — сама база; слишком
## большой масштаб зажимается. Не static: до автолоада без class_name дозваться можно только через инстанс.
func ui_content_size(window_size: Vector2i, base: Vector2i, ui_scale: float) -> Vector2i:
	var size := Vector2(window_size)
	var fit := minf(size.x / base.x, size.y / base.y)
	if ui_scale <= 0.0 or fit < 1.0:
		return base
	var k := minf(ui_scale, fit)
	return Vector2i(ceili(size.x / k), ceili(size.y / k))


# Управление: раскладка клавиш


## Раскатывает settings.keybinds поверх дефолта. В настройках только ОТЛИЧИЯ, поэтому база
## каждый раз перезагружается: «Сброс» не оставит старые переопределения.
func _apply_keybinds() -> void:
	InputMap.load_from_project_settings()
	for action: StringName in settings.keybinds:
		if not InputMap.has_action(action):
			continue  # действие исчезло из project.godot — сейв старше проекта
		var event := code_to_event(settings.keybinds[action])
		if event == null:
			continue
		InputMap.action_erase_events(action)
		InputMap.action_add_event(action, event)


## Код действия по дефолтной раскладке ("" — действия или привязки нет).
func default_code_for(action: StringName) -> String:
	return _default_codes.get(action, "")


## Имя ТЕКУЩЕЙ привязки для подсказок HUD; читает InputMap, а не сейв. "" — привязки нет.
func action_display_name(action: StringName) -> String:
	var code := _first_code_of(action)
	return code_display_name(code) if code != "" else ""


## Имя привязки для UI: "F", "ЛКМ", "—" для пустого/битого кода.
func code_display_name(code: String) -> String:
	var event := code_to_event(code)
	if event is InputEventKey:
		# Имена клавиш по-английски — это надпись на клавише; переводим только пробел.
		if event.physical_keycode == KEY_SPACE:
			return tr("KEY_SPACE")
		return OS.get_keycode_string(event.physical_keycode)
	if event is InputEventMouseButton:
		var button: int = event.button_index
		if MOUSE_BUTTON_NAMES.has(button):
			return tr(MOUSE_BUTTON_NAMES[button])
		return tr("KEY_MOUSE_N") % button
	return "—"


## Кодирует событие в строку для сейва: "key:70", "mouse:1"; "" — непривязываемый тип.
## Не static: у скрипта нет class_name, а статический вызов на инстансе автолоада — ошибка парсера.
func event_to_code(event: InputEvent) -> String:
	if event is InputEventKey:
		# physical_keycode: чтобы WASD не разъезжались на не-QWERTY раскладках.
		var key := event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return "key:%d" % code
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


## Обратная к event_to_code; null, если строка не разбирается.
func code_to_event(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return null
	match parts[0]:
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(parts[1]) as Key
			return key
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(parts[1]) as MouseButton
			return mouse
	return null


func _snapshot_default_codes() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		_default_codes[action] = _first_code_of(action)


## Первая привязка действия, которую умеем кодировать (клавиша или кнопка мыши).
func _first_code_of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var code := event_to_code(event)
		if code != "":
			return code
	return ""
