extends "res://src/world/main.gd"
## Полигон: настоящий мир игры без комплекса — сцена наследует world.tscn, так что системы, наблюдатели и HUD те же,
## что в забеге, а вместо слоёв плоская арена со станциями, по механике на каждую. Запуск — F6 по этой сцене; станции,
## темп времени и версии клипов — в разделе «Полигон» меню отладки (`ё`). Вики: [[Полигон]].

const ClipSources := preload("res://dev/polygon/clip_sources.gd")
## Темпы времени раздела «Полигон»: медленно смотрят переходы и стыки клипов.
const TIME_SCALES: Array[float] = [1.0, 0.5, 0.25, 0.1]

## Бессмертие с порога: распад выкинул бы из тела посреди просмотра. Выключается F4, как в забеге.
@export var immortal := true
## Захват всегда удаётся: в полигоне смотрят, что будет в теле, а не бросок кубика.
@export var sure_capture := true

## Основные клипы и их версии из dev/polygon/clips/ — общая подмена во всех деревьях полигона.
var clips := ClipSources.new()

@onready var _stations: Node3D = %Stations


func _ready() -> void:
	ECS.world = world
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_child(HUD_SCENE.instantiate())
	add_child(ShadowBudget.new())
	var overlay := _add_debug_overlay()
	if overlay != null:
		overlay.set_immortal(immortal)
	clips.watch(get_tree())
	_spawn_player()
	for station in stations():
		station.setup(self)
	go_to(0)
	UIManager.enabled = true


func _exit_tree() -> void:
	# Темп времени — настройка движка, а не сцены: без сброса меню после выхода жило бы в замедлении.
	Engine.time_scale = 1.0
	# Интерполяцию физики переключает станция камеры, а живёт она на дереве — после полигона вернуть проектную.
	get_tree().physics_interpolation = ProjectSettings.get_setting("physics/common/physics_interpolation", false)
	clips.unwatch()


## Станции — дети узла Stations: у каждой title, маркер Spawn и setup(polygon). Новая механика — новая станция.
func stations() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in _stations.get_children():
		if child.has_method(&"setup"):
			out.append(child as Node3D)
	return out


## Ставит игрока на маркер Spawn станции [param index], лицом туда, куда смотрит маркер. Станция может ответить на
## приход и уход (`arrive()`, `depart()`): так станция камеры забирает кадр только у себя.
func go_to(index: int) -> String:
	var all := stations()
	var station := all[index]
	var spawn := station.get_node("Spawn") as Node3D
	var player := E_Player.find() as Node as Node3D
	if player == null:
		return "игрока нет"
	player.global_position = spawn.global_position + PlayerPlacement.lift(player)
	player.global_rotation = Vector3(0.0, spawn.global_rotation.y, 0.0)
	# Перенос — телепорт: с интерполяцией физики риг иначе проехал бы через полигон за один тик.
	player.reset_physics_interpolation()
	for other in all:
		if other != station and other.has_method(&"depart"):
			other.depart()
	if station.has_method(&"arrive"):
		station.arrive()
	return station.title


func set_time_scale(value: float) -> String:
	Engine.time_scale = value
	return "темп времени ×%s" % value


## Раздел «Полигон» меню отладки: { "title", "call" → строка-отчёт, "close" — закрыть меню до вызова }.
func debug_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var all := stations()
	for i in all.size():
		entries.append({"title": "Станция: %s" % all[i].title, "call": go_to.bind(i), "close": true})
	for value in TIME_SCALES:
		var mark := "● " if is_equal_approx(Engine.time_scale, value) else ""
		entries.append({"title": "%sТемп времени ×%s" % [mark, value], "call": set_time_scale.bind(value)})
	# Пульт станции — её записи (станция камеры: режимы камеры); меню их только рисует.
	for station in all:
		if station.has_method(&"debug_entries"):
			entries.append_array(station.debug_entries())
	for official in clips.officials:
		var versions := clips.variants_of(official)
		if versions.is_empty():
			continue
		var stem := official.get_file().get_basename()
		var mark := "" if clips.chosen.has(official) else "● "
		entries.append({"title": "%s%s: основные" % [mark, stem], "call": _choose_clips.bind(official, "")})
		for version in versions:
			mark = "● " if clips.chosen.get(official, "") == version.path else ""
			entries.append({"title": "%s%s: %s" % [mark, stem, version.title], "call": _choose_clips.bind(official, version.path)})
	entries.append({"title": "Перечитать клипы с диска", "call": _reload_clips})
	return entries


func _choose_clips(official: String, variant: String) -> String:
	clips.choose(official, variant)
	return "%s: %s" % [official.get_file().get_basename(), variant.get_file().get_basename() if variant != "" else "основные"]


## Перевыгрузка из Blender видна после импорта редактором: переключиться в него, вернуться в игру и перечитать.
func _reload_clips() -> String:
	clips.reload(true)
	clips.sweep()
	return "клипы перечитаны, версий: %d" % clips.variants.size()


## Душа — как в начале забега (RunManager._spawn_player): перки поверх новой души и полный запас после них.
func _spawn_player() -> void:
	var player := (load(RunManager.PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	SkillManager.reapply_all()
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life != null:
		life.current = life.effective_max(player)
	var snatch := player.get_component(C_BodySnatch) as C_BodySnatch
	if snatch != null and sure_capture:
		snatch.capture_success_chance = 1.0
