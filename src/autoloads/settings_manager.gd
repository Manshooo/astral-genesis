# res://src/autoloads/settings_manager.gd
extends Node

const SETTINGS_PATH := "user://settings.tres"
## Не preload: preload резолвится на компиляции и в debug/export-сборке падает на
## кастомном ресурсе («Cannot get class ''», godotengine/godot#100100). Грузим в
## рантайме через load() в _init — поэтому var, а не const.
const DEFAULT_SETTINGS_PATH := "res://data/settings.tres"
var DEFAULT_SETTINGS: RS_Settings

## Тот же обход preload-бага (см. DEFAULT_SETTINGS выше) — каталог тоже
## кастомный ресурс.
const GRAPHICS_PRESETS_PATH := "res://data/graphics_presets.tres"
var GRAPHICS_PRESETS: RS_GraphicsPresetLibrary

## Действия, доступные для переназначения, в порядке показа в настройках, и
## ключи перевода их подписей.
## pause_game сюда НЕ входит намеренно: Esc — инвариант UI (им закрывается любой
## экран, включая сам экран настроек, где идёт захват клавиши).
const REBINDABLE_ACTIONS := {
	&"move_forward": "ACTION_MOVE_FORWARD",
	&"move_backward": "ACTION_MOVE_BACKWARD",
	&"move_left": "ACTION_MOVE_LEFT",
	&"move_right": "ACTION_MOVE_RIGHT",
	&"jump": "ACTION_JUMP",
	&"sprint": "ACTION_SPRINT",
	&"interact": "ACTION_INTERACT",
	&"snatch_body": "ACTION_SNATCH_BODY",
	&"leave_body": "ACTION_LEAVE_BODY",
	&"map": "ACTION_MAP",
	&"map_mini": "ACTION_MAP_MINI",
}

## Имена кнопок мыши — ключи перевода: OS.get_keycode_string умеет только
## клавиши. Прочие кнопки — KEY_MOUSE_N с номером.
const MOUSE_BUTTON_NAMES := {
	MOUSE_BUTTON_LEFT: "KEY_MOUSE_LEFT",
	MOUSE_BUTTON_RIGHT: "KEY_MOUSE_RIGHT",
	MOUSE_BUTTON_MIDDLE: "KEY_MOUSE_MIDDLE",
	MOUSE_BUTTON_WHEEL_UP: "KEY_WHEEL_UP",
	MOUSE_BUTTON_WHEEL_DOWN: "KEY_WHEEL_DOWN",
	MOUSE_BUTTON_XBUTTON1: "KEY_MOUSE_4",
	MOUSE_BUTTON_XBUTTON2: "KEY_MOUSE_5",
}

## Эмитится каждый раз, когда settings меняются (загрузка, Apply, Reset) —
## подписывайтесь, если системе/UI нужно среагировать на смену настроек.
signal settings_changed(settings: RS_Settings)

var settings: RS_Settings:
	set(value):
		settings = value
		_apply_runtime_effects()

## Дефолтная раскладка из project.godot: action → код события. Снимается ОДИН раз
## в _init, до того как настройки успели что-то переопределить в InputMap.
var _default_codes: Dictionary = {}


func _init() -> void:
	DEFAULT_SETTINGS = load(DEFAULT_SETTINGS_PATH)
	GRAPHICS_PRESETS = load(GRAPHICS_PRESETS_PATH)
	# Автолоады создаются уже после инициализации InputMap из project.godot,
	# поэтому здесь в нём ещё нетронутая дефолтная раскладка.
	_snapshot_default_codes()

func _ready() -> void:
	settings = _load()  # проходит через сеттер -> сразу применяет эффекты
	# Масштаб интерфейса зависит от размера окна, а окно меняет не только
	# «Применить»: его тянут руками и разворачивают на весь экран.
	get_window().size_changed.connect(_apply_ui_scale)

func save() -> void:
	UserResourceFile.write(settings, SETTINGS_PATH, "SettingsManager")

func reset() -> void:
	settings = DEFAULT_SETTINGS.copy()  # тоже через сеттер

