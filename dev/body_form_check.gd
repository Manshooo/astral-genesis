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
