# res://src/autoloads/game_config.gd
## Автозагрузка для конфига разработчика. В отличие от SettingsManager —
## никакого save/load/draft: значения редактируются прямо в data/game_config.tres
## в инспекторе Godot.
extends Node

const DEFAULT_CONFIG := preload("res://data/game_config.tres")

var config: RS_GameConfig = DEFAULT_CONFIG