func default_settings() -> RS_Settings:
	return DEFAULT_SETTINGS.copy()

## Пресет по id ("low"/"medium"/"high") или null — для &"custom" и любого
## неизвестного id (например сейв старше проекта, из каталога пропал пресет).
func preset_by_id(id: StringName) -> RS_GraphicsPreset:
	return GRAPHICS_PRESETS.by_id(id) if GRAPHICS_PRESETS else null

## Ступень теней из настроек или null — тени выключены (или id пропал из
## каталога, что для игрока то же самое). Её дальность читают лампы уровня
## (LevelLight): сами узлы сцены этот автолоад не трогает, см.
## _apply_graphics_settings.
func shadow_level() -> RS_ShadowLevel:
	if settings == null or GRAPHICS_PRESETS == null:
		return null
	return GRAPHICS_PRESETS.shadow_level(settings.shadow_quality)


## Ступень экранных эффектов из настроек или null — эффектов нет. Читает её
## окружение сцены (LevelEnvironment), по той же причине, что лампы — тени.
func effects_level() -> RS_ScreenEffectsLevel:
	if settings == null or GRAPHICS_PRESETS == null:
		return null
	return GRAPHICS_PRESETS.effects_level(settings.screen_effects)


## Сейв с именованным пресетом приводится к пресету, каким он стал: игрок выбрал
## «Высокий», а не набор чисел, и раз «Высокий» поменялся (или в нём появилось
## новое поле, как ступень теней вместо флажка и атласа), он получает новый.
## «Собственные» настройки не трогаются — их числа и есть выбор игрока.
func _load() -> RS_Settings:
	var loaded := UserResourceFile.read(SETTINGS_PATH, RS_Settings, "SettingsManager") as RS_Settings
	if loaded == null:
		return DEFAULT_SETTINGS.copy()
	var preset := preset_by_id(loaded.graphics_preset_id)
	if preset:
		preset.apply_to(loaded)
	return loaded

## Побочные эффекты, которые должны применяться немедленно при смене настроек,
## а не только на старте игры.
func _apply_runtime_effects() -> void:
	if settings == null:
		return
	Engine.max_fps = settings.max_fps
	_apply_keybinds()
	_apply_display_settings()
	_apply_graphics_settings()
	settings_changed.emit(settings)


# ---------------------------------------------------------------------------
# Графика
# ---------------------------------------------------------------------------


## "Тени выкл" — это занулённые атласы, а не свойство конкретного света: автолоад
## не должен знать про DirectionalLight3D из world.tscn — сцена может смениться
## (меню, будущие уровни), а настройка обязана продолжать работать без правки
## каждой новой сцены. directional-атлас не зануляем совсем (0 там не валиден),
## а сжимаем до минимума — эффект тот же, тени неотличимы от выключенных.
## Дальность теней — свойство каждой лампы, и её ставят сами лампы (LevelLight)
## по settings_changed, а не этот автолоад обходом дерева.
func _apply_graphics_settings() -> void:
	var level := shadow_level()
	var atlas := level.atlas_size if level else 0
	if level:
		RenderingServer.positional_soft_shadow_filter_set_quality(level.soft_filter)
		RenderingServer.directional_soft_shadow_filter_set_quality(level.soft_filter)
	var viewport := get_viewport()
	if viewport:
		# Во весь экран «разрешение» — это мельче экрана рисуемое 3D, поверх
		# «Масштаба разрешения» (см. render_resolution_factor).
		var scale_3d := settings.render_scale * render_resolution_factor()
		viewport.scaling_3d_scale = scale_3d
		# Ниже 100 % — FSR1: он дешёвый и вытягивает резкость, которую растяжение
		# билинейным фильтром съедает. FSR2 на встроенной графике сам стоит кадров,
		# а выше 100 % (суперсэмплинг) FSR не работает вовсе. Решает итоговый
		# масштаб, а не ползунок: разрешение ниже экрана — то же уменьшение.
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


