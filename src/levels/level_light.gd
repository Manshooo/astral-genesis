# res://src/levels/level_light.gd
## Лампа комнаты или тайла коридора: тень отбрасывает по настройке «Тени» —
## дальность из её ступени (RS_ShadowLevel.shadow_distance), а при «Выкл» не
## отбрасывает вовсе. Какой из ламп в кадре тень достанется, если на всех не
## хватает ячеек атласа, решает ShadowBudget — лампа для этого в группе GROUP.
##
## Лампа следит за настройкой сама, а не SettingsManager обходит дерево: автолоад
## не знает, какая сцена загружена (Конвенции проекта → настройки графики), а
## лампы слоя спавнятся и уходят вместе с комнатами. Подписка рвётся сама, когда
## лампу освобождают.
##
## Энергию лампы масштабирует слой, на котором она стоит (RS_DepthLight
## .lamp_energy_scale): глубже — тусклее. Слой узнаётся из сигнала RunManager, а не
## при входе в дерево: стример выставляет глубину, только заспавнив слой целиком,
## так что в _ready лампы слоя глубины ещё не знают.
##
## В редакторе скрипт не работает: значения в сцене (тени вкл, 40 м) — это
## ступень «Средние», то, что художник и видит при правке света.
class_name LevelLight
extends Light3D

const GROUP := &"level_lights"
## За сколько метров лампа гаснет целиком после начала затухания: резкий обрыв
## на ходу заметен, а клетка — 8 м.
const FADE_LENGTH := 8.0

## Энергия из сцены — множитель слоя считается от неё, а не от прошлого слоя.
var _authored_energy := 1.0


func _ready() -> void:
	add_to_group(GROUP)
	_authored_energy = light_energy
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed(SettingsManager.settings)
	RunManager.layer_changed.connect(_on_layer_changed)
	_on_layer_changed(RunManager.current_depth)


func _on_layer_changed(depth: int) -> void:
	var layer: RS_DepthLight = RS_DepthLighting.layer(depth) if depth != RunManager.NO_DEPTH else null
	light_energy = _authored_energy * (layer.lamp_energy_scale if layer else 1.0)


## Лампа гаснет там же, где перестаёт отбрасывать тень: дальше она светила бы
## без тени — то есть сквозь стены — и тратила кадр на то, что за ними. В сценах
## стояло 200 м, то есть «не гаснуть никогда».
func _on_settings_changed(_settings: RS_Settings) -> void:
	var level := SettingsManager.shadow_level()
	shadow_enabled = level != null
	distance_fade_enabled = true
	distance_fade_length = FADE_LENGTH
	distance_fade_begin = fade_begin()
	if level:
		distance_fade_shadow = level.shadow_distance


## С какой дальности лампы уровня начинают гаснуть: дальность теней ступени, а
## без теней — unshadowed_light_distance каталога. Одна функция на лампы и туман
## (LevelEnvironment): туман обязан сгущаться ровно туда, где свет кончается, и
## две копии этого правила разошлись бы при первой правке.
static func fade_begin() -> float:
	var level := SettingsManager.shadow_level()
	return level.shadow_distance if level else SettingsManager.GRAPHICS_PRESETS.unshadowed_light_distance


## Докуда достаёт свет лампы — радиус сферы, за которой она ничего не освещает.
static func reach_of(light: Light3D) -> float:
	if light is OmniLight3D:
		return (light as OmniLight3D).omni_range
	if light is SpotLight3D:
		return (light as SpotLight3D).spot_range
	return 0.0
