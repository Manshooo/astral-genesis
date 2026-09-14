extends Node
## Проверка физической формы захваченного тела (C_BodyForm / O_BodyForm):
## контракт сцен тел, перенос габарита и уровня глаз на риг, посадка без
## проваливания, откат к призрачной форме и отказ, когда тело не помещается.
## Запускать: godot --headless dev/body_form_check.tscn
##
## Берём НАСТОЯЩИЙ e_player.tscn, а не заглушку-Entity: механизм правит узлы рига
## (CollisionShape3D и Camera3D) и читает его collision_mask — на заглушке всё это
## отсутствует, и проверка проходила бы, ничего не проверяя.

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const BODY_SCENE := "res://src/entities/body/e_body.tscn"
## Тело другой высоты — им проверяется пересадка из тела в тело.
const CRAWLER_SCENE := "res://src/entities/body/e_body_crawler.tscn"

var _ok := 0
var _fail := 0


func _ready() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world

	var snatch := S_BodySnatch.new()
	snatch.group = "physics"
	world.add_system(snatch)
	world.add_observer(O_ExpelFromBody.new())
	# Порядок регистрации — как в world.tscn: облик раньше габарита. Он не должен
	# ни на что влиять, и проверка ниже как раз про это.
	world.add_observer(O_BodyVisual.new())
	world.add_observer(O_BodyForm.new())

	await _run(world)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _run(world: World) -> void:
	# --- 1. Контракт сцен тел -----------------------------------------------
	# Арт-пасс уже один раз снёс обвязку со всех трёх сцен, и захват молча
	# перестал срабатывать вообще: луч бьёт по слою enemies, а корень должен быть
	# E_Body, иначе RunManager не пометит тело съеденным и оно возродится.
	for path in _body_scenes():
		var probe := (load(path) as PackedScene).instantiate()
		var name := path.get_file()
		_check("%s: корень — E_Body" % name, probe is E_Body, probe.get_class())
		var collider := probe as CollisionObject3D
		_check(
			"%s: корень на слое enemies" % name,
			collider != null and (collider.collision_layer & 4) != 0,
			str(collider.collision_layer) if collider else "не CollisionObject3D"
		)
		var form := E_Body.form_of(probe)
		_check("%s: несёт габарит" % name, form != null and form.shape != null, str(form))
		_check(
			"%s: несёт уровень глаз" % name,
			form != null and form.eye_height > 0.0,
			str(form.eye_height) if form else "нет формы"
		)
		# Подошва облика и подошва габарита обязаны совпасть: иначе надетый меш
		# всплывает над полом, и глаза игрока оказываются на уровне таза
		# собственной модели (см. C_BodyVisual.foot_offset).
		var visual := E_Body.visual_of(probe)
		_check(
			"%s: облик знает свою подошву" % name,
			visual != null and form != null and visual.foot_offset.is_equal_approx(form.foot_offset()),
			"%s против %s" % [visual.foot_offset if visual else "нет облика", form.foot_offset() if form else "нет формы"]
		)
		# Экспорт из Blender разворачивает модель лицом в +Z, а Godot смотрит в
		# −Z: тело, авторенное лицом назад, при вселении смотрит игроку в спину.
		# Признак разворота — минус на диагонали Z у трансформа меша.
		_check(
			"%s: модель смотрит в −Z" % name,
			visual != null and visual.mesh_transform.basis.z.z < 0.0 or _faceless(path),
			str(visual.mesh_transform.basis.z) if visual else "нет облика"
		)
		probe.free()

	# --- 2. Захват надевает форму -------------------------------------------
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame

	var collision := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	var ghost_shape := collision.shape
	var ghost_camera := camera.transform
	var ghost_lift := player.foot_offset().y

	# Entity наследует Node, поэтому до Node3D — через двойной каст, как в
	# S_BodySnatch._embody.
	var body := (load(BODY_SCENE) as PackedScene).instantiate() as Entity
	(body as Node as Node3D).position = Vector3(3.0, 0.0, 0.0)
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	await get_tree().physics_frame

	var bs := player.get_component(C_BodySnatch) as C_BodySnatch
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame

	_check("захват состоялся", player.has_component(C_Embodied), "")
	_check(
		"ригу надет габарит тела (капсула 1.8)",
		collision.shape is CapsuleShape3D and is_equal_approx((collision.shape as CapsuleShape3D).height, 1.8),
		str(collision.shape)
	)
	_check("габарит изменился", collision.shape != ghost_shape, "")
	# Маркер Eyes стоит на 1.7 над подошвой, origin рига — в центре капсулы (0.9).
	_check(
		"камера села на уровень глаз (1.7 − 0.9 = 0.8)",
		is_equal_approx(camera.transform.origin.y, 0.8),
		str(camera.transform.origin.y)
	)
	# Подошва рига должна оказаться там же, где подошва тела, — на полу комнаты.
	_check(
		"риг сел подошвами на место тела, а не по пояс в пол",
		is_equal_approx(player.global_position.y, 0.9),
		"%.3f (призрачный офсет был %.3f)" % [player.global_position.y, ghost_lift]
	)
	_check(
		"foot_offset пересчитался по надетой капсуле",
		is_equal_approx(player.foot_offset().y, 0.9),
		str(player.foot_offset().y)
	)
	# Меш обязан сесть подошвами на пол вместе с ригом. Наблюдатели облика и
	# габарита сидят на разных компонентах, и O_BodyVisual когда-то спрашивал
	# офсет у рига — тот отвечал габаритом, который ещё носит (призрачная сфера
	# 0.26 при первом захвате), и меш всплывал на разницу.
	# Ждём авторский трансформ меша МИНУС подошву надетого тела: у капсулы-заглушки
	# меш авторен по центру (0.9), у моделей — от ступней, и правило одно на всех.
	var geo := RS_EntityVisuals.primary(player) as MeshInstance3D
	var body_visual := E_Body.visual_of_scene(BODY_SCENE)
	_check(
		"меш надетого тела сел подошвами к полу",
		is_equal_approx(geo.transform.origin.y, body_visual.mesh_transform.origin.y - 0.9),
		"%.3f вместо %.3f (призрачный офсет был %.3f)"
		% [geo.transform.origin.y, body_visual.mesh_transform.origin.y - 0.9, ghost_lift]
	)

	# --- 3. Развоплощение возвращает призрачную форму -----------------------
	O_ExpelFromBody.expel(player, true)
	await get_tree().process_frame
	_check("габарит вернулся призрачный", collision.shape == ghost_shape, str(collision.shape))
	_check(
		"камера вернулась призрачная",
		camera.transform.is_equal_approx(ghost_camera),
		str(camera.transform.origin)
	)

	# --- 4. Отказ, когда тело не помещается ---------------------------------
	# Капсула рослого тела не должна молча вырасти в низком проходе: захват —
	# осознанное действие, и застрять в геометрии хуже, чем получить отказ.
	var wall := _blocker(Vector3(-3.0, 0.9, 0.0))
	add_child(wall)
	# Entity наследует Node, поэтому до Node3D — через двойной каст, как в
	# S_BodySnatch._embody.
	var body2 := (load(BODY_SCENE) as PackedScene).instantiate() as Entity
	(body2 as Node as Node3D).position = Vector3(-3.0, 0.0, 0.0)
	world.add_entity(body2)
	body2.add_component(C_SnatchTargeted.new())
	await get_tree().physics_frame
	await get_tree().physics_frame

	bs.capture_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame

	_check("захват в занятое место отклонён", not player.has_component(C_Embodied), "")
	_check("тело осталось в мире", is_instance_valid(body2), "")
	var message := player.get_component(C_ScreenMessage) as C_ScreenMessage
	_check("игроку объяснили отказ", message != null and not message.text.is_empty(), str(message))

	# Убираем препятствие — тот же захват обязан пройти.
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	bs.capture_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame
	_check("без препятствия тот же захват проходит", player.has_component(C_Embodied), "")

	# --- 5. Пересадка тело→тело --------------------------------------------
	# Второй способ уронить меш: спросить офсет у рига, который носит ПРОШЛОЕ
	# тело. Ростовое тело поверх ростового разницы не даст, поэтому пересаживаем
	# в тело другой высоты — ползуна (капсула 0.86, подошва 0.43).
	var crawler := (load(CRAWLER_SCENE) as PackedScene).instantiate() as Entity
	(crawler as Node as Node3D).position = Vector3(-3.0, 0.0, 6.0)
	world.add_entity(crawler)
	crawler.add_component(C_SnatchTargeted.new())
	await get_tree().physics_frame
	await get_tree().physics_frame

	var crawler_form := E_Body.form_of(crawler)
	var crawler_visual := E_Body.visual_of(crawler)
	bs.capture_requested = true
	ECS.process(0.016, "physics")
	await get_tree().process_frame

	_check("пересадка состоялась", player.has_component(C_Embodied), "")
	_check(
		"после пересадки риг сел по НОВОМУ габариту",
		is_equal_approx(player.foot_offset().y, crawler_form.foot_offset().y),
		"%.3f против %.3f" % [player.foot_offset().y, crawler_form.foot_offset().y]
	)
	_check(
		"после пересадки меш сел подошвами к полу, а не по офсету прошлого тела",
		is_equal_approx(
			geo.transform.origin.y,
			crawler_visual.mesh_transform.origin.y - crawler_form.foot_offset().y
		),
		"%.3f (офсет прошлого тела был %.3f)" % [geo.transform.origin.y, 0.9]
	)
	_check(
		"после пересадки камера села на уровень глаз нового тела",
		is_equal_approx(
			camera.transform.origin.y, crawler_form.eye_height - crawler_form.foot_offset().y
		),
		str(camera.transform.origin.y)
	)

	# --- 6. Реальная геометрия комнаты: подошва впритык к полу — не теснота -
	# _fits() кастует капсулу ровно на подошву тела (form.foot_offset()) — то
	# же место, где тело и стоит. В комнатных шаблонах тело расставлено штатно
	# на y=0 (соглашение E_Body — «подошва тела на y=0»), пол комнаты тоже на
	# y=0, и без зазора капсула касалась пола РОВНО в нуле — intersect_shape
	# против пол-трисетки (ConcavePolygonShape3D) засчитывал касание как
	# пересечение. Живой прогон поймал это как «Тело здесь не поместится» на
	# КАЖДОМ теле в КАЖДОЙ заспавненной комнате — и не поймал в хабе только
	# потому, что тела там случайно оказались приподняты над локальным полом.
	# Синтетический блокер из §4 этого не ловит — там нет пола вовсе, только
	# коробка-препятствие в воздухе. Проверять надо на настоящей геометрии.
	for entry in [
		["res://src/levels/procedural/rooms/default/default_room.tscn", "BodyHound"],
		["res://src/levels/procedural/rooms/exit/exit_room.tscn", "BodyCrawler"],
		["res://src/levels/procedural/rooms/lab/lab_room.tscn", "BodyWalker"],
	]:
		var room_path: String = entry[0]
		var body_name: String = entry[1]
		var room := (load(room_path) as PackedScene).instantiate()
		add_child(room)
		await get_tree().physics_frame
		await get_tree().physics_frame

		var room_body := room.find_child(body_name, true, false) as Entity
		var room_form := E_Body.form_of(room_body)
		var fits: bool = S_BodySnatch._fits(player, room_body, room_form)
		_check(
			"%s: %s на штатном месте влезает (пол не считается теснотой)"
			% [room_path.get_file(), body_name],
			fits,
			"тело на %s" % (room_body as Node as Node3D).global_position
		)
		room.queue_free()
		await get_tree().process_frame

	# Зазор не должен занизить чувствительность проверки везде подряд — тесное
	# место обязано остаться тесным. §4 выше это уже проверяет (блокер 1.5×1.5×1.5
	# м, зазор всего 0.05 м — с большим запасом всё ещё «не помещается»), здесь
	# отдельно не дублируем.


## Статическое препятствие вокруг точки: коробка на слое 1, куда смотрит маска
## игрока по умолчанию.
func _blocker(at: Vector3) -> StaticBody3D:
	var node := StaticBody3D.new()
	node.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 1.5, 1.5)
	shape.shape = box
	node.add_child(shape)
	return node


func _body_scenes() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://src/entities/body")
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			out.append("res://src/entities/body/" + file)
	return out


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])


## Тела-заглушки (капсула без модели) лицом никуда не смотрят — разворачивать
## нечего, и требовать от них минуса на диагонали бессмысленно.
func _faceless(path: String) -> bool:
	return path.ends_with("/e_body.tscn")