# ---------------------------------------------------------------------------
# Экран: режим окна, разрешение, масштаб интерфейса
# ---------------------------------------------------------------------------

const WINDOW_WINDOWED := &"windowed"
const WINDOW_BORDERLESS := &"borderless"
const WINDOW_FULLSCREEN := &"fullscreen"

## Разрешения, которые предлагает список: 16:9 и 16:10 — то, что реально
## стоит у игроков. Показываются только влезающие в экран (resolution_options).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1440, 900), Vector2i(1600, 900),
	Vector2i(1680, 1050), Vector2i(1920, 1080), Vector2i(1920, 1200), Vector2i(2560, 1440),
	Vector2i(2560, 1600), Vector2i(3200, 1800), Vector2i(3840, 2160),
]
## Фиксированные масштабы интерфейса. Целые — самые чёткие: линия в пиксель
## остаётся линией в пиксель.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0]


## Базовое окно проекта, под которое свёрстан весь интерфейс (1497×720).
func base_size() -> Vector2i:
	return Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)


## Разрешения для списка в настройках: влезающие в экран, плюс сам экран, если
## его нет среди стандартных.
func resolution_options() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var options: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			options.append(size)
	if screen.x > 0 and not options.has(screen):
		options.append(screen)
	return options


## Масштабы интерфейса для списка: только те, при которых базовое окно ещё
## влезает в экран, — больший интерфейс вылез бы за край.
func ui_scale_options() -> Array[float]:
	var screen := Vector2(DisplayServer.screen_get_size())
	var fit := minf(screen.x / base_size().x, screen.y / base_size().y)
	var options: Array[float] = []
	for scale in UI_SCALES:
		if scale <= fit + 0.001 or scale == 1.0:
			options.append(scale)
	return options


## Режим и размер окна. Godot не меняет разрешение монитора, поэтому во весь
## экран «разрешение» — это то, в чём рисуется 3D (см. render_resolution_factor),
## а размер окна — экран целиком.
func _apply_display_settings() -> void:
	var window := get_window()
	if window == null or DisplayServer.get_name() == "headless":
		return
	match settings.window_mode:
		WINDOW_FULLSCREEN:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		WINDOW_BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		_:
			if window.mode != Window.MODE_WINDOWED:
				window.mode = Window.MODE_WINDOWED
			var wanted := settings.resolution if settings.resolution != Vector2i.ZERO else base_size()
			# Окно не больше рабочей области: иначе заголовок уезжает за край
			# экрана, и окно не передвинуть.
			var usable := DisplayServer.screen_get_usable_rect().size
			if usable.x > 0:
				wanted = wanted.min(usable)
			if window.size != wanted:
				window.size = wanted
				window.move_to_center()
	_apply_ui_scale()


## Во сколько раз 3D рисуется мельче экрана из-за выбранного разрешения: во весь
## экран 1920×1080 на мониторе 2560×1440 — 0.75. В окне разрешение и есть
## размер окна, множитель — 1. Сверху — 1: рисовать 3D крупнее экрана этот
## пункт не обещает, для этого есть «Масштаб разрешения».
func render_resolution_factor() -> float:
	if settings == null or settings.window_mode == WINDOW_WINDOWED or settings.resolution == Vector2i.ZERO:
		return 1.0
	var screen := DisplayServer.screen_get_size()
	if screen.y <= 0:
		return 1.0
	return minf(1.0, float(settings.resolution.y) / screen.y)


## Масштаб интерфейса. «Авто» — canvas_items растягивает базовое окно по окну
## дробно (project.godot). Фиксированный множитель k сделан тем же режимом:
## базовым размером назначается окно / k, и растяжение выходит ровно k — без
## чёрных полей, которые даёт встроенный целый режим Godot (при базе 1497 px его
## множитель на 1080p и 1440p — 1, и игра стоит посередине в рамке).
## Пересчитывается на каждое изменение размера окна.
func _apply_ui_scale() -> void:
	var window := get_window()
	if window == null or settings == null or window.size.x <= 0 or window.size.y <= 0:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	window.content_scale_size = ui_content_size(window.size, base_size(), settings.ui_scale)


