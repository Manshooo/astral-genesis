# res://src/systems/gameplay/s_fps_look.gd
# Группа: "gameplay" — взгляд крутится каждый ОТРИСОВАННЫЙ кадр, а не физтик:
# камера, повёрнутая с частотой физики, дёргается на мониторе чаще 60 Гц. В
# space-state система не ходит, поэтому физическая группа ей не нужна.
#
# Рыскание — на самой сущности (поворачивается весь риг: ходят ногами туда, куда
# смотрят), тангаж — только на камере, чтобы взгляд вверх не заваливал тело и
# маркер на карте. Чувствительность — настройка игрока (SettingsManager), предел
# тангажа — константа дизайна (GameConfig), поэтому и читаются из разных мест.
class_name S_FPSLook
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_FPSCamera]).iterate([C_PlayerInput, C_FPSCamera]).with_none([C_UIBlocked])


func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var s := SettingsManager.settings
	var gc := GameConfig.config

	var input_comps: Array = components[0]
	var camera_comps: Array = components[1]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		if inp.mouse_delta == Vector2.ZERO:
			continue

		var cam_comp := camera_comps[i] as C_FPSCamera
		var player := entities[i] as E_Player

		player.rotate_y(-inp.mouse_delta.x * s.mouse_sensitivity)

		cam_comp.pitch = clampf(
			cam_comp.pitch - inp.mouse_delta.y * s.mouse_sensitivity,
			-gc.pitch_limit,
			gc.pitch_limit
		)
		player.camera.rotation.x = cam_comp.pitch

		inp.mouse_delta = Vector2.ZERO
