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

@export_group("Graphics")
@export var max_fps: int = 60

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
