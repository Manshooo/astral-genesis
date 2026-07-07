# res://src/systems/gameplay/s_fpsLook.gd
# Пример как система читает настройки через SettingsManager — без @export
class_name S_FPSLook
extends System

func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_FPSCamera]).iterate([C_PlayerInput, C_FPSCamera]).with_none([C_UIBlocked])

func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var s := SettingsManager.settings  

	var input_comps: Array = components[0]
	var camera_comps: Array = components[1]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		if inp.mouse_delta == Vector2.ZERO:
			continue

		var cam_comp := camera_comps[i] as C_FPSCamera
		var player := entities[i] as E_Player

		player.rotate_y(-inp.mouse_delta.x * s.mouse_sensitivity)

		cam_comp.pitch = clamp(
			cam_comp.pitch - inp.mouse_delta.y * s.mouse_sensitivity,
			-s.pitch_limit,
			s.pitch_limit
		)
		player.camera.rotation.x = cam_comp.pitch

		inp.mouse_delta = Vector2.ZERO
