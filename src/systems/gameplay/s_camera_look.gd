# res://src/systems/gameplay/s_camera_look.gd
# Группа "gameplay": взгляд крутится каждый ОТРИСОВАННЫЙ кадр (камера с частотой физики дёргается). Мышь крутит опору
# камеры (C_ThirdPersonCamera), а не тело: тело поворачивается по направлению передвижения (S_BodyTurn). Чувствительность —
# SettingsManager, предел тангажа — GameConfig. Вики: [[Вид от третьего лица]].
class_name S_CameraLook
extends System


func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput, C_ThirdPersonCamera]).iterate([C_PlayerInput, C_ThirdPersonCamera]).with_none([C_UIBlocked])


func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var s := SettingsManager.settings
	var gc := GameConfig.config
	var input_comps: Array = components[0]
	var view_comps: Array = components[1]

	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		if inp.mouse_delta == Vector2.ZERO:
			continue
		var view := view_comps[i] as C_ThirdPersonCamera
		if view.yaw == INF:
			view.yaw = (entities[i] as Node as Node3D).global_rotation.y
		view.yaw = wrapf(view.yaw - inp.mouse_delta.x * s.mouse_sensitivity, -PI, PI)
		view.pitch = clampf(view.pitch - inp.mouse_delta.y * s.mouse_sensitivity, -gc.pitch_limit, gc.pitch_limit)
		inp.mouse_delta = Vector2.ZERO
