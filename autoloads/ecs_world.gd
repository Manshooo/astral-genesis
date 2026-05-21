# autoloads/ecs_world.gd
extends Node

@onready var movement = preload("res://systems/movement_system.gd").new()
# @onready var damage = preload("res://systems/damage_system.gd").new()

func _ready():
	add_child(movement)
	# add_child(damage)

func _process(delta):
	movement.process(delta)
	# damage.process(delta)
