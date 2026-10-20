# res://src/ui/settings/ui_scale_setting.gd
## Список масштабов интерфейса: «Авто» (0) и фиксированные, при которых базовое окно влезает в экран (SettingsManager.ui_scale_options); кодом, как ResolutionSetting.
class_name UiScaleSetting
extends OptionSetting


func _ready() -> void:
	clear()
	option_values = [0.0]
	add_item("SETTINGS_UI_SCALE_AUTO")
	for scale: float in SettingsManager.ui_scale_options():
		option_values.append(scale)
		add_item("%d %%" % roundi(scale * 100.0))
	super._ready()
