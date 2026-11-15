extends "res://dev/check_harness.gd"
## Проверка обликов тела (C_Look): шесть материалов и двое очков учёного разыгрываются по месту и едут с телом.
## Запуск: godot --headless dev/body_look_check.tscn
##
## Инвариант тихий: облик, разыгранный не по месту, меняется при пересборке слоя, а облик, не доехавший до рига,
## трупа или сейва, переодевает учёного у игрока на глазах. Ни то, ни другое ошибки не бросает.

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const SCIENTIST_BODY := "res://src/entities/body/e_body_scientist.tscn"
const SCIENTIST_ENEMY := "res://src/entities/enemy/e_enemy_scientist.tscn"
const GLASSES: Array[String] = ["scientist_glasses_round", "scientist_glasses_rect"]

var _world: World
var _room: Node3D


func _ready() -> void:
	_world = _new_world()
	_add_systems(_world, "physics", [S_BodySnatch.new(), S_Gravity.new(), S_Movement.new()])
	_add_systems(_world, "gameplay", [S_Health.new()])
	_world.add_observer(O_ExpelFromBody.new())
	_world.add_observer(O_EnemyDeath.new())
	_world.add_observer(O_BodyVisual.new())
	_world.add_observer(O_BodyForm.new())
	_world.add_observer(O_SoulTraits.new())
	_room = Node3D.new()
	add_child(_room)
	_add_floor()

	_check_roll()
	await _check_capture()
	await _check_corpse()
	_check_save()
	_finish()


# --- 1. Розыгрыш по месту ------------------------------------------------------------
func _check_roll() -> void:
	var look := _scene_look(SCIENTIST_BODY)
	_check("у учёного шесть обликов и двое очков",
		look != null and look.materials.size() == 6 and look.alternatives.size() == 2, "")
	if look == null:
		return
	var a := look.duplicate() as C_Look
	var b := look.duplicate() as C_Look
	RS_EntityVisuals.roll_look(a, [7, &"lab_0/Body"])
	RS_EntityVisuals.roll_look(b, [7, &"lab_0/Body"])
	_check("тот же сид и место — тот же облик",
		a.material_index == b.material_index and a.alternative_index == b.alternative_index, "")

	var seen := {}
	var glasses := {}
	for i in 60:
		var c := look.duplicate() as C_Look
		RS_EntityVisuals.roll_look(c, [i, &"lab_0/Body"])
		seen[c.material_index] = true
		glasses[c.alternative_index] = true
	_check("разные сиды дают разные облики и очки", seen.size() >= 4 and glasses.size() == 2,
		"обликов %d, очков %d" % [seen.size(), glasses.size()])

	var before := randi()
	seed(1)
	var expected := randi()
	seed(1)
	RS_EntityVisuals.roll_look(look.duplicate() as C_Look, [3, &"x"])
	_check("розыгрыш не трогает глобальный ГСЧ", randi() == expected, "")
	seed(before)


# --- 2. Тело на месте и захват --------------------------------------------------------
func _check_capture() -> void:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	_world.add_entity(player)
	(player as Node as Node3D).global_position = Vector3(0.0, 1.0, 0.0)
	await _physics(3)

	var body := (load(SCIENTIST_BODY) as PackedScene).instantiate() as Entity
	_room.add_child(body)
	(body as Node as Node3D).global_position = Vector3(0.0, 0.0, -1.5)
	_world.add_entity(body)
	var look := body.get_component(C_Look) as C_Look
	look.material_index = 4
	look.alternative_index = 1
	RS_EntityVisuals.dress_actor(body, null)
	var visual := body.get_node("Visual")
	var wanted := look.materials[4]
	_check("облик тела — материал на всей геометрии, растворение вблизи сохранено",
		_all_wear(visual, wanted), "")
	_check("у тела виден ровно второй вариант очков", _shown_glasses(visual) == [GLASSES[1]], str(_shown_glasses(visual)))

	body.add_component(C_SnatchTargeted.new())
	var snatch := player.get_component(C_BodySnatch) as C_BodySnatch
	snatch.capture_success_chance = 1.0
	snatch.capture_requested = true
	await _physics(2)
	await get_tree().process_frame
	await _physics(2)
	var worn := player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE))
	var soul_look := player.get_component(C_Look) as C_Look
	_check("номера облика уехали на душу",
		soul_look != null and soul_look.material_index == 4 and soul_look.alternative_index == 1, "")
	_check("на риге тот же облик", worn != null and _all_wear(worn, wanted), "")
	_check("на риге те же очки", worn != null and _shown_glasses(worn) == [GLASSES[1]],
		str(_shown_glasses(worn)) if worn else "облика нет")

	# Сейв: контрольная точка во плоти, выход, восстановление воплощения тем же путём, что загрузка. persist=false —
	# только память, файл игрока не трогается.
	RunManager._checkpoint(&"body_look_check", false)
	_check("контрольная точка записала облик надетого тела", WorldSave.save.body_look == Vector2i(4, 1),
		str(WorldSave.save.body_look))
	O_ExpelFromBody.expel(player, false)
	await _physics(3)
	RunManager._restore_embodiment(player, WorldSave.save)
	await _physics(2)
	var restored := player.get_node_or_null(NodePath(O_BodyVisual.WORN_NODE))
	var restored_look := player.get_component(C_Look) as C_Look
	_check("после загрузки душа носит те же номера облика",
		restored_look != null and restored_look.material_index == 4 and restored_look.alternative_index == 1, "")
	_check("после загрузки на риге тот же облик и очки",
		restored != null and _all_wear(restored, wanted) and _shown_glasses(restored) == [GLASSES[1]],
		str(_shown_glasses(restored)) if restored else "облика нет")

	O_ExpelFromBody.expel(player, false)
	await _physics(3)
	_check("призраком в сейв уходит «облика нет»", _checkpoint_look() == Vector2i(-1, -1), "")


