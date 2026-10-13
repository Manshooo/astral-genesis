extends "res://dev/check_harness.gd"
## Убежище от распада (DecayShelter): зона ставит маркер на настоящего рига
## игрока, пока тот внутри, в убежище запас копится и не убывает, излишек не
## срезается, во плоти доливается карман тела, а вне зоны распад идёт как прежде.
## Запускать: godot --headless dev/decay_shelter_check.tscn

const PLAYER_SCENE := preload("res://src/entities/player/e_player.tscn")
const HUB_SCENE := preload("res://src/levels/hub/hub.tscn")

## Физкадров на то, чтобы Area3D заметила вход или выход, и отложенный вызов
## долетел. Jolt крутится на своём потоке, сигналы приходят с запаздыванием.
const SETTLE_FRAMES := 6
const OUTSIDE := Vector3(100, 1, 100)


func _ready() -> void:
	var world := _new_world()
	_add_systems(world, "gameplay", [S_Lifespan.new(), S_DecayShelter.new()])
	await _run(world)
	_finish()


## Физкадры здесь только двигают физику: gameplay тикаем руками ниже, ровно на
## столько, на сколько нужно ассерту.
func _on_physics_tick(_delta: float) -> void:
	pass


func _run(world: World) -> void:
	# --- 0. Зона стоит в хабе и смотрит на слой игрока ----------------------
	var hub := HUB_SCENE.instantiate()
	var zone := hub.get_node_or_null("DecayShelter") as DecayShelter
	_check("в хабе есть DecayShelter", zone != null)
	if zone:
		_check("зона ловит слой игрока", zone.collision_mask & 2 != 0, str(zone.collision_mask))
		_check("зона сама не коллайдер", zone.collision_layer == 0, str(zone.collision_layer))
	hub.free()

	# Отдельная зона под проверку: хаб тащит тела и врага, которым здесь не место.
	var shelter := DecayShelter.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 8)
	shape.shape = box
	shape.position.y = 2.0
	shelter.add_child(shape)
	shelter.collision_layer = 0
	shelter.collision_mask = 2
	add_child(shelter)

	var player := PLAYER_SCENE.instantiate() as E_Player
	world.add_entity(player)
	player.global_position = OUTSIDE
	await _physics(SETTLE_FRAMES)
	var life := player.get_component(C_Lifespan) as C_Lifespan

	# --- 1. Вне зоны — распад как прежде ------------------------------------
	_check("вне зоны маркера нет", not player.has_component(C_Sheltered))
	life.current = 30.0
	ECS.process(1.0, "gameplay")
	_check("вне зоны запас убывает", is_equal_approx(life.current, 29.0), str(life.current))

	# --- 2. Вошёл — копится, не убывает, до максимума -----------------------
	player.global_position = Vector3(0, 1, 0)
	await _physics(SETTLE_FRAMES)
	_check("в зоне маркер стоит", player.has_component(C_Sheltered))
	var rate := shelter.refill_rate
	ECS.process(1.0, "gameplay")
	_check(
		"в зоне запас растёт темпом зоны",
		is_equal_approx(life.current, 29.0 + rate),
		"%s, ждали %s" % [life.current, 29.0 + rate]
	)
	ECS.process(1000.0, "gameplay")
	var maximum := life.effective_max(player)
	_check("выше максимума не доливает", is_equal_approx(life.current, maximum), str(life.current))

	# --- 3. Излишек замораживается, а не срезается и не утекает -------------
	life.current = maximum + 20.0
	ECS.process(1.0, "gameplay")
	_check("излишек в зоне не тронут", is_equal_approx(life.current, maximum + 20.0), str(life.current))

	# --- 4. Во плоти доливаются оба кармана: и тела, и души -----------------
	life.current = 15.0
	var decay := C_BodyDecay.new()
	player.add_component(decay)
	decay.remaining = 5.0
	ECS.process(1.0, "gameplay")
	_check(
		"во плоти растёт карман тела",
		is_equal_approx(decay.remaining, 5.0 + rate),
		str(decay.remaining)
	)
	_check(
		"во плоти растёт и запас души",
		is_equal_approx(life.current, 15.0 + rate),
		str(life.current)
	)
	player.remove_component(C_BodyDecay)
	life.current = 15.0

	# --- 5. Вышел — маркер снят, распад снова идёт --------------------------
	player.global_position = OUTSIDE
	await _physics(SETTLE_FRAMES)
	_check("вне зоны маркер снят", not player.has_component(C_Sheltered))
	ECS.process(1.0, "gameplay")
	_check("после выхода запас снова убывает", is_equal_approx(life.current, 14.0), str(life.current))

	# --- 6. Зона выгрузилась вместе со слоем, пока игрок внутри -------------
	player.global_position = Vector3(0, 1, 0)
	await _physics(SETTLE_FRAMES)
	_check("снова в зоне", player.has_component(C_Sheltered))
	shelter.queue_free()
	await _physics(SETTLE_FRAMES)
	_check(
		"выгрузка зоны снимает маркер — бессмертия после ухода со слоя нет",
		not player.has_component(C_Sheltered)
	)
