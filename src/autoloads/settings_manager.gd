# res://src/autoloads/settings_manager.gd
extends Node

const SETTINGS_PATH := "user://settings.tres"
## Не preload: preload резолвится на компиляции и в debug/export-сборке падает на
## кастомном ресурсе («Cannot get class ''», godotengine/godot#100100). Грузим в
## рантайме через load() в _init — поэтому var, а не const.
const DEFAULT_SETTINGS_PATH := "res://data/settings.tres"
var DEFAULT_SETTINGS: RS_Settings


func _init() -> void:
	DEFAULT_SETTINGS = load(DEFAULT_SETTINGS_PATH)

## Эмитится каждый раз, когда settings меняются (загрузка, Apply, Reset) —
## подписывайтесь, если системе/UI нужно среагировать на смену настроек.
signal settings_changed(settings: RS_Settings)

var settings: RS_Settings:
	set(value):
		settings = value
		_apply_runtime_effects()

func _ready() -> void:
	settings = _load()  # проходит через сеттер -> сразу применяет эффекты

func save() -> void:
	var err := ResourceSaver.save(settings, SETTINGS_PATH)
	if err != OK:
		push_error("SettingsManager: не удалось сохранить настройки, код ошибки %d" % err)

func reset() -> void:
	settings = DEFAULT_SETTINGS.duplicate()  # тоже через сеттер

func default_settings() -> RS_Settings:
	return DEFAULT_SETTINGS.duplicate()

func _load() -> RS_Settings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var loaded := ResourceLoader.load(SETTINGS_PATH) as RS_Settings
		if loaded:
			return loaded
		push_warning("SettingsManager: файл настроек повреждён, загружаю дефолтные")
	return DEFAULT_SETTINGS.duplicate()

## Побочные эффекты, которые должны применяться немедленно при смене настроек,
## а не только на старте игры.
func _apply_runtime_effects() -> void:
	if settings == null:
		return
	Engine.max_fps = settings.max_fps
	settings_changed.emit(settings)
	
