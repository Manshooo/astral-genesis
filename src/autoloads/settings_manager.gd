# res://src/autoloads/settings_manager.gd
# Autoload — добавь в Project → Project Settings → Autoload
# Name: SettingsManager
# Path: res://src/autoloads/settings_manager.gd
#
# Использование из любого места:
#   SettingsManager.settings.mouse_sensitivity
#   SettingsManager.save()
extends Node

const SETTINGS_PATH := "user://settings.tres"
const DEFAULT_SETTINGS := preload("res://data/settings.tres")

# Текущие активные настройки. Читай отсюда в системах.
var settings: RS_Settings

func _ready() -> void:
	settings = _load()

# Сохранить текущие настройки на диск
func save() -> void:
	var err := ResourceSaver.save(settings, SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: не удалось сохранить настройки, код ошибки %d" % err)

# Сбросить к настройкам по умолчанию
func reset() -> void:
	settings = DEFAULT_SETTINGS.duplicate()

# --- Приватное ---

func _load() -> RS_Settings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var loaded := ResourceLoader.load(SETTINGS_PATH) as RS_Settings
		if loaded:
			return loaded
		push_warning("SettingsManager: файл настроек повреждён, загружаю дефолтные")
	# user://settings.tres не существует — первый запуск
	return DEFAULT_SETTINGS.duplicate()
