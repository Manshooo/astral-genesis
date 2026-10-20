# res://src/ui/settings/window_mode_setting.gd
## Список режимов окна: фиксированные значения SettingsManager.WINDOW_*, как у AAModeSetting; порядок — от «самого игрового» к «самому настольному».
class_name WindowModeSetting
extends OptionSetting


func _ready() -> void:
	clear()
	option_values = [
		SettingsManager.WINDOW_FULLSCREEN,
		SettingsManager.WINDOW_BORDERLESS,
		SettingsManager.WINDOW_WINDOWED,
	]
	add_item("SETTINGS_WINDOW_FULLSCREEN")
	add_item("SETTINGS_WINDOW_BORDERLESS")
	add_item("SETTINGS_WINDOW_WINDOWED")
	super._ready()
