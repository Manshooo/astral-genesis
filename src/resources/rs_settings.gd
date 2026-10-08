# res://src/resources/rs_settings.gd
# Чистые данные — никакой логики (кроме copy(): это копирование самих данных).
#
# Здесь только то, что настраивает САМ ИГРОК: мышь, экран, клавиши. Характеристик
# персонажа тут нет и быть не должно — скорость и прыжок задаёт надетое тело
# (C_Walk/C_Jump), а призраку RS_GameConfig. Раньше move_speed/jump_velocity
# лежали здесь, тела множились на них, и обосновывалось это «игрок настроил их
# сам» — хотя в меню настроек их не было ни дня.
class_name RS_Settings
extends Resource

@export_group("Mouse")
@export var mouse_sensitivity: float = 0.0015  ## Умножается на 1000

@export_group("Camera")
@export var fov: float = 103.0

@export_group("Interaction")
@export var interact_range: float = 3.0        ## Дальность луча взаимодействия

@export_group("Audio")
## Общая громкость: ЛИНЕЙНЫЙ множитель 0..1, не децибелы. byProd масштабирует им
## всё поверх собственной громкости событий, поэтому пересчёт ползунка через
## linear_to_db — то, чего потребовала бы шина Godot, — здесь не нужен и был бы
## ошибкой: он сделал бы середину ползунка почти тишиной.
@export_range(0.0, 1.0) var master_volume: float = 1.0

@export_group("Graphics")
@export var max_fps: int = 60
## Применённый пресет ("low"/"medium"/"high", каталог — data/graphics_presets.tres)
## или &"custom", если игрок вручную поменял хоть одно из полей пресета ниже
## (render_scale/shadow_quality/aa_mode — см.
## RS_GraphicsPreset и settings_menu.gd.GRAPHICS_PRESET_FIELDS). Значения по
## умолчанию здесь равны пресету "medium" — свежая установка не должна
## выглядеть как "собственные" настройки.
@export var graphics_preset_id: StringName = &"medium"
@export_range(0.5, 1.5, 0.05) var render_scale: float = 1.0
## Ступень теней: id из RS_GraphicsPresetLibrary.shadow_levels или
## RS_GraphicsPreset.SHADOWS_OFF.
@export var shadow_quality: StringName = &"medium"
@export var aa_mode: RS_GraphicsPreset.AAMode = RS_GraphicsPreset.AAMode.FXAA
## Вне пресета: про разрыв кадров на конкретном мониторе, а не про качество
## картинки — пресет её не меняет и правка не считается "отступлением" от него.
@export var vsync_enabled: bool = true

@export_group("Display")
## Режим окна: &"windowed", &"borderless" (во весь экран без рамки — Godot
## WINDOW_MODE_FULLSCREEN) или &"fullscreen" (эксклюзивный). Вне пресета, как
## vsync: это про монитор и привычки игрока, а не про качество картинки. По
## умолчанию оконный — запуск сцены из редактора не должен разворачиваться на
## весь экран.
@export var window_mode: StringName = &"windowed"
## Разрешение: в окне — размер окна, во весь экран — разрешение, в котором
## рисуется 3D (Godot не меняет разрешение монитора). ZERO — «авто»: в окне
## базовый размер проекта, во весь экран — разрешение экрана.
@export var resolution: Vector2i = Vector2i.ZERO
## Масштаб интерфейса: 0 — «авто», интерфейс растягивается по окну от базовых
## 1497×720; иначе фиксированный множитель (1.0 — 100 %). Больше, чем
## помещается в окно, не применяется: раскладка свёрстана под базовое окно.
@export var ui_scale: float = 0.0

@export_group("Controls")
## Переназначенные клавиши: имя действия → код события ("key:70", "mouse:1"),
## кодек — SettingsManager.event_to_code/code_to_event.[br]
## Здесь лежат ТОЛЬКО отличия от project.godot: пустой словарь = полностью
## дефолтное управление, поэтому «Сброс» просто чистит его.[br]
## Строка, а не сам InputEvent: ресурсы-события сравниваются по ссылке, и
## черновик настроек всегда считался бы изменённым.
@export var keybinds: Dictionary[StringName, String] = {}


## Независимая копия настроек. Обычный duplicate() копирует ССЫЛКУ на keybinds —
## черновик в меню настроек и применённые настройки оказались бы одним словарём,
## и правки применялись бы в обход кнопки «Применить».
func copy() -> RS_Settings:
	var clone := duplicate() as RS_Settings
	clone.keybinds = keybinds.duplicate()
	return clone


## Перевод сейва старше ступеней теней — второе исключение из «никакой логики»:
## переводить его больше негде, загрузчик ресурса кладёт поля прямо сюда.
## Раньше тени были флажком и размером атласа (shadows_enabled,
## shadow_atlas_size); полей больше нет, и загрузчик отдаёт их в _set. Без
## перевода игрок, выключивший тени, после обновления получил бы их снова.
## В файл пишутся только отличные от умолчания поля, поэтому «флажок не пришёл»
## значит «тени были включены», а «атлас не пришёл» — «был 2048», то есть
## нынешнее умолчание. Флажок в файле идёт раньше атласа.
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