# --- 3. Труп врага — тот же человек ---------------------------------------------------
func _check_corpse() -> void:
	var enemy := (load(SCIENTIST_ENEMY) as PackedScene).instantiate() as Entity
	_room.add_child(enemy)
	(enemy as Node as Node3D).global_position = Vector3(3.0, 0.05, 0.0)
	_world.add_entity(enemy)
	(enemy.get_component(C_EnemyAI) as C_EnemyAI).aggro_range = 0.0
	RS_EntityVisuals.dress_actor(enemy, [11, &"lab_2/EnemySpawn1"])
	var look := enemy.get_component(C_Look) as C_Look
	var material := look.material_index
	var glasses := look.alternative_index
	_check("враг на месте разыгран", look.is_rolled(), "")

	O_EnemyDeath.replace_with_corpse(enemy)
	await _physics(2)
	var corpse: Entity = null
	for node in _room.get_children():
		if node is E_Body:
			corpse = node as Entity
	var corpse_look := corpse.get_component(C_Look) as C_Look if corpse else null
	_check("труп врага носит его облик, а не новый бросок",
		corpse_look != null and corpse_look.material_index == material and corpse_look.alternative_index == glasses,
		"враг %d/%d, труп %s" % [material, glasses,
			"%d/%d" % [corpse_look.material_index, corpse_look.alternative_index] if corpse_look else "—"])
	if corpse_look != null:
		var visual := corpse.get_node("Visual")
		_check("на трупе тот же материал и очки",
			_all_wear(visual, look.materials[material]) and _shown_glasses(visual) == [GLASSES[glasses]], "")


# --- 4. Сейв: облик из номеров, а не из сцены -----------------------------------------
func _check_save() -> void:
	var look := _scene_look(SCIENTIST_BODY)
	look.material_index = 2
	look.alternative_index = 1
	var visual := E_Body.visual_of_scene(SCIENTIST_BODY, look)
	var probe := visual.scene.instantiate()
	var dressed := true
	for geo in probe.find_children("*", "GeometryInstance3D", true, false):
		dressed = dressed and visual.material_overrides.get(geo.name) == look.materials[2]
	probe.free()
	_check("облик из сейва: материал номера на всей геометрии", dressed, str(visual.material_overrides.keys()))
	_check("облик из сейва: спрятан непоказанный вариант очков", Array(visual.hidden_meshes) == [GLASSES[0]],
		str(visual.hidden_meshes))
	var plain := E_Body.visual_of_scene(SCIENTIST_BODY)
	_check("без номеров — облик сцены", plain.material_overrides.is_empty() and Array(plain.hidden_meshes) == [GLASSES[1]],
		"%s %s" % [plain.material_overrides.keys(), plain.hidden_meshes])


func _checkpoint_look() -> Vector2i:
	RunManager._checkpoint(&"body_look_check", false)
	return WorldSave.save.body_look


func _scene_look(path: String) -> C_Look:
	for component in E_Body.traits_of_scene(path):
		if component is C_Look:
			return component as C_Look
	return null


## Вся геометрия носит [param material] — сам или копию с растворением вблизи камеры (копия сохраняет текстуру).
func _all_wear(appearance: Node, material: Material) -> bool:
	var geometry := appearance.find_children("*", "GeometryInstance3D", true, false)
	if geometry.is_empty():
		return false
	var albedo := (material as BaseMaterial3D).albedo_texture
	for geo in geometry:
		var worn := (geo as GeometryInstance3D).material_override as BaseMaterial3D
		if worn == null or worn.albedo_texture != albedo:
			return false
	return true


func _shown_glasses(appearance: Node) -> Array:
	var shown := []
	for name in GLASSES:
		var node := appearance.find_child(name, true, false) as Node3D
		if node != null and node.visible:
			shown.append(name)
	return shown


func _add_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)


func _on_physics_tick(delta: float) -> void:
	ECS.process(delta, "physics")
	ECS.process(delta, "gameplay")
