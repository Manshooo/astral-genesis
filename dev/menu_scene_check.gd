extends "res://dev/check_harness.gd"
## Проверка живой сцены за главным меню (L_menu_map): грузится и крутится без
## единой ошибки движка, свечение колбы и лампа ведут себя так, как велит §8
## «Меню — спека», а подмена заглушек артом остаётся подменой ресурса.
## Запускать: godot --headless dev/menu_scene_check.tscn
##
## Ломается здесь всё тихо. Метка BodyAnchor, переименованная в модели, — и мозг
## молча висит в запасной точке; стекло под другим именем — и туман колбы не
## совпадает с ней; лампа, у которой спутан порядок вспышек, — горит ровно или
## не горит вовсе. Ошибкой ничего из этого не выглядит. Пикселей headless не
## рисует, поэтому сверяется вход картинки: энергия света, размеры тумана,
## позиции, назначенные текстуры.
##
## Своё отличие от обвязки — сторож ловит ЛЮБУЮ ошибку движка, а не только
## ошибки скрипта: сцена меню первой встречает игрока, и битая ссылка на ресурс
## или неверный путь узла в ней — тоже провал.

const MENU := preload("res://src/levels/menu_map/L_menu_map.tscn")
## Имена меток и доля колбы — у скрипта сцены, а не литералами здесь: сверять
## надо то, чего ждёт сцена, а не то, что когда-то в неё вписали.
const MENU_SCRIPT := preload("res://src/levels/menu_map/l_menu_map.gd")
const GLASS := preload("res://assets/materials/MAT_incubator_glass.tres")

var _engine_errors := _EngineErrorCounter.new()
## Полем, а не const: свойство константы анализатор GDScript сворачивает при
## разборе, и `CONST.emission_energy_multiplier` вечно читал бы значение из .tres,
## а не живого ресурса, — ассерт про возврат материала зеленел бы на мутации.
var _lamp_glow: StandardMaterial3D = preload("res://assets/materials/MAT_light_fluorescent_glow.tres")


## Считает ошибки движка любого вида, кроме предупреждений.
class _EngineErrorCounter:
	extends Logger

	var _mutex := Mutex.new()
	var _count := 0
	var _first := ""

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array[ScriptBacktrace],
	) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		_count += 1
		if _first == "":
			_first = "%s (%s:%d, %s)" % [rationale if rationale != "" else code, file, line, function]
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func count() -> int:
		_mutex.lock()
		var result := _count
		_mutex.unlock()
		return result

	func first() -> String:
		_mutex.lock()
		var result := _first
		_mutex.unlock()
		return result


func _ready() -> void:
	OS.add_logger(_engine_errors)
	var authored_lamp_glow := _lamp_glow.emission_energy_multiplier

	await _check_loads_clean()
	await _check_glow()
	await _check_flicker()
	await _check_fallback_flask()
	await _check_model_contract()

	_check(
		"материал лампы после меню — авторский",
		is_equal_approx(_lamp_glow.emission_energy_multiplier, authored_lamp_glow),
		"%.3f, а в .tres %.3f: следующее меню сняло бы «авторское» со вспышки" % [
			_lamp_glow.emission_energy_multiplier, authored_lamp_glow]
	)
	OS.remove_logger(_engine_errors)
	_finish()


func _spawn(prepare: Callable = Callable()) -> Node3D:
	var menu: Node3D = MENU.instantiate()
	if prepare.is_valid():
		prepare.call(menu)
	add_child(menu)
	await get_tree().process_frame
	return menu


# --- 1. Грузится и крутится без ошибок -------------------------------------
func _check_loads_clean() -> void:
	var before := _engine_errors.count()
	var menu := await _spawn()
	for i in 90:
		await get_tree().process_frame
	_check(
		"сцена меню грузится и крутится без ошибок движка",
		_engine_errors.count() == before,
		"ошибок: %d, первая — %s" % [_engine_errors.count() - before, _engine_errors.first()]
	)
	_check(
		"камера сцены — текущая",
		menu.get_viewport().get_camera_3d() == menu.get_node("Camera3D"),
		"текущая камера — %s" % menu.get_viewport().get_camera_3d()
	)
	var env := menu.get_node("WorldEnvironment")
	_check("окружение — LevelEnvironment", env is LevelEnvironment, "окружение мимо настроек графики")
	menu.queue_free()
	await get_tree().process_frame


