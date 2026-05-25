extends Node

# Ссылка на активные настройки (синглтон доступа)
var settings : SettingsData

func _ready():
	load_settings()

func load_settings():
	var path = "user://settings.tres"
	if FileAccess.file_exists(path):
		settings = ResourceLoader.load(path)
	else:
		settings = SettingsData.new()
		save_settings()   # Создаём файл с дефолтными значениями

	# Применяем настройки после загрузки
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(settings.master_volume))
	if settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func save_settings():
	var path = "user://settings.tres"
	ResourceSaver.save(settings, path)

# Удобные методы для чтения/записи
func get_mouse_sensitivity() -> float:
	return settings.mouse_sensitivity

func set_mouse_sensitivity(value: float):
	settings.mouse_sensitivity = value
	save_settings()
