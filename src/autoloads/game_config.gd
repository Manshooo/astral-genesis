# res://src/autoloads/game_config.gd
## Автозагрузка для конфига разработчика. В отличие от SettingsManager —
## никакого save/load/draft: значения редактируются прямо в data/game_config.tres
## в инспекторе Godot.
extends Node

## Путь, а не preload: preload резолвится на этапе компиляции и в debug/export-
## сборке падает на вложенном кастомном ресурсе («Cannot get class ''», см.
## godotengine/godot#100100). Грузим ресурс в рантайме через load() в _init.
const DEFAULT_CONFIG_PATH := "res://data/game_config.tres"

var config: RS_GameConfig


func _init() -> void:
	config = load(DEFAULT_CONFIG_PATH)
