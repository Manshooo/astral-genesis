extends Node3D
## Ряд тел разных габаритов: вселиться и смотреть, как опора и плечо камеры идут за формой. Захват поглощает тело,
## как в забеге; пульт докладывает недостающие. Вики: [[Полигон]].

## Положено новое тело — станция выдаёт ему копии материалов с дизером.
signal laid(body: E_Body)

## Какие тела класть: по маркеру-ребёнку на каждое, в порядке детей.
@export var bodies: Array[PackedScene] = []

## Тело на каждом маркере; поглощённое захватом — освобождённый объект.
var laid_bodies: Array = []


## Кладёт тела на пустые маркеры; возвращает, сколько положено.
func lay_bodies() -> int:
	var points := find_children("*", "Marker3D", false, false)
	laid_bodies.resize(bodies.size())
	var count := 0
	for i in mini(bodies.size(), points.size()):
		# Без типа: поглощённое тело уже освобождено, а в типизированную переменную его не присвоить.
		var old: Variant = laid_bodies[i]
		if is_instance_valid(old) and ECS.world.entities.has(old):
			continue
		var entity := bodies[i].instantiate() as E_Body
		# Место до add_child: рэгдолл тела стартует в его _ready.
		entity.transform = (points[i] as Node3D).transform
		add_child(entity)
		ECS.world.add_entity(entity)
		laid_bodies[i] = entity
		laid.emit(entity)
		count += 1
	return count
