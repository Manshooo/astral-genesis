# res://src/ui/settings/resolution_setting.gd
## Список разрешений: строится при открытии из влезающих в экран (SettingsManager.resolution_options), первым «Авто» (Vector2i.ZERO). Сохранённое, которого на экране нет, показывается как «Авто» (OptionSetting берёт первый пункт).
class_name ResolutionSetting
extends OptionSetting


func _ready() -> void:
	clear()
	option_values = [Vector2i.ZERO]
	add_item("SETTINGS_RES_AUTO")
	for size: Vector2i in SettingsManager.resolution_options():
		option_values.append(size)
		add_item("%d × %d" % [size.x, size.y])
	super._ready()
