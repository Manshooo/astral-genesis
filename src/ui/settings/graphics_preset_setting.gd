# res://src/ui/settings/graphics_preset_setting.gd
## Список пресетов графики — единственный контрол с пунктами не из сцены: строится из SettingsManager.GRAPHICS_PRESETS, последним «Собственный» (не в каталоге — отметка отступления, см. settings_menu.gd).
class_name GraphicsPresetSetting
extends OptionSetting

const CUSTOM_ID := &"custom"
const CUSTOM_LABEL := "SETTINGS_PRESET_CUSTOM"

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
