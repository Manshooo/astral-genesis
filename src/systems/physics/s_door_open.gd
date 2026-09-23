# res://src/systems/physics/s_door_open.gd
# Группа: "physics". Поднимает полотно открытой двери (C_DoorOpen).
#
# Полотно — AnimatableBody3D из .glb двери (коллизия едет вместе с мешем), и
# двигать его правильно в физическом кадре: тело с sync_to_physics переносится
# шагом физики, и сдвиг из обычного _process давал бы полотну на кадр
# расходиться со своей же коллизией. Сдвигаем не тело, а узел Visual целиком:
# визуал и тело в нём — одна вещь, и имя Visual одно на все сущности проекта
# (конвенция арт-пайплайна).
#
# Кривая — «быстро стартует, мягко садится»: гермозатвор, а не лифт.
class_name S_DoorOpen
extends System


func query() -> QueryBuilder:
	return q.with_all([C_DoorOpen])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var door := entity.get_component(C_DoorOpen) as C_DoorOpen
		if door.progress >= 1.0:
			continue
		door.progress = minf(1.0, door.progress + delta / maxf(door.duration, 0.001))
		var visual := entity.get_node_or_null(^"Visual") as Node3D
		if visual:
			visual.position.y = door.lift * ease(door.progress, 0.4)
