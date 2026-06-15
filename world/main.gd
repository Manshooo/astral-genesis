# main.gd
extends Node

@onready var world: World = $World

func _ready():
	ECS.world = world
	var entity = Entity.new()
	ECS.world.add_entity(entity, [C_Health.new(100), C_Velocity.new()])

func _process(delta):
	ECS.process(delta)
