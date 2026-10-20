## Список «Эффекты освещения»: ступени из RS_GraphicsPresetLibrary.effects_levels, «Выкл» первой; новая ступень — строка в data/graphics_presets.tres.
class_name ScreenEffectsSetting
extends OptionSetting


func _ready() -> void:
	clear()
	option_values.clear()
	var library := SettingsManager.GRAPHICS_PRESETS
	if library:
		for level in library.effects_levels:
			add_item(level.display_name)
			option_values.append(level.id)
	super._ready()
