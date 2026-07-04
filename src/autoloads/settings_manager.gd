# res://src/autoloads/settings_manager.gd
extends Node

const SETTINGS_PATH := "user://settings.tres"
const DEFAULT_SETTINGS := preload("res://data/settings.tres")

var settings: RS_Settings

func _ready() -> void:
	settings = _load()

func save() -> void:
	var err := ResourceSaver.save(settings, SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: не удалось сохранить настройки, код ошибки %d" % err)

func reset() -> void:
	settings = DEFAULT_SETTINGS.duplicate()

## Даёт независимую копию дефолтов — для черновиков в UI, не трогает SettingsManager.settings.
func default_settings() -> RS_Settings:
	return DEFAULT_SETTINGS.duplicate()

func _load() -> RS_Settings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var loaded := ResourceLoader.load(SETTINGS_PATH) as RS_Settings
		if loaded:
			return loaded
		push_warning("SettingsManager: файл настроек повреждён, загружаю дефолтные")
	return DEFAULT_SETTINGS.duplicate()
