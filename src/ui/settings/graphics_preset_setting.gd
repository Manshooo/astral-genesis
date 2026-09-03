# res://src/ui/settings/graphics_preset_setting.gd
## Список пресетов графики — единственный контрол настроек, чьи пункты не
## авторятся в сцене руками: строится из SettingsManager.GRAPHICS_PRESETS, плюс
## всегда последним пунктом "Собственный" (не хранится в каталоге — это не
## пресет, а отметка «игрок отступил от любого из них», см. settings_menu.gd).
## Так добавление пресета в data/graphics_presets.tres попадает в выпадающий
## список само, без правки этой сцены.
class_name GraphicsPresetSetting
extends OptionSetting

const CUSTOM_ID := &"custom"
const CUSTOM_LABEL := "Собственный"

func _ready() -> void:
	clear()
	option_values.clear()
	var library := SettingsManager.GRAPHICS_PRESETS
	if library:
		for preset in library.presets:
			add_item(preset.display_name)
			option_values.append(preset.id)
	add_item(CUSTOM_LABEL)
	option_values.append(CUSTOM_ID)
	super._ready()
