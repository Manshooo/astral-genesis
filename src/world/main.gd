# res://src/world/main.gd
extends Node

@onready var world: World = $World

const HUD_SCENE := preload("res://src/ui/hud/hud.tscn")

func _ready() -> void:
	ECS.world = world
	UIManager.enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_child(HUD_SCENE.instantiate())

func _process(delta: float) -> void:
	ECS.process(delta, "input")
	ECS.process(delta, "gameplay")

func _physics_process(delta: float) -> void:
	ECS.process(delta, "physics")
