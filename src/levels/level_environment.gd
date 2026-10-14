## Окружение сцены под настройками игрока: ступень «Эффекты освещения» и флажок
## «Свечение» снимают экранные эффекты, которые игрок не тянет или не хочет,
## яркость поднимает тени гамма-кривой поверх тонмаппинга. Как и LevelLight, узел следит
## за настройкой сам — автолоад не знает, какая сцена загружена, и окружение
## сцены не ищет. Каждое окружение игры обязано идти через этот узел: окружение
## на Camera3D или голый WorldEnvironment настройку молча не слышат
## (settings_menu_check сверяет сцены).
##
## Настройка — потолок над тем, что поставил автор, а не включатель: «Высокие»
## не добавят SSR окружению, где его нет. Поэтому авторские флажки снимаются один
## раз, при входе в дерево, и каждая смена настройки считается от них, а не от
## того, что осталось после прошлой.
##
## Окружение копируется: .tres общий, и правка на месте ушла бы в каждую сцену с
## тем же ресурсом, а вторая такая сцена сняла бы «авторские» флажки уже
## урезанными. В редакторе скрипт не работает: там видно авторское.
##
## Туман по глубине, если его поставил автор, сгущается до полного ровно там,
## где лампы уровня погасли целиком (LevelLight.fade_begin + FADE_LENGTH):
## дальний конец длинного коридора растворяется в темноте, а не обрывается
## погасшими лампами. Дальность — от ступени теней, поэтому туман ближе на
## «Низком» и дальше на «Ультра». Начало держит долю, которую автор задал в
## ресурсе (fog_depth_begin / fog_depth_end): густоту крутят там, а не в коде.
##
## Яркость — подъём теней кривой в adjustment_color_correction (её Godot
## применяет после тонмаппинга, к sRGB). Ниже колена (SHADOW_KNEE) кадр
## возводится в 1 / яркость, выше — не трогается, и кривая входит в колено с
## наклоном 1, без излома. Чёрный остаётся нулём, почти-чёрное поднимается
## сильно — так устроены «подъём теней» мониторов и ползунки калибровки в играх.
## Отвергнуто по замерам 14.10 (знак, освещённый одним фоновым светом дна):
## - exposure_multiplier атрибутов камеры: Godot умножает на него энергию
##   источников света, а фоновый свет кладёт в шейдер как есть
##   (render_scene_data_rd.cpp) — знак 6/255 и на 50 %, и на 200 %;
## - tonemap_exposure и adjustment_brightness: множитель, а у чёрного это
##   крошечный шаг — 6 → 12/255 при ×2, и на одном мониторе из двух знак так и не
##   проступил; дальше умножать — выгорают лампы;
## - гамма на весь кадр: тьму поднимала, но и середину (128 → 181 при 2), и
##   комнаты с лампами пересвечивало — живой прогон.
## Авторская экспозиция (exposure_multiplier 1.5 мира — усиление ламп) остаётся
## как есть. На 1 кривой нет вовсе: картинка и цена кадра — авторские.
##
## Туман у слоя свой по плотности (RS_DepthLight.fog_density): у поверхности
## дымки нет вовсе, глубже она гуще. Крутизну нарастания задаёт автор окружения
## (fog_depth_curve): Godot считает туман как
## pow(smoothstep(начало, конец, d), кривая) · плотность.
##
## SDFGI (ступень «Ультра») при смене слоя перезапускается: поле расстояний он
## строит один раз и сам обновляет, только когда камера пересекает каскад, а все
## слои раскладываются от одной клетки — без перезапуска отражённый свет считался
## бы по стенам прошлого слоя.
##
## Свет слоя (RS_DepthLight) задаёт фоновому свету цвет и энергию, а туману —
## цвет; экспозицию не трогает (почему — там же). Фоновый свет окружение обязано
## держать в режиме «цвет»: в другом режиме цвет и энергия ничего не значат.
class_name LevelEnvironment
extends WorldEnvironment

## Текселей в кривой теней — по одному на значение восьмибитного кадра.
const CURVE_SIZE := 256
## Колено кривой теней: значение кадра в sRGB, выше которого яркость его не
## трогает. Ниже — тьма и полутени, выше — то, что освещено лампой. Поднять —
## тьма светлеет сильнее, но вместе с ней светлеют и полутени комнат; опустить —
## освещённое неприкосновеннее, но и тьме подъёма достаётся меньше.
const SHADOW_KNEE := 0.4

## Слушать ли яркость. Яркость — калибровка игрового мира под монитор; фон меню
## нарисован как картинка, и крутить его вместе с миром незачем.
@export var apply_brightness: bool = true
## Слушать ли свет слоя. Только окружение мира: «Выход в меню» из паузы забег не
## кончает, глубина в RunManager остаётся, и меню без этого флага потемнело бы
## до слоя, с которого из него вышли.
@export var apply_depth_lighting: bool = false

## Яркость, которую показать вместо применённой; меньше нуля — применённая.
## Экран калибровки крутит черновик: применять его на каждый шаг ползунка значило
## бы переприменять все настройки, а «Назад» обязана оставить применённое как
## было. Формула при этом одна — эта, иначе калибровка показывала бы не мир.
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
## Авторский свет — вне слоя (до первого спавна, после снятия) окружение
## возвращается к нему.
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


## Выключить на кадр и вернуть по настройке: так Godot строит поле заново. В один
## кадр выключение с включением сливаются, и поле остаётся прежним.
func _restart_sdfgi() -> void:
	if not environment.sdfgi_enabled:
		return
	environment.sdfgi_enabled = false
	await get_tree().process_frame
	if is_inside_tree():
		_on_settings_changed(SettingsManager.settings)


## Авторской цветокоррекции в окружениях игры нет; появится — её придётся
## запечь в ту же кривую, иначе яркость её затрёт.
func _apply_shadow_gamma(brightness: float) -> void:
	if is_equal_approx(brightness, 1.0):
		environment.adjustment_enabled = _authored_adjustment
		environment.adjustment_color_correction = null
		return
	environment.adjustment_enabled = true
	environment.adjustment_color_correction = shadow_curve(brightness)


## Кривая теней: тексель i — что станет со значением sRGB i/255. Восьми бит
## хватает: на выходе кадр всё равно восьмибитный.
static func shadow_curve(lift: float) -> ImageTexture:
	var image := Image.create(CURVE_SIZE, 1, false, Image.FORMAT_RGB8)
	for i in CURVE_SIZE:
		var v := shadow_lift(float(i) / (CURVE_SIZE - 1), lift)
		image.set_pixel(i, 0, Color(v, v, v))
	return ImageTexture.create_from_image(image)


## Ниже колена x = v / колено уходит в (1 − x²)·x^(1/подъём) + x³: в нуле это
## гамма, у колена — x с наклоном 1, и между ними кривая монотонна (проверено
## перебором на 0.5…3). Чистая гамма до колена дала бы излом наклона на нём —
## полосу смены контраста посреди полутеней.
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
