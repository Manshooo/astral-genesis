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
## В редакторе скрипт не работает: значения в сцене (тени вкл, 40 м) — это
## ступень «Средние», то, что художник и видит при правке света.
class_name LevelLight
extends Light3D

const GROUP := &"level_lights"


func _ready() -> void:
	add_to_group(GROUP)
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed(SettingsManager.settings)


func _on_settings_changed(_settings: RS_Settings) -> void:
	var level := SettingsManager.shadow_level()
	shadow_enabled = level != null
	if level:
		distance_fade_enabled = true
		distance_fade_shadow = level.shadow_distance


## Докуда достаёт свет лампы — радиус сферы, за которой она ничего не освещает.
static func reach_of(light: Light3D) -> float:
	if light is OmniLight3D:
		return (light as OmniLight3D).omni_range
	if light is SpotLight3D:
		return (light as SpotLight3D).spot_range
	return 0.0
