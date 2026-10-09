## Окружение сцены под настройками игрока: ступень «Эффекты освещения» и флажок
## «Свечение» снимают экранные эффекты, которые игрок не тянет или не хочет,
## яркость умножает авторскую экспозицию камеры. Как и LevelLight, узел следит
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
## Окружение и атрибуты камеры копируются: .tres общий, и правка на месте ушла бы
## в каждую сцену с тем же ресурсом, а вторая такая сцена сняла бы «авторские»
## флажки уже урезанными. В редакторе скрипт не работает: там видно авторское.
##
## Туман по глубине, если его поставил автор, сгущается до полного ровно там,
## где лампы уровня погасли целиком (LevelLight.fade_begin + FADE_LENGTH):
## дальний конец длинного коридора растворяется в темноте, а не обрывается
## погасшими лампами. Дальность — от ступени теней, поэтому туман ближе на
## «Низком» и дальше на «Ультра». Начало держит долю, которую автор задал в
## ресурсе (fog_depth_begin / fog_depth_end): густоту крутят там, а не в коде.
##
## Яркость — через exposure_multiplier, до тонмаппинга, а не через
## adjustment_brightness после него: экспозиция сжимает пересветы тем же
## тонмаппингом, а поправка после него поднимает чёрное в серую дымку.
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

## Слушать ли яркость. Яркость — калибровка игрового мира под монитор; фон меню
## нарисован как картинка, и крутить его вместе с миром незачем.
@export var apply_brightness: bool = true
## Слушать ли свет слоя. Только окружение мира: «Выход в меню» из паузы забег не
## кончает, глубина в RunManager остаётся, и меню без этого флага потемнело бы
## до слоя, с которого из него вышли.
@export var apply_depth_lighting: bool = false

var _authored_ssao := false
var _authored_ssil := false
var _authored_ssr := false
var _authored_sdfgi := false
var _authored_glow := false
var _authored_exposure := 1.0
## Доля начала тумана от его конца; -1 — тумана по глубине у автора нет.
var _fog_begin_share := -1.0
## Авторский свет — вне слоя (до первого спавна, после снятия) окружение
## возвращается к нему.
var _authored_ambient_color := Color.BLACK
var _authored_ambient_energy := 0.0
var _authored_fog_color := Color.BLACK


func _ready() -> void:
	if environment:
		environment = environment.duplicate()
		_authored_ssao = environment.ssao_enabled
		_authored_ssil = environment.ssil_enabled
		_authored_ssr = environment.ssr_enabled
		_authored_sdfgi = environment.sdfgi_enabled
		_authored_glow = environment.glow_enabled
		if environment.fog_enabled and environment.fog_mode == Environment.FOG_MODE_DEPTH \
				and environment.fog_depth_end > 0.0:
			_fog_begin_share = clampf(environment.fog_depth_begin / environment.fog_depth_end, 0.0, 1.0)
		_authored_ambient_color = environment.ambient_light_color
		_authored_ambient_energy = environment.ambient_light_energy
		_authored_fog_color = environment.fog_light_color
	# Без атрибутов камеры экспозиции нет вовсе; пустые практические атрибуты
	# картинку не меняют (множитель 1, автоэкспозиция и глубина резкости выкл).
	camera_attributes = camera_attributes.duplicate() if camera_attributes else CameraAttributesPractical.new()
	_authored_exposure = camera_attributes.exposure_multiplier
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


## Выключить на кадр и вернуть по настройке: так Godot строит поле заново. В один
## кадр выключение с включением сливаются, и поле остаётся прежним.
func _restart_sdfgi() -> void:
	if not environment.sdfgi_enabled:
		return
	environment.sdfgi_enabled = false
	await get_tree().process_frame
	if is_inside_tree():
		_on_settings_changed(SettingsManager.settings)


func _on_settings_changed(settings: RS_Settings) -> void:
	if settings == null:
		return
	if apply_brightness:
		camera_attributes.exposure_multiplier = _authored_exposure * settings.brightness
	if environment == null:
		return
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
