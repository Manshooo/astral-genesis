# res://src/systems/physics/s_playerMovement.gd
class_name S_PlayerMovement
extends System

func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_Velocity]).iterate([C_PlayerInput, C_Velocity])

func process(entities: Array[Entity], components: Array, delta: float) -> void:
	var s := SettingsManager.settings

	var input_comps: Array = components[0]
	var velocity_comps: Array = components[1]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		var vel := velocity_comps[i] as C_Velocity
		var player := entities[i] as E_Player

		if not player.is_on_floor():
			vel.velocity.y -= GameConfig.config.gravity * delta
		else:
			vel.velocity.y = max(vel.velocity.y, 0.0)

		if inp.jump_pressed:
			if player.is_on_floor():
				vel.velocity.y = s.jump_velocity
			inp.jump_pressed = false

		if inp.move_direction != Vector3.ZERO:
			var wish = (player.transform.basis * inp.move_direction).normalized()
			vel.velocity.x = wish.x * s.move_speed
			vel.velocity.z = wish.z * s.move_speed
		else:
			vel.velocity.x = 0.0
			vel.velocity.z = 0.0