# --- 2. Свечение колбы плавает на 10–15 % ---------------------------------
func _check_glow() -> void:
	var menu := await _spawn()
	var light: Light3D = menu.get_node("Incubator/Glow")
	var base: float = menu._glow_energy
	var lo := INF
	var hi := -INF
	menu.set_process(false)
	for i in 2400:
		menu._process(0.05)
		lo = minf(lo, light.light_energy / base)
		hi = maxf(hi, light.light_energy / base)
	_check(
		"свечение колбы не выходит за ±15 %",
		lo >= 0.85 - 0.001 and hi <= 1.15 + 0.001,
		"от %.3f до %.3f авторского" % [lo, hi]
	)
	_check(
		"свечение колбы не постоянно — гуляет хотя бы на 10 %",
		hi - lo >= 0.1,
		"размах %.3f" % (hi - lo)
	)
	menu.queue_free()
	await get_tree().process_frame


# --- 3. Лампа мигает сериями со случайными паузами --------------------------
func _check_flicker() -> void:
	var menu := await _spawn()
	var lamp: Light3D = menu.get_node("FluorescentLamp/Light")
	var step := 1.0 / 60.0
	var lit_time := 0.0
	var flashes := 0
	var was_lit := false
	var dark_since := 0.0
	var pauses: Array[float] = []
	menu.set_process(false)
	for i in 90 * 60:
		menu._process(step)
		var t := (i + 1) * step
		var lit := lamp.light_energy > 0.0
		if lit:
			lit_time += step
		if lit and not was_lit:
			flashes += 1
			if t - dark_since > 1.0:
				pauses.append(snappedf(t - dark_since, 0.05))
		if was_lit and not lit:
			dark_since = t
		was_lit = lit
	_check(
		"лампа больше мертва, чем горит, но горит",
		lit_time > 0.0 and lit_time < 90.0 * 0.5,
		"горела %.1f с из 90" % lit_time
	)
	_check(
		"вспышек больше, чем пауз, — лампа мигает сериями",
		pauses.size() >= 3 and flashes > pauses.size() * 1.5,
		"вспышек %d, пауз дольше секунды %d" % [flashes, pauses.size()]
	)
	var distinct := {}
	for pause in pauses:
		distinct[pause] = true
	_check(
		"паузы между сериями разные — не метроном",
		distinct.size() >= mini(3, pauses.size()),
		"паузы: %s" % [pauses]
	)
	menu.queue_free()
	await get_tree().process_frame


# --- 4. Без стекла и меток — запасная колба, мозг и пузырьки внутри неё ------
func _check_fallback_flask() -> void:
	var menu := await _spawn()
	var fog: FogVolume = menu.get_node("Incubator/GlowFog")
	var specimen: Node3D = menu.get_node("Incubator/Specimen")
	var bubbles: GPUParticles3D = menu.get_node("Incubator/Bubbles")
	_check(
		"туман колбы — цилиндр",
		fog.shape == RenderingServer.FOG_VOLUME_SHAPE_CYLINDER,
		"форма %d" % fog.shape
	)
	_check(
		"мозг внутри тумана колбы",
		_inside_cylinder(specimen.position, fog),
		"мозг %s, туман %s размером %s" % [specimen.position, fog.position, fog.size]
	)
	_check(
		"пузырьки рождаются внутри колбы и ниже мозга",
		_inside_cylinder(bubbles.position, fog, 0.05) and bubbles.position.y < specimen.position.y,
		"пузырьки %s, мозг %s" % [bubbles.position, specimen.position]
	)
	var radius: float = (bubbles.process_material as ParticleProcessMaterial).emission_ring_radius
	_check(
		"кольцо пузырьков уже колбы",
		radius > 0.0 and radius < fog.size.x * 0.5,
		"кольцо %.2f, радиус тумана %.2f" % [radius, fog.size.x * 0.5]
	)
	var decals := menu.get_node("Lab/Blood").find_children("*", "Decal", true, false)
	var bare := decals.filter(func(d: Decal) -> bool: return d.texture_albedo == null)
	_check(
		"у каждой декали крови есть текстура (заглушка, пока нет атласа)",
		not decals.is_empty() and bare.is_empty(),
		"декалей %d, без текстуры %d" % [decals.size(), bare.size()]
	)
	var unmarked := []
	for node_name in ["Hound", "ScientistEaten", "ScientistCurled", "ScientistCrawled"]:
		if not menu.get_node("Lab/" + node_name).has_meta(&"menu_action"):
			unmarked.append(node_name)
	_check(
		"у собаки и учёных есть метка действия",
		unmarked.is_empty(),
		"без метки menu_action: %s" % [unmarked]
	)
	menu.queue_free()
	await get_tree().process_frame


