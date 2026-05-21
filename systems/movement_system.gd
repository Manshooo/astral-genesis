# systems/movement_system.gd
extends Node

func process(delta: float):
    for entity in get_tree().get_nodes_in_group("entities"):
        if entity.has_node("VelocityComponent") and entity is CharacterBody2D:
            var vel = entity.get_node("VelocityComponent")
            entity.velocity = vel.value
            entity.move_and_slide()
