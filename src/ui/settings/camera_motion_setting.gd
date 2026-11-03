# res://src/ui/settings/camera_motion_setting.gd
## Список ступеней покачивания камеры: фиксированные значения RS_Settings.CAMERA_MOTION_*, как у WindowModeSetting.
class_name CameraMotionSetting
extends OptionSetting


func _ready() -> void:
	clear()
	option_values = [
		RS_Settings.CAMERA_MOTION_OFF,
		RS_Settings.CAMERA_MOTION_WEAK,
		RS_Settings.CAMERA_MOTION_FULL,
	]
	add_item("SETTINGS_CAMERA_MOTION_OFF")
	add_item("SETTINGS_CAMERA_MOTION_WEAK")
	add_item("SETTINGS_CAMERA_MOTION_FULL")
	super._ready()