## Базовый размер холста для окна [param window_size] при масштабе
## [param ui_scale]: canvas_items растянет его по окну, и множитель выйдет ровно
## тот, что задан. «Авто» (0) и окно меньше базового — сама база: фиксированный
## масштаб в маленьком окне оставил бы раскладке меньше места, чем она
## свёрстана. Масштаб больше, чем влезает, зажимается до влезающего. Не static
## по той же причине, что event_to_code: до автолоада без class_name снаружи
## дозваться можно только через инстанс.
func ui_content_size(window_size: Vector2i, base: Vector2i, ui_scale: float) -> Vector2i:
	var size := Vector2(window_size)
	var fit := minf(size.x / base.x, size.y / base.y)
	if ui_scale <= 0.0 or fit < 1.0:
		return base
	var k := minf(ui_scale, fit)
	return Vector2i(ceili(size.x / k), ceili(size.y / k))


# ---------------------------------------------------------------------------
# Управление: раскладка клавиш
# ---------------------------------------------------------------------------


## Раскатывает settings.keybinds поверх дефолтной раскладки. База каждый раз
## перезагружается из project.godot: в настройках лежат только ОТЛИЧИЯ, поэтому
## «Сброс» (пустой словарь) обязан вернуть управление к дефолту, а не оставить
## прошлые переопределения висеть в InputMap.
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


## Код действия по дефолтной раскладке project.godot ("" — действия нет или у
## него нет ни клавиши, ни кнопки мыши).
func default_code_for(action: StringName) -> String:
	return _default_codes.get(action, "")


## Читаемое имя ТЕКУЩЕЙ привязки действия — для подсказок в HUD ("F", "ЛКМ").
## Читает InputMap, а не сейв, поэтому остаётся верным сразу после
## переназначения. "" — у действия нет ни клавиши, ни кнопки мыши (тогда
## подсказке нечего показывать и префикс лучше не рисовать вовсе).
func action_display_name(action: StringName) -> String:
	var code := _first_code_of(action)
	return code_display_name(code) if code != "" else ""


## Отображаемое имя привязки для UI: "F", "ЛКМ", "—" для пустого/битого кода.
func code_display_name(code: String) -> String:
	var event := code_to_event(code)
	if event is InputEventKey:
		# Клавиатурные имена движок отдаёт по-английски, и для букв и Shift это
		# и есть надпись на клавише. Пробел — единственная частая клавиша, чьё имя
		# игрок читает словом, поэтому переводим только его.
		if event.physical_keycode == KEY_SPACE:
			return tr("KEY_SPACE")
		return OS.get_keycode_string(event.physical_keycode)
	if event is InputEventMouseButton:
		var button: int = event.button_index
		if MOUSE_BUTTON_NAMES.has(button):
			return tr(MOUSE_BUTTON_NAMES[button])
		return tr("KEY_MOUSE_N") % button
	return "—"


## Кодирует событие ввода в короткую строку для сейва: "key:70", "mouse:1".
## "" — событие непривязываемого типа (движение мыши, джойстик и т.п.).
##
## Не static, хотя от состояния не зависит: class_name у скрипта нет (его имя
## занято автолоадом), поэтому единственный способ дозваться до кодека — через
## инстанс автолоада, а статический вызов на инстансе парсер считает ошибкой.
func event_to_code(event: InputEvent) -> String:
	if event is InputEventKey:
		# physical_keycode: привязка к ФИЗИЧЕСКОЙ клавише, чтобы WASD не разъезжались
		# на не-QWERTY раскладках (так же заданы действия в project.godot).
		var key := event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return "key:%d" % code
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	return ""


## Обратная операция к event_to_code. null, если строка не разбирается.
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


## Первая привязка действия, которую мы умеем кодировать (клавиша или кнопка
## мыши). Действия в project.godot имеют по одному событию, но перебор надёжнее.
func _first_code_of(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event in InputMap.action_get_events(action):
		var code := event_to_code(event)
		if code != "":
			return code
	return ""
