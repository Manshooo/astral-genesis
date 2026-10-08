## Список «Эффекты освещения»: ступени из каталога
## (RS_GraphicsPresetLibrary.effects_levels), «Выкл» среди них первой. Пункты
## строятся из данных, как у ShadowQualitySetting: новая ступень — строка в
## data/graphics_presets.tres, а не правка сцены меню.
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
