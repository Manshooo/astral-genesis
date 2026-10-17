extends "res://dev/check_harness.gd"
## Проверка ростера врагов по слоям и существа L5 (карточка «Игровой цикл — от и
## до», §2 и §10 П0 п. 1/5): маркеры спавна в комнатах, бросок по сиду, состав по
## глубинам, сопротивление L5.
##
## Ломается всё это тихо: ростер, отдающий не тех врагов, бросок, зависящий от
## общего ГСЧ, маркер внутри стены или множитель урона не в ту сторону ничем не
## бросают ошибку — игра просто становится другой. Поэтому проверяется поведение:
## тот же слой даёт тех же врагов на тех же местах, на каждой глубине встаёт тот,
## кто положен по карточке, удар слабого тела по L5 слабеет, а удар другого L5 —
## нет, и маркер стоит на полу, а не в стене.
##
## Настоящий RunManager: слой собирается стримером, как в игре. Сейв разработчика
## снимается и возвращается (mark_body_consumed и контрольные точки пишут в
## user://).
## Запускать: godot --headless dev/enemy_roster_check.tscn

const RUN_SEED := 424242
const HOUND_ENEMY := "res://src/entities/enemy/e_enemy_hound.tscn"
const SCIENTIST_ENEMY := "res://src/entities/enemy/e_enemy_scientist.tscn"
const SOLDIER_ENEMY := "res://src/entities/enemy/e_enemy_soldier.tscn"
const L5_ENEMY := "res://src/entities/enemy/e_enemy_l5.tscn"
const L5_BODY := "res://src/entities/body/e_body_l5.tscn"
const HOUND_BODY := "res://src/entities/body/e_body_hound.tscn"
const SOLDIER_BODY := "res://src/entities/body/e_body_soldier.tscn"

## Сколько бросков на глубину для проверки состава: хватает, чтобы выпала каждая
## строка самого узкого слоя при любых разумных весах.
const SAMPLES := 600

## Комнаты, где маркеров быть НЕ должно — решение, а не умолчание: в выходе
## финал, в Архитекторе безопасная встреча, на лестнице враги падали бы с
## пролёта.
const NO_ENEMY_ROOMS: Array[String] = [
	"res://src/levels/procedural/rooms/exit/exit_room.tscn",
	"res://src/levels/procedural/rooms/architect/architect_room.tscn",
	"res://src/levels/procedural/rooms/stairs/stairs_2x2x2.tscn",
]

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _roster: RS_EnemyRoster


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save
	_roster = RS_EnemyRoster.current()

	var world := _new_world()
	_add_systems(world, "gameplay", [S_Health.new()])
	world.add_observer(O_EnemyDeath.new())

	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	_check_roster_data()
	_check_roster_composition()
	_check_roll_determinism()
	_check_l5_resistance()
	_check_l5_binding()

	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	await get_tree().physics_frame

	await _check_layers()
	await _check_death_and_memory()
	await _check_markers_on_floor()

	RunManager._end_run()
	_restore()
	_finish()


# --- Данные и состав ----------------------------------------------------------


func _check_roster_data() -> void:
	var problems := _roster.validate(RS_LevelGraph.DEPTHS)
	_check("ростер валиден: на каждом слое есть строка, данные в границах", problems.is_empty(), "; ".join(problems))
	_check("ростер лежит там, где его читает игра", RS_EnemyRoster.current() == _roster and not _roster.entries.is_empty(), "")


## Кто встаёт на каком слое — таблица карточки §2 и решения по L2: учёные и
## охрана (военные). Множества, а не веса: веса тюнятся, состав — нет.
func _check_roster_composition() -> void:
	var expected := {
		0: [SCIENTIST_ENEMY],
		1: [SCIENTIST_ENEMY],
		2: [SCIENTIST_ENEMY, SOLDIER_ENEMY],
		3: [SOLDIER_ENEMY],
		4: [SOLDIER_ENEMY, HOUND_ENEMY],
		5: [L5_ENEMY],
	}
	for depth: int in RS_LevelGraph.DEPTHS:
		var seen := {}
		var empty := 0
		for i in SAMPLES:
			var scene := _roster.roll(RUN_SEED, depth, &"node_%d" % i, &"EnemySpawn1")
			if scene == null:
				empty += 1
			else:
				seen[scene.resource_path] = true
		var want: Array = expected[depth]
		var got: Array = seen.keys()
		got.sort()
		want.sort()
		_check("L%d: ростер отдаёт ровно положенных врагов" % depth, got == want, "получено %s" % [got])
		# Пустой маркер — часть замысла (враги не на каждом шагу), но не весь слой.
		var share := float(empty) / SAMPLES
		_check("L%d: часть маркеров пуста, но не все (%.2f)" % [depth, share],
			share > 0.0 and share < 1.0, "пустых %.2f" % share)


