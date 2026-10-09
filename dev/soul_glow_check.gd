extends "res://dev/check_harness.gd"
## Свечение души (C_SoulGlow, S_SoulGlow) на настоящем e_player.tscn: на спокойном
## запасе душа светит в полную силу, у порога распада тускнеет, но не гаснет;
## во плоти светит карман тела и янтарём, вне тела — сиреневым, и цвет
## перетекает, а не прыгает.
##
## Ломается это тихо: лампа, до которой система не нашла путь, просто светит
## авторским числом, а свет, читающий не тот карман, гаснет не тогда.
##
## Запускать: godot --headless dev/soul_glow_check.tscn

const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"
const TICK := 0.05


func _ready() -> void:
	var world := _new_world()
	_add_systems(world, "gameplay", [S_SoulGlow.new()])
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	world.add_entity(player)
	await get_tree().process_frame

	var glow := player.get_component(C_SoulGlow) as C_SoulGlow
	var light: Light3D = (player.get_node_or_null(glow.light_path) as Light3D) if glow else null
	_check("у души есть свечение и его лампа", light != null, str(glow.light_path) if glow else "нет C_SoulGlow")
	if light == null:
		_finish()
		return
	var life := player.get_component(C_Lifespan) as C_Lifespan
	var soul_max := life.effective_max(player)

	life.current = soul_max
	_tick(1.0)
	var full := light.light_energy
	_check("на спокойном запасе душа светит в полную силу", is_equal_approx(full, glow.energy_full),
		"%.3f при %.3f" % [full, glow.energy_full])
	_check("вне тела свет сиреневый, как дуга", light.light_color.is_equal_approx(UI_HudMood.SOUL),
		str(light.light_color))

	life.current = soul_max * 0.2
	_tick(TICK)
	var low := light.light_energy
	life.current = soul_max * 0.02
	_tick(TICK)
	var faint := light.light_energy
	_check("у порога распада тускнеет, и чем ближе, тем сильнее", faint < low and low < full,
		"%.3f → %.3f → %.3f" % [full, low, faint])
	_check("на исходе не гаснет совсем", faint >= glow.energy_faded and faint > 0.0, "%.3f" % faint)

	# Во плоти убывает карман тела: душа полна, а тело на исходе — свет тусклый.
	life.current = soul_max
	var decay := C_BodyDecay.new()
	player.add_component(decay)
	decay.remaining = decay.effective_maximum(player) * 0.02
	_tick(TICK)
	_check("во плоти свет следует за карманом тела, а не за душой", light.light_energy < full,
		"%.3f при полной душе" % light.light_energy)
	_check("цвет перетекает к янтарю, а не прыгает",
		not light.light_color.is_equal_approx(UI_HudMood.SOUL) and not light.light_color.is_equal_approx(UI_HudMood.BODY),
		str(light.light_color))
	_tick(1.0)
	_check("во плоти свет янтарный, как дуга", light.light_color.is_equal_approx(UI_HudMood.BODY),
		str(light.light_color))

	_finish()


## Прогоняет группу gameplay мелкими тактами на [param seconds] секунд.
func _tick(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		ECS.process(minf(TICK, left), "gameplay")
		left -= TICK
