# res://src/world/main.gd
extends Node

@onready var world: World = $World

func _ready() -> void:
	ECS.world = world
	PauseHandler.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	ECS.process(delta, "input")
	ECS.process(delta, "gameplay")

func _physics_process(delta: float) -> void:
	ECS.process(delta, "physics")