## Бросок — функция входа: тот же вход даёт тот же ответ, другой сид — другую
## раскладку, а общий ГСЧ не трогается.
func _check_roll_determinism() -> void:
	var same := true
	var differs := false
	for i in 200:
		var node := StringName("room_%d" % i)
		var a := _roster.roll(RUN_SEED, 4, node, &"EnemySpawn2")
		var b := _roster.roll(RUN_SEED, 4, node, &"EnemySpawn2")
		same = same and a == b
		differs = differs or _roster.roll(RUN_SEED + 1, 4, node, &"EnemySpawn2") != a
	_check("бросок на маркер детерминирован", same, "")
	_check("другой сид забега даёт другую раскладку", differs, "")

	# Общий ГСЧ не сдвигается: сид глобального генератора после бросков тот же,
	# что и без них. Иначе бросок мешал бы всему, что разыгрывается позже.
	seed(77)
	var control := randi()
	seed(77)
	for i in 50:
		_roster.roll(RUN_SEED, 3, &"x_%d" % i, &"EnemySpawn1")
	_check("бросок не трогает глобальный ГСЧ", randi() == control, "")


# --- Существо L5 ---------------------------------------------------------------


func _check_l5_binding() -> void:
	var body := (load(L5_BODY) as PackedScene).instantiate() as E_Body
	_check("труп существа L5 — тело класса 5", body != null and body.body_class == 5, "")
	_check("класс трупа читается и по пути сцены (как при захвате)", E_Body.class_of_scene(L5_BODY) == 5, "")
	body.free()

	var enemy := (load(L5_ENEMY) as PackedScene).instantiate() as E_Enemy
	_check("враг L5 оставляет труп L5", enemy.corpse_scene != null and enemy.corpse_scene.resource_path == L5_BODY, "")
	_check("класс угрозы врага L5 — 5", enemy.threat_class() == 5, "%d" % enemy.threat_class())
	var hound := (load(HOUND_ENEMY) as PackedScene).instantiate() as E_Enemy
	_check("класс угрозы гончей — класс её трупа, не 5", hound.threat_class() == E_Body.class_of_scene(HOUND_BODY), "")

	# «Увеличенная гончая, сильнее по числам» — отношения, не значения.
	var enemy_hp := (enemy.component_resources.filter(func(c): return c is C_Health)[0] as C_Health).maximum
	var hound_hp := (hound.component_resources.filter(func(c): return c is C_Health)[0] as C_Health).maximum
	var enemy_ai := enemy.component_resources.filter(func(c): return c is C_EnemyAI)[0] as C_EnemyAI
	var hound_ai := hound.component_resources.filter(func(c): return c is C_EnemyAI)[0] as C_EnemyAI
	_check("существо L5 крепче гончей", enemy_hp > hound_hp, "%s против %s" % [enemy_hp, hound_hp])
	_check("существо L5 бьёт больнее гончей", enemy_ai.attack_damage > hound_ai.attack_damage, "")
	enemy.free()
	hound.free()


func _check_l5_resistance() -> void:
	var attack := C_Attack.new()
	attack.damage = 20.0
	var l5 := (load(L5_ENEMY) as PackedScene).instantiate() as E_Enemy
	var hound := (load(HOUND_ENEMY) as PackedScene).instantiate() as E_Enemy

	var in_hound := _embodied_in(HOUND_BODY)
	var in_soldier := _embodied_in(SOLDIER_BODY)
	var in_l5 := _embodied_in(L5_BODY)
	var ghost := Entity.new()
	ECS.world.add_entity(ghost)

	var weak := S_Attack.damage_against(in_hound, l5, attack)
	_check("тело класса ниже L5 бьёт существо L5 в десять раз слабее",
		is_equal_approx(weak, attack.damage * S_Attack.L5_RESISTANCE), "%s" % weak)
	_check("это ослабление, а не неуязвимость", weak > 0.0, "%s" % weak)
	_check("военный (класс 3) тоже слабее против L5",
		S_Attack.damage_against(in_soldier, l5, attack) < attack.damage, "")
	_check("душа вне тела против L5 — как слабое тело",
		is_equal_approx(S_Attack.damage_against(ghost, l5, attack), attack.damage * S_Attack.L5_RESISTANCE), "")
	_check("удар другого L5 по существу L5 — полный урон",
		is_equal_approx(S_Attack.damage_against(in_l5, l5, attack), attack.damage), "")
	_check("не-L5 цель не ослаблена: гончая получает полный урон",
		is_equal_approx(S_Attack.damage_against(in_hound, hound, attack), attack.damage), "")
	_check("множитель — ослабление, а не усиление", S_Attack.L5_RESISTANCE > 0.0 and S_Attack.L5_RESISTANCE < 1.0, "")

	for entity in [in_hound, in_soldier, in_l5, ghost]:
		ECS.world.remove_entity(entity)
	l5.free()
	hound.free()


