# res://src/resources/rs_settings.gd
# Чистые данные (кроме copy()): только то, что настраивает САМ ИГРОК — мышь, экран, клавиши. Характеристики персонажа
# задаёт надетое тело (C_Walk/C_Jump), призраку — C_Flight.
class_name RS_Settings
extends Resource

@export_group("Mouse")
@export var mouse_sensitivity: float = 0.0015  ## Умножается на 1000

@export_group("Camera")
## Поле зрения по горизонтали, градусов (камеру ставит E_Player); границы держат ползунок и камера — сейв мог быть со шкалой 60–120.
@export_range(90.0, 110.0, 1.0) var fov: float = 103.0

const FOV_MIN := 90.0
const FOV_MAX := 110.0

@export_group("Interaction")
@export var interact_range: float = 3.0        ## Дальность луча взаимодействия

@export_group("Audio")
## Общая громкость: ЛИНЕЙНЫЙ множитель 0..1, не децибелы — linear_to_db сделал бы середину ползунка почти тишиной.
@export_range(0.0, 1.0) var master_volume: float = 1.0

@export_group("Graphics")
@export var max_fps: int = 60
## Применённый пресет или &"custom", если игрок поменял поле пресета (GRAPHICS_PRESET_FIELDS). Умолчания равны "medium".
@export var graphics_preset_id: StringName = &"medium"
@export_range(0.5, 1.5, 0.05) var render_scale: float = 1.0
## Ступень теней: id из RS_GraphicsPresetLibrary.shadow_levels или SHADOWS_OFF.
@export var shadow_quality: StringName = &"medium"
## Ступень экранных эффектов (effects_levels).
@export var screen_effects: StringName = &"medium"
## Свечение: отдельный флажок — ореол вокруг ламп кому-то просто мешает.
@export var glow_enabled: bool = true
@export var aa_mode: RS_GraphicsPreset.AAMode = RS_GraphicsPreset.AAMode.FXAA
## Вне пресета: про разрыв кадров на мониторе, не про качество.
@export var vsync_enabled: bool = true
## Яркость — сила подъёма теней (LevelEnvironment), 1 — авторская картинка; числом, не множителем света. Вне пресета: калибровка
## под монитор. Потолок 3 — запас, освещённого лампой подъём не касается.
@export_range(0.5, 3.0, 0.05) var brightness: float = 1.0
## Предлагалась ли калибровка яркости: отметка (показ раз на первом запуске, «Назад» тоже считается); «Сброс» снимает её вместе с яркостью.
@export var brightness_calibrated: bool = false

@export_group("Display")
## Режим окна: &"windowed", &"borderless" (WINDOW_MODE_FULLSCREEN) или &"fullscreen" (эксклюзивный). Вне пресета; по умолчанию оконный.
@export var window_mode: StringName = &"windowed"
## Разрешение: в окне — размер окна, во весь экран — разрешение 3D. ZERO — «авто».
@export var resolution: Vector2i = Vector2i.ZERO
## Масштаб интерфейса: 0 — «авто» по окну, иначе множитель; больше помещающегося не применяется.
@export var ui_scale: float = 0.0

@export_group("Controls")
## Переназначенные клавиши: действие → код ("key:70", "mouse:1"); кодек — SettingsManager. ТОЛЬКО отличия от project.godot
## (пустой = дефолт). Строка, а не InputEvent: события сравниваются по ссылке.
@export var keybinds: Dictionary[StringName, String] = {}


## Независимая копия: duplicate() копирует ССЫЛКУ на keybinds, и черновик меню правил бы применённые настройки.
func copy() -> RS_Settings:
	var clone := duplicate() as RS_Settings
	clone.keybinds = keybinds.duplicate()
	return clone


## Перевод сейва старше ступеней теней (shadows_enabled, shadow_atlas_size): загрузчик кладёт поля сюда; в файле только отличные от
## умолчания, поэтому «флажок не пришёл» = «тени были включены», «атлас не пришёл» = «2048». Флажок идёт раньше атласа.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"shadows_enabled":
		if not value:
			shadow_quality = RS_GraphicsPreset.SHADOWS_OFF
		return true
	if property == &"shadow_atlas_size":
		if shadow_quality != RS_GraphicsPreset.SHADOWS_OFF:
			var size := int(value)
			shadow_quality = &"low" if size <= 1024 else &"medium" if size <= 2048 else &"high" if size <= 4096 else &"ultra"
		return true
	return false
