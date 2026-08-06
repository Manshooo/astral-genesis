## res://src/resources/rs_game_config.gd
## Конфиг для разработчика: значения баланса/физики, которые НЕ являются
## пользовательскими настройками и не должны попадать в user:// или в
## draft/apply/reset флоу SettingsManager. Редактируется напрямую в
## инспекторе на data/game_config.tres.
class_name RS_GameConfig
extends Resource

@export_group("FPS")
@export var pitch_limit: float = 1.4           ## ~80° в радианах

@export_group("Physics")
@export var gravity: float = 9.8

@export_group("БФЖ (развоплощён)")
## Множитель к скорости движения из настроек: призрак не бежит, а плывёт.
@export var ghost_speed_scale: float = 0.8
## Разгон до желаемой скорости, м/с². Меньше — тяжелее раскачивается.
@export var ghost_acceleration: float = 9.0
## Затухание, когда клавиши отпущены, м/с². Меньше — дольше несёт по инерции.
@export var ghost_damping: float = 3.5

@export_group("Распад")
## Во сколько раз быстрее утекает запас СВЕРХ собственного максимума души —
## тот излишек, что принесён из тела при добровольном выходе. Смысл в том, что
## накопить огромный буфер и ходить с ним нельзя: излишек надо тратить.
@export var lifespan_overflow_leak: float = 3.0
## Какая доля собственного максимума остаётся душе, если тело ПОГИБЛО (HP в ноль
## или его время вышло). Сгорело — значит сгорело: остаток тела не переносится,
## и запас души не «сохраняется», а падает до этой доли.
@export_range(0.0, 1.0) var lifespan_death_fraction: float = 0.1

@export_group("World generation")
## Библиотека пресетов комнат для процедурной генерации.
## Пусто = все узлы получают placeholder-комнату (поведение до появления
## библиотеки). Назначается в инспекторе на data/game_config.tres.
@export var room_preset_library: RS_RoomPresetLibrary
