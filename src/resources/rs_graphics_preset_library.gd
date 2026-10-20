# res://src/resources/rs_graphics_preset_library.gd
## Каталог пресетов графики (data/graphics_presets.tres): пресеты и ступени теней/эффектов; расширяется данными, список в
## настройках строится по массиву (GraphicsPresetSetting), применённый пресет ищет SettingsManager по id.
class_name RS_GraphicsPresetLibrary
extends Resource

@export var presets: Array[RS_GraphicsPreset] = []
## Ступени «Тени» от дешёвой к дорогой, после «Выкл».
@export var shadow_levels: Array[RS_ShadowLevel] = []
## Докуда светят лампы уровня при выключенных тенях (с тенями — на дальности теней ступени).
@export var unshadowed_light_distance: float = 30.0
## Ступени «Эффекты освещения» от дешёвой к дорогой, «Выкл» первой.
@export var effects_levels: Array[RS_ScreenEffectsLevel] = []


func by_id(id: StringName) -> RS_GraphicsPreset:
	for p in presets:
		if p != null and p.id == id:
			return p
	return null


## Ступень теней по id или null (SHADOWS_OFF или пропавший id — «теней нет»).
func shadow_level(id: StringName) -> RS_ShadowLevel:
	for level in shadow_levels:
		if level != null and level.id == id:
			return level
	return null


## Ступень эффектов по id или null (пропавший id — «нет»: дешевле промахнуться вниз).
func effects_level(id: StringName) -> RS_ScreenEffectsLevel:
	for level in effects_levels:
		if level != null and level.id == id:
			return level
	return null
