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
## (render_scale/shadows_enabled/shadow_atlas_size/aa_mode — см.
## RS_GraphicsPreset и settings_menu.gd.GRAPHICS_PRESET_FIELDS). Значения по
## умолчанию здесь равны пресету "medium" — свежая установка не должна
## выглядеть как "собственные" настройки.
@export var graphics_preset_id: StringName = &"medium"
@export_range(0.5, 1.5, 0.05) var render_scale: float = 1.0
@export var shadows_enabled: bool = true
@export var shadow_atlas_size: int = 2048
@export var aa_mode: RS_GraphicsPreset.AAMode = RS_GraphicsPreset.AAMode.FXAA
## Вне пресета: про разрыв кадров на конкретном мониторе, а не про качество
## картинки — пресет её не меняет и правка не считается "отступлением" от него.
@export var vsync_enabled: bool = true

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
