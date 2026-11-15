extends Node3D
## Мат: тело лежит наготове — вселиться и смотреть облик со спины, клипы хода, прыжок. Захват
## поглощает тело, как в забеге; новое кладёт пульт рядом. Вики: [[Полигон]].

## Какое тело класть.
@export var body_scene: PackedScene

var body: E_Body

@onready var _point: Marker3D = %BodyPoint


## Кладёт тело на мат, если прежнее поглощено; true — положено новое.
func lay_body() -> bool:
	if is_instance_valid(body) and ECS.world.entities.has(body):
		return false
	var entity := body_scene.instantiate() as E_Body
	# Место до add_child: рэгдолл тела стартует в его _ready.
	entity.transform = _point.transform
	add_child(entity)
	ECS.world.add_entity(entity)
	body = entity
	return true