## Сущность, воплощённая в теле [param body_path] — для damage_against нужен
## только путь сцены, по которому берётся класс.
func _embodied_in(body_path: String) -> Entity:
	var entity := Entity.new()
	ECS.world.add_entity(entity)
	var embodied := C_Embodied.new()
	embodied.body_scene_path = body_path
	entity.add_component(embodied)
	return entity


# --- Слои в мире ---------------------------------------------------------------


## Враги ростера загруженного слоя: id маркера -> путь сцены врага.
func _roster_enemies() -> Dictionary:
	var found := {}
	for spawned: LayerStreamer.SpawnedRoom in RunManager.layer.rooms.values():
		for child in spawned.children:
			if child is E_Enemy and child.has_meta(LayerStreamer.ROSTER_ID_META):
				found[child.get_meta(LayerStreamer.ROSTER_ID_META)] = child.scene_file_path
	return found


func _reload_layer(depth: int) -> void:
	RunManager._despawn_layer()
	RunManager._spawn_layer(depth)
	await get_tree().physics_frame
	await get_tree().physics_frame


## Расстояние по полу: рэгдолл за кадр оседает, и высота не про место.
func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _check_layers() -> void:
	var total := 0
	var wrong_depth: Array[String] = []
	var unstable: Array[String] = []
	var unregistered := 0
	var not_origin := 0
	var l5_seen := 0
	for depth: int in RS_LevelGraph.DEPTHS:
		await _reload_layer(depth)
		var first := _roster_enemies()
		total += first.size()
		var allowed: Array[String] = []
		for entry in _roster.entries_at(depth):
			allowed.append(entry.enemy_scene.resource_path)
		for id: StringName in first:
			if not allowed.has(first[id]):
				wrong_depth.append("L%d %s" % [depth, first[id]])
			l5_seen += 1 if first[id] == L5_ENEMY else 0
		for spawned: LayerStreamer.SpawnedRoom in RunManager.layer.rooms.values():
			for child in spawned.children:
				if child is E_Enemy and child.has_meta(LayerStreamer.ROSTER_ID_META):
					unregistered += 0 if ECS.world.entities.has(child) else 1
					var origin := child.get_component(C_BodyOrigin) as C_BodyOrigin
					not_origin += 0 if origin and origin.body_id == child.get_meta(LayerStreamer.ROSTER_ID_META) else 1

		# Тот же слой, собранный заново, — те же враги на тех же маркерах.
		await _reload_layer(depth)
		if _roster_enemies() != first:
			unstable.append("L%d" % depth)
	_check("маркеры ростера в комнатах дают врагов (%d на всех слоях)" % total, total > 0, "")
	_check("на слое встали только положенные ему враги", wrong_depth.is_empty(), ", ".join(wrong_depth.slice(0, 4)))
	_check("слой, собранный заново, возвращает тех же врагов на те же места", unstable.is_empty(), ", ".join(unstable))
	_check("враги ростера зарегистрированы в мире", unregistered == 0, "%d вне мира" % unregistered)
	_check("враг ростера несёт id своего маркера", not_origin == 0, "%d без C_BodyOrigin" % not_origin)
	print("  (врагов ростера на всех слоях: %d, существ L5: %d)" % [total, l5_seen])
	_check("на дне встают существа L5", l5_seen > 0, "")


