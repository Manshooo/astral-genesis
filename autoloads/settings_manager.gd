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
	apply_sensitivity(settings.mouse_sensitivity)
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
	apply_sensitivity(value)

func apply_sensitivity(value: float):
	# Пример применения к мыши (если используется InputMap или камера)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # если нужно
	# Для камеры в 3D: обычно умножаем дельту на sensitivity
	# Здесь просто сохраняем, а в скрипте камеры читаем SettingsManager.get_mouse_sensitivity()
