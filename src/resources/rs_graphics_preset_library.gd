# res://src/resources/rs_graphics_preset_library.gd
## Каталог пресетов графики (data/graphics_presets.tres). Расширяется
## добавлением элемента в presets — без правок кода: выпадающий список в
## настройках строится по этому массиву (см. GraphicsPresetSetting), а
## SettingsManager ищет применённый пресет по id через by_id().
##
## Ступени теней лежат здесь же: пресет ссылается на ступень по id, и держать
## их в одном файле — значит видеть «Средний = тени Средние» рядом с тем, что
## такое «Средние».
class_name RS_GraphicsPresetLibrary
extends Resource

@export var presets: Array[RS_GraphicsPreset] = []
## Ступени настройки «Тени» от дешёвой к дорогой — в этом порядке они и идут в
## списке, после «Выкл».
@export var shadow_levels: Array[RS_ShadowLevel] = []
## Докуда светят лампы уровня при выключенных тенях (LevelLight). С тенями лампа
## гаснет на дальности теней своей ступени; без них ей не на что опереться, и
## дальность — отсюда.
@export var unshadowed_light_distance: float = 30.0
## Ступени настройки «Эффекты освещения» от дешёвой к дорогой, «Выкл» первой.
@export var effects_levels: Array[RS_ScreenEffectsLevel] = []


func by_id(id: StringName) -> RS_GraphicsPreset:
	for p in presets:
		if p != null and p.id == id:
			return p
	return null


## Ступень теней по id или null — для SHADOWS_OFF и для id, пропавшего из
## каталога (сейв старше проекта): и то и другое значит «теней нет».
func shadow_level(id: StringName) -> RS_ShadowLevel:
	for level in shadow_levels:
		if level != null and level.id == id:
			return level
	return null


## Ступень эффектов по id или null — id, пропавший из каталога (сейв старше
## проекта), значит «эффектов нет»: дешевле промахнуться вниз, чем вверх.
func effects_level(id: StringName) -> RS_ScreenEffectsLevel:
	for level in effects_levels:
		if level != null and level.id == id:
			return level
	return null
