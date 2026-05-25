extends Node3D

@onready var yaw_node = $CamYaw
@onready var pitch_node = $CamYaw/CamPitch
@onready var camera = $CamYaw/CamPitch/PlayerCamera

var yaw: float = 0
var pitch: float = 0

func _input(event: InputEvent):
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			var sens = SettingsManager.get_mouse_sensitivity()
			yaw -= event.relative.x * sens
			pitch -= event.relative.y * sens
			pitch = clamp(pitch, -1.4, 1.4)
			rotation.y = yaw
			rotation.x = pitch
