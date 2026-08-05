class_name A_UsePortal
extends A_TravelThroughDoor
## Вертикальный переход между слоями комплекса. Механически это ровно тот же
## переход по ребру графа, что и дверь, — отличается только тем, какие рёбра ему
## достаются (RunManager._bind_portals отдаёт порталам рёбра со сменой глубины) и
## как он об этом говорит. Поэтому наследуемся от A_TravelThroughDoor, а не
## дублируем проверки замка/заглушки: разъехаться им нельзя.


func _sealed_message() -> String:
	return "Портал мёртв: он никуда не ведёт"


func _locked_message(key: StringName) -> String:
	return "Портал заблокирован. Нужен %s" % _key_name(key)


func _class_label() -> String:
	return "A_UsePortal"
