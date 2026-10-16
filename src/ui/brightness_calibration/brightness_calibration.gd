# res://src/ui/brightness_calibration/brightness_calibration.gd
## Экран калибровки яркости: три знака комплекса на чёрном и ползунок «Яркости» —
## «левый виден, средний едва различим, правый не виден». Открывается на первом запуске
## (главное меню) и из настроек и подбирает ту же RS_Settings.brightness. Что
## делать с подобранным, решает тот, кто открыл: меню применяет сразу, настройки
## кладут в черновик — у них своя кнопка «Применить».
##
## Знаков три — общая практика SDR-калибровки в играх (14.10): все на чёрном и
## все тёмные, разной тьмы; ручка одна. «Едва виден» — эталон, порог видимости;
## «не виден» держит верхнюю границу: с одним знаком игрок, который «чтобы точно
## было видно» уводит ползунок вверх, делает тьму без лампы необязательной, и
## ничто на экране ему этого не говорит; «виден» — опора глазу: показывает, где
## знак и как он выглядит, когда его видно, иначе на тёмной матрице не понять,
## есть ли вообще что искать. Тёмный, средний и светлый эталоны с отдельными
## ручками — схема HDR (чёрная точка, бумажный белый, пик): в SDR светлый край
## монитор показывает одинаково на любой матрице, расходятся они в чёрном.
##
## Знаки не нарисованы интерфейсом, а сняты камерой в своём мире: яркость — это
## кривая теней в окружении мира (LevelEnvironment), и 2D-картинку она не
## задевает. Окружение — копия окружения мира (тот же тонмаппинг и та же
## экспозиция, поверх которых ложится кривая).
##
## Эталон — тьма слоя reference_depth (L4): средний знак — плита со стенным
## альбедо, освещённая ТОЛЬКО фоновым светом этого слоя, то есть стена в тёмном
## закоулке без лампы. Знак «едва виден» ровно на той яркости, на которой и
## закоулок L4 выглядит задуманным (живой прогон 14.10: у автора это 1.25), —
## это и есть калибровка: эталон задан значением кадра, а глаз и матрица у
## каждого свои, и игрок двигает ползунок, пока знак не станет таким же. Слой назван явно, а не
## «самый глубокий»: свет L5 заведён раньше, чем слой появился в забеге, и
## подобранная игроками яркость не должна сдвигаться ни с его приходом, ни с
## правкой его чисел.
##
## Свет знака — СЕРЫЙ той же яркости, что фоновый свет слоя: эталон калибровки —
## градация серого, иначе игрок подбирал бы яркость по оттенку, а не по свету
## (синий канал на тёмной матрице гаснет раньше других).
##
## Из окружения мира сняты эффекты, зависящие от геометрии и ступени: SSAO,
## SDFGI, туман, свечение. Яркость — про монитор, а не про цену кадра, и одна
## калибровка обязана годиться на любой ступени; что SDFGI на «Ультра» темнит
## углы, лечится толстыми стенами. LevelEnvironment эффекты только снимает, так
## что снятое здесь ступень обратно не включит.
##
## Фон — чистый чёрный, а не bg_void меню: знаки сравниваются с тьмой мира, а она
## ноль.
class_name UI_BrightnessCalibration
extends UI_MenuScreen

signal confirmed(brightness: float)

const WORLD_ENVIRONMENT := "res://assets/world_environment.tres"

## Слой, чья тьма — эталон. Сменить — сменить задуманную норму для всех игроков.
@export var reference_depth := 4
## Альбедо стены, которой притворяется средний знак. Стены кита пока в прототипной
## палитре; когда у стены будет свой материал — его средний тон.
@export_range(0.0, 1.0, 0.01) var reference_albedo := 0.35
## Доли света крайних знаков от среднего — в ЛИНЕЙНОМ свете, а не от альбедо в
## инспекторе: тот в sRGB, и 0.4 от него — это 0.18 света, правый знак не
## проступал даже на потолке ползунка. Подъём теней поднимает тёмное сильнее
## светлого, так что при перекрутке правый догоняет средний.
@export_range(0.05, 0.95, 0.01) var hidden_share := 0.4
## Левый, «виден»: в несколько раз светлее порога, но всё ещё тьма без лампы —
## 3 лежит между закоулками L3 (×2.3 света L4) и L2 (×4).
@export_range(1.5, 10.0, 0.1) var clear_share := 3.0

## С какой яркости начать — зовущий ставит до добавления в дерево.
var brightness := 1.0

@onready var _slider: SliderSetting = %Slider
@onready var _environment: LevelEnvironment = %Environment


## Окружение ставится до того, как LevelEnvironment войдёт в дерево и снимет
## «авторские» значения: дети готовы раньше родителя, и в _ready было бы поздно —
## узел уже запомнил бы флажки заглушки, а не мира.
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


## Серый той же яркости: яркость считается в линейном свете (цвет в инспекторе —
## sRGB), весами Rec. 709 — теми, что глаз.
static func gray_of(color: Color) -> Color:
	var luminance := color.srgb_to_linear().get_luminance()
	return Color(luminance, luminance, luminance).linear_to_srgb()


## Альбедо со светом, умноженным на [param share], — в линейном свете.
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