# --- 5. Пришедшая модель: стекло, метки, атлас, анимация — без правки сцены --
func _check_model_contract() -> void:
	var anchor_at := Vector3(0.1, 2.6, -0.05)
	var source_at := Vector3(0.0, 1.7, 0.0)
	var glass_center := Vector3(0.0, 2.5, 0.0)
	var atlas := ImageTexture.create_from_image(Image.create_empty(4, 4, false, Image.FORMAT_RGBA8))
	var menu := await _spawn(func(m: Node3D) -> void:
		var model: Node3D = m.get_node("Incubator/Model")
		var glass := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 2.0
		glass.mesh = cylinder
		glass.material_override = GLASS
		glass.position = glass_center
		model.add_child(glass)
		for marker in [[MENU_SCRIPT.BODY_ANCHOR, anchor_at], [MENU_SCRIPT.BUBBLE_SOURCE, source_at]]:
			var node := Node3D.new()
			node.name = marker[0]
			node.position = marker[1]
			model.add_child(node)
		var decal := Decal.new()
		decal.name = "FromAtlas"
		decal.texture_albedo = atlas
		m.get_node("Lab/Blood").add_child(decal)
		var player := AnimationPlayer.new()
		var library := AnimationLibrary.new()
		var eat := Animation.new()
		eat.length = 1.0
		library.add_animation(&"eat", eat)
		player.add_animation_library(&"", library)
		m.get_node("Lab/Hound").add_child(player))

	var fog: FogVolume = menu.get_node("Incubator/GlowFog")
	_check(
		"туман колбы берёт объём у стекла модели",
		fog.position.is_equal_approx(glass_center) and absf(fog.size.x - 1.0 * MENU_SCRIPT.FLASK_INSET) < 0.02 \
				and absf(fog.size.y - 2.0 * MENU_SCRIPT.FLASK_INSET) < 0.02,
		"туман %s размером %s, стекло r 0.5 h 2 в %s" % [fog.position, fog.size, glass_center]
	)
	var specimen: Node3D = menu.get_node("Incubator/Specimen")
	_check(
		"мозг встаёт на метку BodyAnchor",
		specimen.position.distance_to(anchor_at) < 0.05,
		"мозг %s, метка %s" % [specimen.position, anchor_at]
	)
	var bubbles: Node3D = menu.get_node("Incubator/Bubbles")
	_check(
		"пузырьки идут от метки BubbleSource",
		bubbles.position.is_equal_approx(source_at),
		"пузырьки %s, метка %s" % [bubbles.position, source_at]
	)
	_check(
		"декаль с текстурой атласа заглушка не трогает",
		(menu.get_node("Lab/Blood/FromAtlas") as Decal).texture_albedo == atlas,
		"текстура подменена заглушкой"
	)
	var player: AnimationPlayer = menu.get_node("Lab/Hound").find_children("*", "AnimationPlayer", true, false)[0]
	_check(
		"модель с анимацией из метки играет её сама",
		player.is_playing() and player.current_animation == &"eat",
		"играет «%s»" % player.current_animation
	)
	menu.queue_free()
	await get_tree().process_frame


static func _inside_cylinder(point: Vector3, fog: FogVolume, margin: float = 0.0) -> bool:
	var local := point - fog.position
	var radius := fog.size.x * 0.5 + margin
	var half := fog.size.y * 0.5 + margin
	return Vector2(local.x, local.z).length() <= radius and absf(local.y) <= half
