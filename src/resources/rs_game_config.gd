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

@export_group("World generation")
## Библиотека пресетов комнат для процедурной генерации.
## Пусто = все узлы получают placeholder-комнату (поведение до появления
## библиотеки). Назначается в инспекторе на data/game_config.tres.
@export var room_preset_library: RS_RoomPresetLibrary
