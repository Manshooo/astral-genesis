## Окружение сцены под настройками игрока: ступень «Эффекты освещения», флажок «Свечение», яркость (подъём теней
## кривой в adjustment_color_correction), туман и свет по глубине слоя. Каждое окружение игры обязано идти через этот узел
## (settings_menu_check). Настройка — потолок над авторским: авторские флажки снимаются раз при входе в дерево;
## окружение копируется (.tres общий). В редакторе скрипт не работает. Отвергнутые способы яркости и замеры —
## [[Конвенции проекта]] §6 и [[Калибровка яркости]]; свет по глубине — [[Визуальный стиль и текстуры]].
## SDFGI при смене слоя перезапускается: поле строится один раз, а все слои раскладываются от одной клетки.
## Туман по глубине сгущается до полного там, где лампы погасли (LevelLight.fade_begin + FADE_LENGTH); крутизна —
## fog_depth_curve автора.
class_name LevelEnvironment
extends WorldEnvironment

## Текселей в кривой теней — по одному на значение восьмибитного кадра.
const CURVE_SIZE := 256
## Колено кривой: значение sRGB, выше которого яркость кадр не трогает (тьма и полутени — ниже).
const SHADOW_KNEE := 0.4

## Слушать ли яркость (фон меню — картинка, крутить его с миром незачем).
@export var apply_brightness: bool = true
## Слушать ли свет слоя — только окружение мира: меню после «Выхода в меню» потемнело бы до слоя.
@export var apply_depth_lighting: bool = false

## Яркость вместо применённой; меньше нуля — применённая. Экран калибровки крутит черновик по той же формуле.
var preview_brightness := -1.0:
	set(value):
		preview_brightness = value
		if is_node_ready():
			_on_settings_changed(SettingsManager.settings)

var _authored_ssao := false
var _authored_ssil := false
var _authored_ssr := false
var _authored_sdfgi := false
var _authored_glow := false
var _authored_adjustment := false
## Доля начала тумана от его конца; -1 — тумана по глубине у автора нет.
var _fog_begin_share := -1.0
## Авторский свет — вне слоя окружение возвращается к нему.
var _authored_ambient_color := Color.BLACK
var _authored_ambient_energy := 0.0
var _authored_fog_color := Color.BLACK
var _authored_fog_density := 1.0


func _ready() -> void:
	if environment:
		environment = environment.duplicate()
		_authored_ssao = environment.ssao_enabled
		_authored_ssil = environment.ssil_enabled
		_authored_ssr = environment.ssr_enabled
		_authored_sdfgi = environment.sdfgi_enabled
		_authored_glow = environment.glow_enabled
		_authored_adjustment = environment.adjustment_enabled
		if environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH \
				and environment.fog_depth_end > 0.0:
			_fog_begin_share = clampf(environment.fog_depth_begin / environment.fog_depth_end, 0.0, 1.0)
		_authored_ambient_color = environment.ambient_light_color
		_authored_ambient_energy = environment.ambient_light_energy
		_authored_fog_color = environment.fog_light_color
		_authored_fog_density = environment.fog_density
	SettingsManager.settings_changed.connect(_on_settings_changed)
	_on_settings_changed(SettingsManager.settings)
	if apply_depth_lighting and environment:
		RunManager.layer_changed.connect(_on_layer_changed)
		_on_layer_changed(RunManager.current_depth)
	if _authored_sdfgi:
		RunManager.layer_changed.connect(_restart_sdfgi.unbind(1))


func _on_layer_changed(depth: int) -> void:
	var layer: RS_DepthLight = RS_DepthLighting.layer(depth) if depth != RunManager.NO_DEPTH else null
	environment.ambient_light_color = layer.ambient_color if layer else _authored_ambient_color
	environment.ambient_light_energy = layer.ambient_energy if layer else _authored_ambient_energy
	environment.fog_light_color = layer.fog_color if layer else _authored_fog_color
	environment.fog_density = layer.fog_density if layer else _authored_fog_density


## Выключить на кадр и вернуть: в один кадр выключение с включением сливаются, поле остаётся прежним.
func _restart_sdfgi() -> void:
	if not environment.sdfgi_enabled:
		return
	environment.sdfgi_enabled = false
	await get_tree().process_frame
	if is_inside_tree():
		_on_settings_changed(SettingsManager.settings)


## Авторской цветокоррекции в окружениях игры нет; появится — запечь в ту же кривую, иначе яркость её затрёт.
func _apply_shadow_gamma(brightness: float) -> void:
	if is_equal_approx(brightness, 1.0):
		environment.adjustment_enabled = _authored_adjustment
		environment.adjustment_color_correction = null
		return
	environment.adjustment_enabled = true
	environment.adjustment_color_correction = shadow_curve(brightness)


## Кривая теней: тексель i — что станет со значением sRGB i/255.
static func shadow_curve(lift: float) -> ImageTexture:
	var image := Image.create(CURVE_SIZE, 1, false, Image.FORMAT_RGB8)
	for i in CURVE_SIZE:
		var v := shadow_lift(float(i) / (CURVE_SIZE - 1), lift)
		image.set_pixel(i, 0, Color(v, v, v))
	return ImageTexture.create_from_image(image)


## Ниже колена x = v / колено уходит в (1 − x²)·x^(1/подъём) + x³: гамма в нуле, наклон 1 у колена, монотонна (перебор 0.5…3).
static func shadow_lift(v: float, lift: float) -> float:
	if v >= SHADOW_KNEE:
		return v
	var x := v / SHADOW_KNEE
	var lifted := (1.0 - x * x) * pow(x, 1.0 / maxf(lift, 0.01)) + x * x * x
	return SHADOW_KNEE * lifted


func _on_settings_changed(settings: RS_Settings) -> void:
	if settings == null:
		return
	if environment == null:
		return
	if apply_brightness:
		_apply_shadow_gamma(preview_brightness if preview_brightness >= 0.0 else settings.brightness)
	var level := SettingsManager.effects_level()
	environment.ssao_enabled = _authored_ssao and level != null and level.ssao
	environment.ssil_enabled = _authored_ssil and level != null and level.ssil
	environment.ssr_enabled = _authored_ssr and level != null and level.ssr
	environment.sdfgi_enabled = _authored_sdfgi and level != null and level.sdfgi
	environment.glow_enabled = _authored_glow and settings.glow_enabled
	if _fog_begin_share >= 0.0:
		var fog_end := LevelLight.fade_begin() + LevelLight.FADE_LENGTH
		environment.fog_depth_end = fog_end
		environment.fog_depth_begin = fog_end * _fog_begin_share
