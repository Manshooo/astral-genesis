# resources/settings_data.gd
extends Resource
class_name SettingsData

signal settings_changed(key, value)

@export var mouse_sensitivity : float = 0.001 :
	set(v):
		mouse_sensitivity = v
		settings_changed.emit("mouse_sensitivity", v)

@export var master_volume : float = 0.75
@export var fullscreen : bool = true
