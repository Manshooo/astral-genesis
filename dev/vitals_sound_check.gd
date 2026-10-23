extends "res://dev/check_harness.gd"
## Проверка звуков модели тела: удар захвата (`S_BodySnatch` → `C_BodySnatch.capture_event`) и петля
## распада (`S_DecaySound`/`C_DecaySound`). Запуск: godot --headless dev/vitals_sound_check.tscn
##
## Оба ломаются тихо: захват, который не просит звук, и петля, которая не вступает у порога или не глохнет
## над ним, ошибки не бросают. Запрос звука наблюдается по `AudioManager.event_requested` — он шлётся до
## всякой проверки на загруженный проект; петля после старта подменяется записывающим объектом, поэтому
## проверка не зависит ни от рантайма byProd, ни от собранного проекта звука.
##
## Пороги — у дуги HUD (`UI_HudMood.LOW`), а не литералами: звук обязан вступать вместе с дугой.

const BODY_SCENE := preload("res://src/entities/body/e_body.tscn")


## Записывает, что сделали с петлёй, вместо ByProdEventInstance.
class _LoopRecorder:
	extends RefCounted

	var values: Array[float] = []
	var stopped := false

	func set_parameter(_name: String, value: float) -> void:
		values.append(value)

	func stop() -> void:
		stopped = true


var _requests: Array[String] = []


func _ready() -> void:
	var world := _new_world()
	_add_systems(world, "physics", [S_BodySnatch.new()])
	_add_systems(world, "gameplay", [S_DecaySound.new()])
	AudioManager.event_requested.connect(func(path: String, _position: Vector3) -> void: _requests.append(path))

	_check_capture(world)
	_check_decay(world)

	_finish()


func _check_capture(world: World) -> void:
	var soul := Entity.new()
	soul.component_resources = [C_PlayerInput.new(), C_BodySnatch.new(), C_Lifespan.new()]
	world.add_entity(soul)
	var bs := soul.get_component(C_BodySnatch) as C_BodySnatch

	# --- 1. Неудавшийся захват молчит -------------------------------------
	var body := BODY_SCENE.instantiate()
	world.add_entity(body)
	body.add_component(C_SnatchTargeted.new())
	bs.capture_success_chance = 0.0
	bs.capture_requested = true
	_requests.clear()
	ECS.process(0.016, "physics")
	_check("неудавшийся захват звук не просит", _requests.is_empty(), "запросы: %s" % [_requests])

	# --- 2. Удавшийся — ровно один удар захвата ----------------------------
	bs.capture_success_chance = 1.0
	bs.capture_requested = true
	_requests.clear()
	ECS.process(0.016, "physics")
	_check(
		"удавшийся захват просит событие захвата ровно раз",
		_requests == [bs.capture_event] and soul.has_component(C_Embodied),
		"запросы: %s, во плоти: %s" % [_requests, soul.has_component(C_Embodied)],
	)
	world.remove_entity(soul)


func _check_decay(world: World) -> void:
	var soul := Entity.new()
	soul.component_resources = [C_Lifespan.new(), C_DecaySound.new()]
	world.add_entity(soul)
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	var sound := soul.get_component(C_DecaySound) as C_DecaySound
	var full := life.effective_max(soul)

	# --- 3. Над порогом дуги петля молчит -----------------------------------
	life.current = full * (UI_HudMood.LOW + 0.1)
	_requests.clear()
	ECS.process(0.016, "gameplay")
	_check("над порогом дуги петля распада не заводится", _requests.is_empty() and sound.instance == null,
		"запросы: %s" % [_requests])

	# --- 4. Ниже порога — заводится один раз, а не каждый кадр -------------
	life.current = full * (UI_HudMood.LOW - 0.05)
	ECS.process(0.016, "gameplay")
	var recorder := _LoopRecorder.new()
	sound.instance = recorder
	ECS.process(0.016, "gameplay")
	ECS.process(0.016, "gameplay")
	_check("ниже порога петля заводится ровно раз", _requests == [sound.event_path], "запросы: %s" % [_requests])
	var calm: float = recorder.values.back() if not recorder.values.is_empty() else NAN

	# --- 5. Ближе к нулю — напряжённее, в пределах компонента --------------
	life.current = full * 0.02
	ECS.process(0.016, "gameplay")
	var tense: float = recorder.values.back() if not recorder.values.is_empty() else NAN
	_check(
		"ближе к нулю напряжение петли выше и не выходит за intensity_max",
		calm < tense and tense <= sound.intensity_max and calm >= sound.intensity_calm,
		"у порога %.3f, у нуля %.3f, диапазон %.2f–%.2f" % [calm, tense, sound.intensity_calm, sound.intensity_max],
	)

	# --- 6. Снова над порогом — петля глохнет ------------------------------
	life.current = full
	ECS.process(0.016, "gameplay")
	_check("над порогом петля останавливается и отпускается", recorder.stopped and sound.instance == null,
		"stop: %s" % recorder.stopped)
	world.remove_entity(soul)