## Убитый враг ростера оставляет труп с id маркера; съеденный труп — маркер не
## разыгрывается при новой сборке слоя (единственная память о врагах, что есть).
func _check_death_and_memory() -> void:
	var depth := 4
	await _reload_layer(depth)
	var before := _roster_enemies()
	if before.is_empty():
		_check("на L4 есть враг ростера для проверки смерти", false, "seed %d" % RUN_SEED)
		return

	var victim: E_Enemy = null
	for spawned: LayerStreamer.SpawnedRoom in RunManager.layer.rooms.values():
		for child in spawned.children:
			if victim == null and child is E_Enemy and child.has_meta(LayerStreamer.ROSTER_ID_META):
				victim = child
	var marker_id: StringName = victim.get_meta(LayerStreamer.ROSTER_ID_META)
	var parent := (victim as Node).get_parent()

	# Враг умирает не на маркере: он успел пройти. Место смерти выбрано вдали и от
	# маркера, и от начала координат комнаты — туда уезжал рэгдолл, запущенный до
	# того, как трупу выставили место (см. O_EnemyDeath.replace_with_corpse).
	var victim_node := victim as Node as Node3D
	var room_origin := (parent as Node3D).global_position
	var offset := Vector3(2.0, 0.0, 0.0)
	if _flat(victim_node.global_position + offset - room_origin) < 2.5:
		offset = -offset
	var death_spot := victim_node.global_position + offset
	victim_node.global_position = death_spot

	O_EnemyDeath.replace_with_corpse(victim)
	await get_tree().process_frame
	var corpse: E_Body = null
	for child in parent.get_children():
		if child is E_Body and child.has_component(C_BodyOrigin) \
				and (child.get_component(C_BodyOrigin) as C_BodyOrigin).body_id == marker_id:
			corpse = child
	_check("труп врага ростера наследует id маркера", corpse != null, marker_id)
	if corpse != null:
		# Кости, а не корень: корень встаёт куда велено в любом случае, а лежит
		# труп там, где его кости симуляции.
		var bones := corpse.find_children("*", "PhysicalBone3D", true, false)
		var far: Array[String] = []
		for bone: Node3D in bones:
			if _flat(bone.global_position - death_spot) > 1.5:
				far.append("%s в %.1f м" % [bone.name, _flat(bone.global_position - death_spot)])
		_check("рэгдолл трупа лежит на месте смерти врага, а не на маркере или в начале комнаты",
			not bones.is_empty() and far.is_empty(),
			"костей %d, далеко: %s" % [bones.size(), ", ".join(far.slice(0, 3))])

	# Не съеден — враг вернётся (задокументированный пробел), съеден — нет.
	await _reload_layer(depth)
	_check("убитый, но не съеденный враг возвращается при новой сборке слоя (пробел)",
		_roster_enemies().has(marker_id), "")
	WorldSave.save.consumed_body_ids.append(marker_id)
	await _reload_layer(depth)
	var after := _roster_enemies()
	var expected := before.duplicate()
	expected.erase(marker_id)
	_check("съеденный труп снимает маркер: враг не воскресает", not after.has(marker_id), "")
	_check("остальные маркеры слоя не тронуты", after == expected, "")


# --- Маркеры в сценах ----------------------------------------------------------


## Маркер стоит на полу и над ним есть место для самого большого врага:
## расставляется руками по координатам, и промах — враг в стене или в воздухе —
## тихий. Комнаты берутся из библиотеки пресетов, а не списком в проверке.
func _check_markers_on_floor() -> void:
	var library := GameConfig.config.room_preset_library
	var scenes: Array[PackedScene] = []
	for preset in library.presets:
		if preset.scene != null and not scenes.has(preset.scene):
			scenes.append(preset.scene)

	var rooms: Array[Node3D] = []
	var with_markers := 0
	var offset := 400.0
	for scene in scenes:
		var room := scene.instantiate() as Node3D
		room.position = Vector3(offset, 0.0, 0.0)
		offset += 100.0
		add_child(room)
		rooms.append(room)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().world_3d.direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.8
	var floating: Array[String] = []
	var buried: Array[String] = []
	var forbidden: Array[String] = []
	for i in rooms.size():
		var room := rooms[i]
		var markers := room.find_children("EnemySpawn*", "Marker3D", true, false)
		if not markers.is_empty():
			with_markers += 1
		if NO_ENEMY_ROOMS.has(scenes[i].resource_path) and not markers.is_empty():
			forbidden.append(scenes[i].resource_path)
		for marker: Marker3D in markers:
			var at := marker.global_position
			var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 1.0, 1)
			var hit := space.intersect_ray(ray)
			var label := "%s/%s" % [room.name, marker.name]
			if hit.is_empty() or absf(hit.position.y - at.y) > 0.35:
				floating.append(label)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 1
			query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (1.4 + 0.05))
			if not space.intersect_shape(query, 1).is_empty():
				buried.append(label)
	_check("маркеры стоят в нескольких комнатах (%d)" % with_markers, with_markers >= 3, "")
	_check("маркер стоит на полу, а не в воздухе", floating.is_empty(), ", ".join(floating))
	_check("над маркером есть место для самого крупного врага", buried.is_empty(), ", ".join(buried))
	_check("в выходе, у Архитектора и на лестнице маркеров нет", forbidden.is_empty(), ", ".join(forbidden))
	for room in rooms:
		room.free()


func _restore() -> void:
	WorldSave.save = _save_object
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")
