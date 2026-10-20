class_name A_UsePortal
extends A_TravelThroughDoor
## Вертикальный переход между слоями — тот же переход по ребру графа, что у двери, но с рёбрами со сменой
## глубины (LayerStreamer._bind_portals). Наследуем A_TravelThroughDoor, чтобы проверки замка не разъехались.


func _sealed_message() -> String:
	return tr("HUD_MSG_PORTAL_SEALED")


func _locked_message(key: StringName) -> String:
	return tr("HUD_MSG_PORTAL_LOCKED_NEEDS") % _key_name(key)


func _class_label() -> String:
	return "A_UsePortal"
