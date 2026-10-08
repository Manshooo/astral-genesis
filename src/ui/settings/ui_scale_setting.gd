# res://src/ui/settings/ui_scale_setting.gd
## Список масштабов интерфейса: «Авто» (0 — растягивается по окну) и
## фиксированные множители, при которых базовое окно ещё влезает в экран
## (SettingsManager.ui_scale_options). Строится кодом по той же причине, что и
## ResolutionSetting: набор зависит от монитора.
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
