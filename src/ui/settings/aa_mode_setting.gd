# res://src/ui/settings/aa_mode_setting.gd
## Список режимов сглаживания (RS_GraphicsPreset.AAMode): пункты заводятся в коде, не через Items — popup/item_N/* в .tscn вручную собирать ненадёжно.
class_name AAModeSetting
extends OptionSetting

func _ready() -> void:
	clear()
	option_values = [
		RS_GraphicsPreset.AAMode.OFF,
		RS_GraphicsPreset.AAMode.FXAA,
		RS_GraphicsPreset.AAMode.MSAA_2X,
		RS_GraphicsPreset.AAMode.MSAA_4X,
	]
	# Ключом переводится только «Выкл»: FXAA и MSAA — имена.
	add_item("SETTINGS_AA_OFF")
	add_item("FXAA")
	add_item("MSAA 2x")
	add_item("MSAA 4x")
	super._ready()
