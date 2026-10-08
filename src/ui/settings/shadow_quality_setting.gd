# res://src/ui/settings/shadow_quality_setting.gd
## Список «Тени»: «Выкл» и ступени из каталога (RS_GraphicsPresetLibrary.
## shadow_levels). Один список вместо прежних флажка и ползунка атласа: ползунок
## шёл шагом 512, и 1536 или 3072 движок всё равно округлял до степени двойки —
## игрок крутил деления, которые ничего не меняли, а дальность теней, главная
## ручка цены кадра, не настраивалась вовсе. Пункты строятся из данных, как у
## GraphicsPresetSetting: новая ступень — строка в data/graphics_presets.tres.
class_name ShadowQualitySetting
extends OptionSetting

const OFF_LABEL := "SETTINGS_OFF"


func _ready() -> void:
	clear()
	option_values.clear()
	add_item(OFF_LABEL)
	option_values.append(RS_GraphicsPreset.SHADOWS_OFF)
	var library := SettingsManager.GRAPHICS_PRESETS
	if library:
		for level in library.shadow_levels:
			add_item(level.display_name)
			option_values.append(level.id)
	super._ready()
