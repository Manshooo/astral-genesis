# res://src/levels/level_light.gd
## Лампа комнаты или тайла коридора: тень по настройке «Тени» (RS_ShadowLevel.shadow_distance, при «Выкл» нет), ячейки атласа
## распределяет ShadowBudget (группа GROUP). Следит за настройкой сама, не автолоад. Энергию масштабирует слой
## (RS_DepthLight.lamp_energy_scale) по сигналу RunManager: в _ready глубины ещё нет. В редакторе не работает.
class_name LevelLight
extends Light3D

const GROUP := &"level_lights"
## За сколько метров лампа гаснет целиком: резкий обрыв заметен (клетка — 8 м).
const FADE_LENGTH := 8.0

## Энергия из сцены — множитель слоя считается от неё.
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
	for child in get_children():
		if child is LampFixture:
			(child as LampFixture).refresh(light_color, light_energy)


## Лампа гаснет там же, где перестаёт отбрасывать тень: дальше светила бы сквозь стены.
func _on_settings_changed(_settings: RS_Settings) -> void:
	var level := SettingsManager.shadow_level()
	shadow_enabled = level != null
	distance_fade_enabled = true
	distance_fade_length = FADE_LENGTH
	distance_fade_begin = fade_begin()
	if level:
		distance_fade_shadow = level.shadow_distance


## С какой дальности лампы гаснут: дальность теней, без теней — unshadowed_light_distance. Одна функция на лампы и туман.
static func fade_begin() -> float:
	var level := SettingsManager.shadow_level()
	return level.shadow_distance if level else SettingsManager.GRAPHICS_PRESETS.unshadowed_light_distance


## Докуда достаёт свет лампы — радиус сферы.
static func reach_of(light: Light3D) -> float:
	if light is OmniLight3D:
		return (light as OmniLight3D).omni_range
	if light is SpotLight3D:
		return (light as SpotLight3D).spot_range
	return 0.0
