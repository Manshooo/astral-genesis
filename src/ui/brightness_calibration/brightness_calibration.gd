# res://src/ui/brightness_calibration/brightness_calibration.gd
## Экран калибровки яркости: три знака комплекса на чёрном (виден / едва различим / не виден) и ползунок RS_Settings.brightness; открывается на первом запуске и из настроек,
## применяет решение зовущий. Знаки сняты камерой в своём мире (яркость — кривая в окружении мира, 2D её не задевает); эталон — тьма слоя reference_depth, свет знака серый,
## из окружения сняты эффекты ступени. Обоснование знаков и замеры — [[Калибровка яркости]].
class_name UI_BrightnessCalibration
extends UI_MenuScreen

signal confirmed(brightness: float)

const WORLD_ENVIRONMENT := "res://assets/world_environment.tres"

## Слой, чья тьма — эталон; сменить — сменить задуманную норму для всех.
@export var reference_depth := 4
## Альбедо стены, которой притворяется средний знак.
@export_range(0.0, 1.0, 0.01) var reference_albedo := 0.35
## Доли света крайних знаков от среднего — в ЛИНЕЙНОМ свете (альбедо в sRGB дало бы 0.18 света); подъём теней поднимает тёмное сильнее.
@export_range(0.05, 0.95, 0.01) var hidden_share := 0.4
## Левый, «виден»: в несколько раз светлее порога, но всё ещё тьма без лампы.
@export_range(1.5, 10.0, 0.1) var clear_share := 3.0

## С какой яркости начать — зовущий ставит до добавления в дерево.
var brightness := 1.0

@onready var _slider: SliderSetting = %Slider
@onready var _environment: LevelEnvironment = %Environment


## Окружение ставится до того, как LevelEnvironment войдёт в дерево и запомнит «авторские» значения: в _ready поздно.
func _enter_tree() -> void:
	if is_node_ready():
		return
	(get_node("%Environment") as WorldEnvironment).environment = _environment_like_reference_layer()
	var albedo := Color(reference_albedo, reference_albedo, reference_albedo)
	_paint_sign(get_node("%Clear") as MeshInstance3D, _scaled(albedo, clear_share))
	_paint_sign(get_node("%Faint") as MeshInstance3D, albedo)
	_paint_sign(get_node("%Hidden") as MeshInstance3D, _scaled(albedo, hidden_share))


func _ready() -> void:
	super._ready()
	_slider.set_setting_value(brightness)
	_slider.setting_changed.connect(_on_slider_changed)
	_on_slider_changed(_slider)


func _environment_like_reference_layer() -> Environment:
	var environment := (load(WORLD_ENVIRONMENT) as Environment).duplicate() as Environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.ssr_enabled = false
	environment.sdfgi_enabled = false
	environment.glow_enabled = false
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var layer := RS_DepthLighting.layer(reference_depth)
	if layer:
		environment.ambient_light_color = gray_of(layer.ambient_color)
		environment.ambient_light_energy = layer.ambient_energy
	return environment


## Серый той же яркости: считается в линейном свете, весами Rec. 709.
static func gray_of(color: Color) -> Color:
	var luminance := color.srgb_to_linear().get_luminance()
	return Color(luminance, luminance, luminance).linear_to_srgb()


## Альбедо со светом, умноженным на share, — в линейном свете.
static func _scaled(albedo: Color, share: float) -> Color:
	return (albedo.srgb_to_linear() * share).clamp().linear_to_srgb()


## Материал копируется: он общий у сцены, а у знаков альбедо разное.
func _paint_sign(sign_mesh: MeshInstance3D, albedo: Color) -> void:
	var sign_material := (sign_mesh.get_active_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	sign_material.albedo_color = albedo
	sign_mesh.material_override = sign_material


func _on_slider_changed(_control: SliderSetting) -> void:
	brightness = _slider.get_setting_value()
	_environment.preview_brightness = brightness


func _on_done_pressed() -> void:
	confirmed.emit(brightness)
	UIManager.close_top()


func _on_back_pressed() -> void:
	UIManager.close_top()
