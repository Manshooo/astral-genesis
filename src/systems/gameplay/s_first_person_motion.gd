# res://src/systems/gameplay/s_first_person_motion.gd
# Группа "gameplay": ставит камеру туда, где голова облика (стоя, на рыси, в беге, в укусе — по C_FirstPersonMotion
# тела), качает её в такт клипу хода и клюёт ею при укусе. Камера сдвигается узлом — лучи атаки и захвата идут из
# головы; у стены её держит EyeReach (SpringArm3D кастует сам в своём физкадре — запроса в space-state отсюда нет,
# Jolt на потоке). Качка — h_offset/v_offset, только картинка. Тангаж пишется каждый кадр: S_FPSLook пишет его лишь
# при движении мыши. Вики: [[Захват тела]].
class_name S_FirstPersonMotion
extends System

## Как быстро качка и положение головы следуют за сменой аллюра, 1/с.
const GAIT_BLEND := 8.0

const EYE_REACH := ^"EyeReach"


func query() -> QueryBuilder:
	return q.with_all([C_FPSCamera])


func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_FPSLook, S_BodyAnimation]}


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var player := entity as E_Player
		if player == null or player.camera == null:
			continue
		var camera := player.camera
		var look := entity.get_component(C_FPSCamera) as C_FPSCamera
		if look.eye_position == Vector3.INF:
			look.eye_position = camera.position
		var motion := entity.get_component(C_FirstPersonMotion) as C_FirstPersonMotion
		# Без характеристики (душа, тело без неё) камера стоит в базе: так снимается и остаток после выхода из тела.
		var sway := _gait(entity, motion, delta) if motion else Vector3.ZERO
		var bite := _bite(entity, motion, delta) if motion else 0.0
		var head := Vector3.ZERO
		if motion:
			head = motion.stand_head \
				+ (motion.trot_head - motion.stand_head) * motion.trot_weight \
				+ (motion.run_head - motion.stand_head) * motion.run_weight \
				+ (motion.bite_head - motion.stand_head) * bite

		# Настройка игрока гасит только качку и клевок; где голова — место глаз, его она не трогает.
		var strength := SettingsManager.settings.camera_motion
		camera.position = look.eye_position + _reach(player, motion, look.eye_position, head)
		camera.h_offset = sway.x * strength
		camera.v_offset = sway.y * strength
		camera.rotation.x = look.pitch - (deg_to_rad(motion.bite_dip) * bite * strength if motion else 0.0)
		camera.rotation.z = sway.z * strength


## Смещение головы, укороченное стеной. Каст всегда на самую длинную голову тела: длину, которой каст шёл, отсюда не
## узнать (физкадр реже кадра), а с постоянной длиной «упёрлись» — это просто хит короче неё.
func _reach(player: E_Player, motion: C_FirstPersonMotion, base: Vector3, head: Vector3) -> Vector3:
	var arm := player.get_node_or_null(EYE_REACH) as SpringArm3D
	var length := head.length()
	if arm == null or length < 0.001:
		if arm:
			arm.spring_length = 0.0
		return head
	var dir := head / length
	var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK
	arm.transform = Transform3D(Basis.looking_at(-dir, up), base)  # SpringArm3D кастует по своей +Z
	var longest := 0.0
	for point in [motion.stand_head, motion.trot_head, motion.run_head, motion.bite_head]:
		longest = maxf(longest, (point as Vector3).length())
	arm.spring_length = longest
	return dir * minf(length, arm.get_hit_length())


## Качка по фазе клипа, который играет облик: x — вбок, y — вверх, z — крен. Фаза клипа, а не пройденный путь, —
## чтобы просадка совпадала с лапами рук-муляжа в кадре.
func _gait(entity: Entity, motion: C_FirstPersonMotion, delta: float) -> Vector3:
	var anim := entity.get_component(C_BodyAnimation) as C_BodyAnimation
	var tree := RS_EntityVisuals.animation_tree(entity)
	var playback: AnimationNodeStateMachinePlayback = null
	if tree != null and tree.active:
		playback = tree.get(S_BodyAnimation.STATE) as AnimationNodeStateMachinePlayback

	var state := anim.state if anim else &""
	var blend := 1.0 - exp(-GAIT_BLEND * delta)
	motion.walk_weight = lerpf(motion.walk_weight, 1.0 if state == &"walk" else 0.0, blend)
	motion.trot_weight = lerpf(motion.trot_weight, 1.0 if state == &"trot" else 0.0, blend)
	motion.run_weight = lerpf(motion.run_weight, 1.0 if state == &"run" else 0.0, blend)
	if playback == null or playback.get_current_length() <= 0.0:
		return Vector3.ZERO

	var phase := playback.get_current_play_position() / playback.get_current_length()
	var side := sin(TAU * phase)
	# Рысь качает с амплитудой шага: две просадки за цикл, по опоре на каждую ногу.
	var drop := motion.walk_bob.x * (motion.walk_weight * _dip(phase, motion.walk_bounces, motion.walk_low)
		+ motion.trot_weight * _dip(phase, motion.walk_bounces, motion.trot_low)) \
		+ motion.run_weight * motion.run_bob.x * _dip(phase, motion.run_bounces, motion.run_low)
	var lean := (motion.walk_weight + motion.trot_weight) * motion.walk_bob.y + motion.run_weight * motion.run_bob.y
	return Vector3(lean * side, -drop, motion.run_weight * deg_to_rad(motion.run_roll) * side)


## 0 — камера наверху, 1 — в нижней точке; bounces просадок за цикл, нижняя — в доле цикла low.
func _dip(phase: float, bounces: int, low: float) -> float:
	return 0.5 + 0.5 * cos(TAU * bounces * (phase - low))


## Глубина выпада укуса 0..1. Укус узнаём по сбросу перезарядки C_Attack, как S_BodyAnimation.
func _bite(entity: Entity, motion: C_FirstPersonMotion, delta: float) -> float:
	var attack := entity.get_component(C_Attack) as C_Attack
	if attack != null:
		if attack.cooldown_left > motion.last_cooldown + 0.01:
			motion.bite_left = motion.bite_time
		motion.last_cooldown = attack.cooldown_left
	motion.bite_left = maxf(motion.bite_left - delta, 0.0)
	if motion.bite_left <= 0.0 or motion.bite_time <= 0.0:
		return 0.0
	var t := 1.0 - motion.bite_left / motion.bite_time
	if t < motion.bite_peak:
		return sin(PI * 0.5 * t / motion.bite_peak)
	return 0.5 + 0.5 * cos(PI * (t - motion.bite_peak) / (1.0 - motion.bite_peak))
