# res://src/ui/hud/hud_message.gd
## Экранное сообщение: короткий текст-реакция на действие («Заперто…»,
## «Прохода нет»). Показывается, пока на игроке висит C_ScreenMessage; снимает
## его по таймеру S_ScreenMessage.
##
## Реагируем на добавление/снятие компонента через сигналы мира — тем же
## паттерном, что crosshair.gd и hud_prompt.gd.
##
## Скрипт — на ПОДЛОЖКЕ (PanelContainer), а не на самом Label: подложка нужна
## ровно тогда, когда есть сообщение, иначе на экране висела бы пустая плашка.
## show()/hide() self прячут подложку целиком вместе с текстом — тот же приём,
## что у hud_prompt.gd и hud_abilities.gd.
class_name UI_HudMessage
extends PanelContainer

@onready var _label: Label = $Message


func _ready() -> void:
	hide()
	if ECS.world:
		_connect_world_signals(ECS.world)
	ECS.world_changed.connect(_on_world_changed)


func _on_world_changed(world: World) -> void:
	hide()
	if world:
		_connect_world_signals(world)


func _connect_world_signals(world: World) -> void:
	if not world.component_added.is_connected(_on_component_added):
		world.component_added.connect(_on_component_added)
	if not world.component_removed.is_connected(_on_component_removed):
		world.component_removed.connect(_on_component_removed)


func _on_component_added(_entity: Entity, component: Variant) -> void:
	if not (component is C_ScreenMessage):
		return
	_label.text = (component as C_ScreenMessage).text
	show()


func _on_component_removed(_entity: Entity, component: Variant) -> void:
	if component is C_ScreenMessage:
		hide()
