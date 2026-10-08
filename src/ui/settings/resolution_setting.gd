# res://src/ui/settings/resolution_setting.gd
## Список разрешений. Строится при открытии из того, что влезает в экран
## (SettingsManager.resolution_options), а не авторится в сцене: на мониторе
## 1080p пункт 4K был бы обещанием, которое нечем выполнить. Первым — «Авто»
## (Vector2i.ZERO): в окне — базовый размер проекта, во весь экран — экран.
##
## Сохранённое разрешение, которого на этом экране нет (сейв с другого
## монитора), показывается как «Авто» — OptionSetting выбирает первый пункт.
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
