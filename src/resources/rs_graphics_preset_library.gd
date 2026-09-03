# res://src/resources/rs_graphics_preset_library.gd
## Каталог пресетов графики (data/graphics_presets.tres). Расширяется
## добавлением элемента в presets — без правок кода: выпадающий список в
## настройках строится по этому массиву (см. GraphicsPresetSetting), а
## SettingsManager ищет применённый пресет по id через by_id().
class_name RS_GraphicsPresetLibrary
extends Resource

@export var presets: Array[RS_GraphicsPreset] = []


func by_id(id: StringName) -> RS_GraphicsPreset:
	for p in presets:
		if p != null and p.id == id:
			return p
	return null
