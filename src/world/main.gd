# res://src/world/main.gd
extends Node

@onready var world: World = $World

func _ready() -> void:
	ECS.world = world
	print (ECS.world)

func _process(delta: float) -> void:
	# Ввод и логика — в обычном process
	ECS.process(delta, "input")
	ECS.process(delta, "gameplay")

func _physics_process(delta: float) -> void:
	# Физика (move_and_slide) — обязательно в physics_process,
	# иначе движение будет дёргаться и is_on_floor() врёт
	ECS.process(delta, "physics")
