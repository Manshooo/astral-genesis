extends Node3D

var yaw := 0.0
var pitch := 0.0

func _input(event):
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			var sens = SettingsManager.get_mouse_sensitivity()
			yaw -= event.relative.x * sens
			pitch -= event.relative.y * sens
			pitch = clamp(pitch, -1.4, 1.4)
			rotation.y = yaw
			rotation.x = pitch
