# res://src/ui/settings/aa_mode_setting.gd
## Список режимов сглаживания. Пункты — фиксированный, короткий список значений
## RS_GraphicsPreset.AAMode, поэтому заводится в коде, а не через Items
## редактора: собрать popup/item_N/* вручную в .tscn ненадёжно, а вариантов и
## так конечное число.
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
	add_item("Выкл")
	add_item("FXAA")
	add_item("MSAA 2x")
	add_item("MSAA 4x")
	super._ready()
